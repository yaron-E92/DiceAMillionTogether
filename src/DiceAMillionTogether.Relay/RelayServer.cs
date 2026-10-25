using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace DiceAMillionTogether.Relay;

/// <summary>
/// Drop-in .NET replacement for Multidice's Python relay. It preserves the
/// GameMaker client protocol: uint32-le length + UTF-8 JSON (protocol v1).
/// </summary>
public sealed class RelayServer(IPAddress bindAddress, int port) : IAsyncDisposable
{
    private const int Protocol = 1;
    private const int MaxFrameBytes = 65536;
    private static readonly TimeSpan HelloTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan IdleTimeout = TimeSpan.FromMinutes(5);
    private const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private readonly TcpListener _listener = new(bindAddress, port);
    private readonly CancellationTokenSource _stop = new();
    private readonly object _gate = new();
    private readonly Dictionary<string, Room> _rooms = new(StringComparer.Ordinal);
    private readonly HashSet<Peer> _clients = new();

    public int Port => ((IPEndPoint)_listener.LocalEndpoint).Port;
    public Task Completion { get; private set; } = Task.CompletedTask;

    public void Start()
    {
        _listener.Start();
        Completion = AcceptLoopAsync(_stop.Token);
    }

    private async Task AcceptLoopAsync(CancellationToken cancellation)
    {
        try
        {
            while (!cancellation.IsCancellationRequested)
            {
                TcpClient socket = await _listener.AcceptTcpClientAsync(cancellation);
                socket.NoDelay = true;
                var client = new Peer(socket);
                lock (_gate) _clients.Add(client);
                _ = HandleAsync(client, cancellation);
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (ObjectDisposedException) when (cancellation.IsCancellationRequested) { }
    }

    private sealed class Peer(TcpClient socket) : IDisposable
    {
        private readonly SemaphoreSlim _writeGate = new(1, 1);
        private readonly NetworkStream _stream = socket.GetStream();
        public Room? Room;
        public string Role = "";
        public NetworkStream Stream => _stream;

        public async Task SendBytesAsync(ReadOnlyMemory<byte> payload, CancellationToken cancellation)
        {
            if (payload.Length is < 1 or > MaxFrameBytes)
                throw new InvalidDataException("Invalid outgoing frame length.");

            await _writeGate.WaitAsync(cancellation);
            try
            {
                byte[] header = new byte[4];
                BinaryPrimitives.WriteUInt32LittleEndian(header, (uint)payload.Length);
                await _stream.WriteAsync(header, cancellation);
                await _stream.WriteAsync(payload, cancellation);
            }
            finally
            {
                _writeGate.Release();
            }
        }

        public Task SendJsonAsync(object message, CancellationToken cancellation)
            => SendBytesAsync(JsonSerializer.SerializeToUtf8Bytes(message), cancellation);

        public void Dispose()
        {
            socket.Dispose();
            // _writeGate is intentionally not disposed: an in-flight write may
            // release it after a peer is forcibly disconnected.
        }
    }

    private sealed record Room(string Code, Peer Host)
    {
        public Peer? Guest;
    }

    private static string? StringProp(JsonElement json, string key) =>
        json.ValueKind == JsonValueKind.Object &&
        json.TryGetProperty(key, out var value) &&
        value.ValueKind == JsonValueKind.String ? value.GetString() : null;

    private static async Task<byte[]> ReadFrameAsync(
        Stream stream, TimeSpan timeout, CancellationToken cancellation)
    {
        using var limit = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        limit.CancelAfter(timeout);

        var header = new byte[4];
        await stream.ReadExactlyAsync(header, limit.Token);
        uint size = BinaryPrimitives.ReadUInt32LittleEndian(header);
        if (size is 0 or > MaxFrameBytes)
            throw new InvalidDataException($"Invalid incoming frame size: {size}");

        var payload = new byte[(int)size];
        await stream.ReadExactlyAsync(payload, limit.Token);
        return payload;
    }

    private static bool TryParse(byte[] bytes, out JsonDocument? document)
    {
        try
        {
            document = JsonDocument.Parse(bytes);
            return document.RootElement.ValueKind == JsonValueKind.Object;
        }
        catch (JsonException)
        {
            document = null;
            return false;
        }
    }

    private async Task ErrorAsync(Peer peer, string message, CancellationToken cancellation)
        => await peer.SendJsonAsync(new { type = "ERROR", msg = message }, cancellation);

    private string CreateCode()
    {
        lock (_gate)
        {
            while (true)
            {
                char[] value = new char[6];
                for (int i = 0; i < value.Length; i++)
                    value[i] = CodeAlphabet[RandomNumberGenerator.GetInt32(CodeAlphabet.Length)];
                string code = new(value);
                if (!_rooms.ContainsKey(code)) return code;
            }
        }
    }

    private async Task<bool> JoinAsync(Peer peer, string? requested, CancellationToken cancellation)
    {
        Room? room;
        bool full = false;
        string code = (requested ?? "").Trim().ToUpperInvariant();
        lock (_gate)
        {
            if (_rooms.TryGetValue(code, out room))
            {
                if (room.Guest is not null) full = true;
                else
                {
                    room.Guest = peer;
                    peer.Room = room;
                    peer.Role = "guest";
                }
            }
        }

        if (room is null || full)
        {
            await ErrorAsync(peer, full ? "room full" : "room not found", cancellation);
            return false;
        }

        await peer.SendJsonAsync(new { type = "ROOM", code, role = "guest" }, cancellation);
        await room.Host.SendJsonAsync(new { type = "PEER_JOINED" }, cancellation);
        return true;
    }

    private async Task BrowseAsync(Peer peer, CancellationToken cancellation)
    {
        while (!cancellation.IsCancellationRequested && peer.Room is null)
        {
            byte[] frame = await ReadFrameAsync(peer.Stream, IdleTimeout, cancellation);
            if (!TryParse(frame, out var doc) || doc is null)
            {
                await ErrorAsync(peer, "browse frame not JSON", cancellation);
                continue;
            }

            using (doc)
            {
                string? messageType = StringProp(doc.RootElement, "type");
                if (messageType == "LIST_REQUEST")
                {
                    string[] codes;
                    lock (_gate)
                        codes = _rooms.Values.Where(r => r.Guest is null)
                            .Select(r => r.Code).OrderBy(x => x, StringComparer.Ordinal).ToArray();
                    await peer.SendJsonAsync(new { type = "LOBBIES", codes }, cancellation);
                }
                else if (messageType == "JOIN")
                {
                    await JoinAsync(peer, StringProp(doc.RootElement, "code"), cancellation);
                }
                else
                    await ErrorAsync(peer, $"unknown browse msg {messageType}", cancellation);
            }
        }
    }

    private async Task HandleAsync(Peer peer, CancellationToken cancellation)
    {
        try
        {
            byte[] hello = await ReadFrameAsync(peer.Stream, HelloTimeout, cancellation);
            if (!TryParse(hello, out var first) || first is null)
            {
                await ErrorAsync(peer, "HELLO not JSON", cancellation);
                return;
            }

            string? mode;
            string? code;
            using (first)
            {
                var root = first.RootElement;
                if (StringProp(root, "type") != "HELLO")
                {
                    await ErrorAsync(peer, "first frame must be HELLO", cancellation);
                    return;
                }
                if (!root.TryGetProperty("proto", out var proto) ||
                    !proto.TryGetInt32(out var version) || version != Protocol)
                {
                    await ErrorAsync(peer, $"proto mismatch, relay={Protocol}", cancellation);
                    return;
                }
                mode = StringProp(root, "mode");
                code = StringProp(root, "code");
            }

            if (mode == "create")
            {
                var roomCode = CreateCode();
                lock (_gate)
                {
                    var room = new Room(roomCode, peer);
                    _rooms.Add(roomCode, room);
                    peer.Room = room;
                    peer.Role = "host";
                }
                await peer.SendJsonAsync(new { type = "ROOM", code = roomCode, role = "host" }, cancellation);
            }
            else if (mode == "join")
            {
                if (!await JoinAsync(peer, code, cancellation)) return;
            }
            else if (mode == "list")
            {
                await BrowseAsync(peer, cancellation);
            }
            else
            {
                await ErrorAsync(peer, "bad mode", cancellation);
                return;
            }

            while (!cancellation.IsCancellationRequested)
            {
                byte[] payload = await ReadFrameAsync(peer.Stream, IdleTimeout, cancellation);
                if (TryParse(payload, out var message) && message is not null)
                {
                    using (message)
                    {
                        // The old relay captures LOG messages in a server-side
                        // file. Do not forward those logs, but also don't store
                        // potentially sensitive local game logs on the relay.
                        if (StringProp(message.RootElement, "type") == "LOG")
                            continue;
                    }
                }
                else
                {
                    message?.Dispose();
                }

                Peer? other = null;
                lock (_gate)
                {
                    if (peer.Room is { } room)
                        other = ReferenceEquals(room.Host, peer) ? room.Guest : room.Host;
                }
                if (other is null)
                {
                    await ErrorAsync(peer, "no peer yet", cancellation);
                    continue;
                }
                await other.SendBytesAsync(payload, cancellation);
            }
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
        catch (OperationCanceledException) { /* HELLO / idle timeout */ }
        catch (EndOfStreamException) { /* clean disconnect */ }
        catch (IOException) { /* remote socket disconnected */ }
        catch (SocketException) { /* remote socket disconnected */ }
        catch (ObjectDisposedException) { /* server closed peer */ }
        catch (InvalidDataException) { /* malformed frame: close connection */ }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"Relay client error: {ex.GetType().Name}: {ex.Message}");
        }
        finally
        {
            Room? room = null;
            Peer? other = null;
            lock (_gate)
            {
                _clients.Remove(peer);
                room = peer.Room;
                if (room is not null && _rooms.Remove(room.Code))
                {
                    other = ReferenceEquals(room.Host, peer) ? room.Guest : room.Host;
                    room.Host.Room = null;
                    if (room.Guest is not null) room.Guest.Room = null;
                }
                peer.Room = null;
            }

            if (other is not null)
            {
                try
                {
                    await other.SendJsonAsync(new { type = "PEER_LEFT" }, CancellationToken.None)
                        .WaitAsync(TimeSpan.FromSeconds(2));
                }
                catch (Exception) { /* peer already gone */ }
                other.Dispose(); // original protocol closes the whole room
            }
            peer.Dispose();
        }
    }

    public async ValueTask DisposeAsync()
    {
        _stop.Cancel();
        _listener.Stop();
        lock (_gate)
        {
            foreach (var peer in _clients) peer.Dispose();
            _clients.Clear();
            _rooms.Clear();
        }
        try { await Completion; }
        catch (OperationCanceledException) { }
        _stop.Dispose();
    }
}
