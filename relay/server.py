"""
Multidice relay.

TCP, length-prefixed frames: 4-byte little-endian uint32 length + UTF-8 JSON payload.

Service messages (client <-> relay):
  -> {"type":"HELLO","proto":1,"mod":"<ver>","mode":"create"|"join"|"list","code":"ABC123"?}
  <- {"type":"ROOM","code":"ABC123","role":"host"|"guest"}
  <- {"type":"PEER_JOINED"}              # to host when guest arrives
  <- {"type":"PEER_LEFT"}                # peer dropped, room stays open
  <- {"type":"ERROR","msg":"..."}

Browse flow (mode=list):
  -> HELLO mode=list          — keep socket, no room yet
  -> LIST_REQUEST             — ask for open lobbies
  <- LOBBIES {codes:[...]}    — list of rooms with no guest
  -> JOIN {code}              — promote to guest of that room
  <- ROOM + PEER_JOINED        — same as a normal mode=join connection

After pairing, any frame that isn't a service message (type starts with lowercase, or any unknown type)
is forwarded verbatim to the peer. Relay never parses game state.
"""

import asyncio
import json
import logging
import os
import secrets
import string
import struct
import time
from dataclasses import dataclass, field

HOST = "0.0.0.0"
PORT = 7777
PROTO = 1
MAX_FRAME = 1 << 16  # 64 KiB is plenty for this game
ROOM_CODE_LEN = 6
ROOM_CODE_ALPHABET = string.ascii_uppercase.replace("O", "").replace("I", "") + "23456789"
HELLO_TIMEOUT = 10.0
IDLE_TIMEOUT = 300.0  # drop silent sockets so leaked rooms reap themselves
SESSION_LOG = "/opt/multidice-relay/sessions.log"

log = logging.getLogger("relay")


