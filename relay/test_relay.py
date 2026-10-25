"""Smoke test for the relay: host creates a room, guest joins, they exchange a frame.

Override the relay address with env vars:
    RELAY_HOST=your.relay.example PORT=7777 python3 test_relay.py
"""
import asyncio
import json
import os
import struct

HOST = os.environ.get("RELAY_HOST", "127.0.0.1")
PORT = int(os.environ.get("RELAY_PORT", "7777"))


def pack(obj: dict) -> bytes:
    data = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return struct.pack("<I", len(data)) + data


async def read_frame(reader: asyncio.StreamReader) -> dict:
    hdr = await reader.readexactly(4)
    (ln,) = struct.unpack("<I", hdr)
    body = await reader.readexactly(ln)
    return json.loads(body.decode("utf-8"))


async def main() -> None:
    # host connects
    hr, hw = await asyncio.open_connection(HOST, PORT)
    hw.write(pack({"type": "HELLO", "proto": 1, "mod": "test", "mode": "create"}))
    await hw.drain()
    room_msg = await read_frame(hr)
    print("host got:", room_msg)
    code = room_msg["code"]
    assert room_msg["role"] == "host"

    # guest connects using the code
    gr, gw = await asyncio.open_connection(HOST, PORT)
    gw.write(pack({"type": "HELLO", "proto": 1, "mod": "test", "mode": "join", "code": code}))
    await gw.drain()
    guest_room = await read_frame(gr)
    print("guest got:", guest_room)
    assert guest_room["role"] == "guest"

    # host should see PEER_JOINED
    host_peer_msg = await read_frame(hr)
    print("host got:", host_peer_msg)
    assert host_peer_msg["type"] == "PEER_JOINED"

    # host -> guest game message
    hw.write(pack({"t": "hello-from-host"}))
    await hw.drain()
    got = await read_frame(gr)
    print("guest got from host:", got)
    assert got["t"] == "hello-from-host"

    # guest -> host
    gw.write(pack({"t": "hi-host"}))
    await gw.drain()
    got = await read_frame(hr)
    print("host got from guest:", got)
    assert got["t"] == "hi-host"

    # guest disconnects, host should see PEER_LEFT
    gw.close()
    await gw.wait_closed()
    left = await read_frame(hr)
    print("host got:", left)
    assert left["type"] == "PEER_LEFT"
    hw.close()
    await hw.wait_closed()
    print("all relay checks passed")


if __name__ == "__main__":
    asyncio.run(main())