def write_session_line(client: "Client", text: str) -> None:
    """Append a line to the shared session log, tagged with room + role + addr."""
    room_code = client.room.code if client.room else "-"
    role = client.role or "?"
    ts = time.strftime("%Y-%m-%d %H:%M:%S")
    line = f"[{ts}] room={room_code} role={role} addr={client.addr}: {text}\n"
    try:
        with open(SESSION_LOG, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception as e:
        log.warning("session log write failed: %s", e)


@dataclass
class Client:
    writer: asyncio.StreamWriter
    addr: str
    room: "Room | None" = None
    role: str = ""  # "host" or "guest"


@dataclass
class Room:
    code: str
    host: Client
    guest: Client | None = None


rooms: dict[str, Room] = {}


def new_code() -> str:
    while True:
        c = "".join(secrets.choice(ROOM_CODE_ALPHABET) for _ in range(ROOM_CODE_LEN))
        if c not in rooms:
            return c


async def read_frame(reader: asyncio.StreamReader) -> bytes:
    hdr = await reader.readexactly(4)
    (ln,) = struct.unpack("<I", hdr)
    if ln == 0 or ln > MAX_FRAME:
        raise ValueError(f"bad frame length {ln}")
    return await reader.readexactly(ln)


def pack_frame(payload: bytes) -> bytes:
    return struct.pack("<I", len(payload)) + payload


async def send_json(w: asyncio.StreamWriter, obj: dict) -> None:
    data = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    w.write(pack_frame(data))
    await w.drain()


async def send_error(w: asyncio.StreamWriter, msg: str) -> None:
    try:
        await send_json(w, {"type": "ERROR", "msg": msg})
    except Exception:
        pass


def peer_of(room: Room, c: Client) -> Client | None:
    return room.guest if c is room.host else room.host


async def close_room(room: Room, reason: str) -> None:
    log.info("room %s closed: %s", room.code, reason)
    rooms.pop(room.code, None)
    for c in (room.host, room.guest):
        if c is None:
            continue
        try:
            c.writer.close()
        except Exception:
            pass


async def handle_client(reader: asyncio.StreamReader, writer: asyncio.StreamWriter) -> None:
    peer = writer.get_extra_info("peername")
    addr = f"{peer[0]}:{peer[1]}" if peer else "?"
    client = Client(writer=writer, addr=addr)
    log.info("conn %s", addr)

    try:
        try:
            hello_raw = await asyncio.wait_for(read_frame(reader), timeout=HELLO_TIMEOUT)
        except asyncio.TimeoutError:
            await send_error(writer, "HELLO timeout")
            return

        try:
            hello = json.loads(hello_raw.decode("utf-8"))
        except Exception:
            await send_error(writer, "HELLO not JSON")
            return

        if hello.get("type") != "HELLO":
            await send_error(writer, "first frame must be HELLO")
            return
        if hello.get("proto") != PROTO:
            await send_error(writer, f"proto mismatch, relay={PROTO}")
            return

        mode = hello.get("mode")
        if mode == "create":
            code = new_code()
            room = Room(code=code, host=client)
            rooms[code] = room
            client.room = room
            client.role = "host"
            await send_json(writer, {"type": "ROOM", "code": code, "role": "host"})
            log.info("room %s created by %s", code, addr)
        elif mode == "join":
            code = (hello.get("code") or "").strip().upper()
            room = rooms.get(code)
            if room is None:
                await send_error(writer, "room not found")
                return
            if room.guest is not None:
                await send_error(writer, "room full")
                return
            room.guest = client
            client.room = room
            client.role = "guest"
            await send_json(writer, {"type": "ROOM", "code": code, "role": "guest"})
            await send_json(room.host.writer, {"type": "PEER_JOINED"})
            log.info("room %s joined by %s", code, addr)
        elif mode == "list":
            # Browse mode: loop reading LIST_REQUEST / JOIN frames until either
            # the client picks a lobby (→ fall through to main relay loop as
            # guest) or disconnects. No room assignment yet; this socket is
            # idle from the room system's POV.
            log.info("list-mode browse session from %s", addr)
            while client.room is None:
                try:
                    lframe = await asyncio.wait_for(read_frame(reader), timeout=IDLE_TIMEOUT)
                except asyncio.TimeoutError:
                    log.info("browse idle timeout on %s", addr)
                    return
                try:
                    lmsg = json.loads(lframe.decode("utf-8"))
                except Exception:
                    await send_error(writer, "browse frame not JSON")
                    continue
                lt = lmsg.get("type") if isinstance(lmsg, dict) else None
                if lt == "LIST_REQUEST":
                    open_codes = [r.code for r in rooms.values() if r.guest is None]
                    await send_json(writer, {"type": "LOBBIES", "codes": open_codes})
                elif lt == "JOIN":
                    code = (lmsg.get("code") or "").strip().upper()
                    room = rooms.get(code)
                    if room is None:
                        await send_error(writer, "room not found")
                        continue
                    if room.guest is not None:
                        await send_error(writer, "room full")
                        continue
                    # Promote this connection to guest of that room.
                    room.guest = client
                    client.room = room
                    client.role = "guest"
                    await send_json(writer, {"type": "ROOM", "code": code, "role": "guest"})
                    await send_json(room.host.writer, {"type": "PEER_JOINED"})
                    log.info("room %s joined (via browse) by %s", code, addr)
                    break  # leave inner loop → main relay loop
                else:
                    await send_error(writer, f"unknown browse msg {lt}")
        else:
            await send_error(writer, "bad mode")
            return

        # main relay loop: intercept LOG messages locally, forward everything else to peer
        while True:
            try:
                frame = await asyncio.wait_for(read_frame(reader), timeout=IDLE_TIMEOUT)
            except asyncio.TimeoutError:
                log.info("idle timeout on %s", addr)
                break

            # Try to intercept mod LOG messages.
            intercepted = False
            try:
                msg = json.loads(frame.decode("utf-8"))
                if isinstance(msg, dict) and msg.get("type") == "LOG":
                    write_session_line(client, str(msg.get("line", "")))
                    intercepted = True
            except (UnicodeDecodeError, json.JSONDecodeError):
                pass  # not JSON or not ours — just forward verbatim
            if intercepted:
                continue

            peer_c = peer_of(client.room, client)
            if peer_c is None:
                await send_error(writer, "no peer yet")
                continue
            peer_c.writer.write(pack_frame(frame))
            try:
                await peer_c.writer.drain()
            except ConnectionError:
                break

    except (asyncio.IncompleteReadError, ConnectionError):
        pass
    except Exception as e:
        log.exception("error on %s: %s", addr, e)
    finally:
        log.info("disc %s", addr)
        try:
            writer.close()
        except Exception:
            pass
        room = client.room
        if room is not None:
            # notify peer, then close the whole room (simple semantics: drop = end session)
            peer_c = peer_of(room, client)
            if peer_c is not None:
                try:
                    await send_json(peer_c.writer, {"type": "PEER_LEFT"})
                except Exception:
                    pass
            await close_room(room, f"{client.role} disconnected")


async def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )
    server = await asyncio.start_server(handle_client, HOST, PORT)
    log.info("relay listening on %s:%d (proto=%d)", HOST, PORT, PROTO)
    async with server:
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
