using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Threading.Channels;
using Steamworks;
using Steamworks.Data;

namespace DiceAMillionTogether.SteamBridge;

/// <summary>
/// Local GameMaker TCP protocol server + actual Steam lobbies and P2P transport.
/// Neither the game nor its proprietary files need a native plugin.
/// </summary>
public sealed class SteamBridgeServer(uint gameAppId) : IDisposable
{
    private const string CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
    private const string LobbyMarker = "dmt_protocol";
    private const string LobbyCode = "dmt_code";
    private readonly TcpListener _local = new(IPAddress.Loopback, 7777);
    private readonly CancellationTokenSource _stop = new();
    private GameSession? _game;
    private Lobby? _lobby;
    private HostSocket? _hostSocket;
    private GuestConnection? _guestConnection;
    private Connection? _hostPeerConnection;
    private bool _connected;
    private TaskCompletionSource<bool>? _guestConnected;

    public async Task RunAsync(CancellationToken cancellation)
    {
        // Do not permit a silent fallback to raw network connections if Steam
        // initialization fails: the GameMaker UI will receive a local ERROR.
        SteamClient.Init(gameAppId, asyncCallbacks: false);
        if (!SteamClient.IsLoggedOn)
            throw new InvalidOperationException("Steam client is not logged on.");

        _local.Start();
        Console.WriteLine($"Steam P2P bridge ready for {SteamClient.Name} ({SteamClient.SteamId})");
        Console.WriteLine("Listening on 127.0.0.1:7777. No router port forward or relay server needed.");
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _stop.Token);
        var pump = PumpAsync(linked.Token);
        try
        {
            while (!linked.IsCancellationRequested)
            {
                TcpClient tcp = await _local.AcceptTcpClientAsync(linked.Token);
                if (_game is not null)
                {
                    tcp.Dispose();
                    continue;
                }

                // Do not await here: Steam callbacks must continue pumping while
                // a game socket is waiting for lobby creation or P2P connection.
                _ = RunLocalAsync(tcp, linked.Token);
            }
        }
        catch (OperationCanceledException) when (linked.IsCancellationRequested) { }
        finally
        {
            linked.Cancel();
            try { await pump; } catch (OperationCanceledException) { }
            _game?.Close();
            ResetSteamSession();
        }
    }

    private async Task PumpAsync(CancellationToken cancellation)
    {
        while (!cancellation.IsCancellationRequested)
        {
            SteamClient.RunCallbacks();
            _hostSocket?.Receive();
            _guestConnection?.Receive();
            await Task.Delay(16, cancellation);
        }
    }

    private async Task RunLocalAsync(TcpClient tcp, CancellationToken cancellation)
    {
        using (tcp)
        using (var local = new GameSession(tcp))
        {
            _game = local;
            local.StartWriter(cancellation);
            try
            {
                using var hello = GameFrame.Parse(await GameFrame.ReadAsync(tcp.GetStream(), cancellation));
                var root = hello.RootElement;
                if (Get(root, "type") != "HELLO")
                {
                    local.Send(new { type = "ERROR", msg = "first frame must be HELLO" });
                    return;
                }
                if (!root.TryGetProperty("proto", out var proto) || proto.GetInt32() != 1)
                {
                    local.Send(new { type = "ERROR", msg = "proto mismatch, bridge=1" });
                    return;
                }
                switch (Get(root, "mode"))
                {
                    case "create":
                        await CreateLobbyAsync(local, cancellation);
                        break;
                    case "join":
                        await JoinCodeAsync(local, Get(root, "code"), cancellation);
                        break;
                    case "list":
                        break;
                    default:
                        local.Send(new { type = "ERROR", msg = "bad mode" });
                        return;
                }

                while (!cancellation.IsCancellationRequested)
                {
                    byte[] data = await GameFrame.ReadAsync(tcp.GetStream(), cancellation);
                    using var doc = GameFrame.Parse(data);
                    var message = doc.RootElement;
                    string? type = Get(message, "type");

                    // The GameMaker client can browse lobbies before selecting a code.
                    if (type == "LIST_REQUEST")
                    {
                        var results = await FindLobbiesAsync(null);
                        local.Send(new { type = "LOBBIES",
                            codes = results.Select(x => x.GetData(LobbyCode))
                                .Where(x => !string.IsNullOrWhiteSpace(x)).Distinct().ToArray() });
                    }
                    else if (type == "JOIN" && _lobby is null)
                        await JoinCodeAsync(local, Get(message, "code"), cancellation);
                    else if (type == "LOG")
                    {
                        // Never send debug logs to other players.
                    }
                    else if (_connected)
                        SendSteam(data);
                    else
                        local.Send(new { type = "ERROR", msg = "Steam peer not connected" });
                }
            }
            catch (EndOfStreamException) { }
            catch (IOException) { }
            catch (SocketException) { }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"Game socket error: {ex.Message}");
                local.Send(new { type = "ERROR", msg = "Steam bridge failed: " + ex.Message });
            }
            finally
            {
                // Give any pending terminal error time to be flushed before close.
                await local.FinishAsync();
                ResetSteamSession();
                if (ReferenceEquals(_game, local)) _game = null;
            }
        }
    }

    private static string? Get(System.Text.Json.JsonElement root, string key) =>
        root.TryGetProperty(key, out var prop) && prop.ValueKind == System.Text.Json.JsonValueKind.String
            ? prop.GetString() : null;

    private static string NewCode() =>
        new(Enumerable.Range(0, 6).Select(_ => CodeAlphabet[RandomNumberGenerator.GetInt32(CodeAlphabet.Length)]).ToArray());

    private async Task CreateLobbyAsync(GameSession game, CancellationToken ct)
    {
        Lobby? created = await SteamMatchmaking.CreateLobbyAsync(2).WaitAsync(TimeSpan.FromSeconds(20), ct);
        if (created is null)
        {
            game.Send(new { type = "ERROR", msg = "Steam lobby creation failed (game's Steamworks configuration may block lobbies)" });
            return;
        }

        _lobby = created.Value;
        string code = NewCode();
        _hostSocket = SteamNetworkingSockets.CreateRelaySocket<HostSocket>();
        _hostSocket.Bridge = this;
        if (!_lobby.Value.SetData(LobbyMarker, "1")
            || !_lobby.Value.SetData(LobbyCode, code)
            || !_lobby.Value.SetPublic()
            || !_lobby.Value.SetJoinable(true))
            throw new InvalidOperationException("Could not publish Steam lobby metadata.");
        game.Send(new { type = "ROOM", code, role = "host" });
        Console.WriteLine($"Steam lobby created: {code} / {_lobby.Value.Id}");
    }

    private static async Task<Lobby[]> FindLobbiesAsync(string? code)
    {
        var query = SteamMatchmaking.LobbyList
            .WithKeyValue(LobbyMarker, "1")
            .FilterDistanceWorldwide();
        if (!string.IsNullOrEmpty(code))
            query = query.WithKeyValue(LobbyCode, code);
        var result = await query.WithMaxResults(100).RequestAsync();
        return result ?? Array.Empty<Lobby>();
    }

    private async Task JoinCodeAsync(GameSession game, string? requested, CancellationToken ct)
    {
        string code = (requested ?? "").Trim().ToUpperInvariant();
        if (code.Length != 6 || code.Any(ch => !CodeAlphabet.Contains(ch)))
        {
            game.Send(new { type = "ERROR", msg = "Invalid six-character lobby code" });
            return;
        }
        var lobbies = await FindLobbiesAsync(code).WaitAsync(TimeSpan.FromSeconds(20), ct);
        if (lobbies.Length == 0)
        {
            game.Send(new { type = "ERROR", msg = "Steam lobby not found. Check game ownership/version." });
            return;
        }
        Lobby? joined = await SteamMatchmaking.JoinLobbyAsync(lobbies[0].Id)
            .WaitAsync(TimeSpan.FromSeconds(20), ct);
        if (joined is null || joined.Value.GetData(LobbyMarker) != "1")
        {
            game.Send(new { type = "ERROR", msg = "Cannot join Steam lobby" });
            return;
        }
        _lobby = joined;
        _guestConnected = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _guestConnection = SteamNetworkingSockets.ConnectRelay<GuestConnection>(_lobby.Value.Owner.Id);
        _guestConnection.Bridge = this;
        await _guestConnected.Task.WaitAsync(TimeSpan.FromSeconds(25), ct);
        game.Send(new { type = "ROOM", code, role = "guest" });
        Console.WriteLine($"Steam lobby joined: {code}");
    }

    private bool IsLobbyGuest(SteamId id)
    {
        var lobby = _lobby;
        if (lobby is null || lobby.Value.Owner.Id != SteamClient.SteamId)
            return false;
        return lobby.Value.Members.Any(friend => friend.Id == id && friend.Id != SteamClient.SteamId);
    }

    private void OnHostConnected(Connection connection)
    {
        _hostPeerConnection = connection;
        _connected = true;
        _game?.Send(new { type = "PEER_JOINED" });
        Console.WriteLine("Steam P2P guest connected.");
    }

    private void OnGuestConnected()
    {
        _connected = true;
        _guestConnected?.TrySetResult(true);
        Console.WriteLine("Steam P2P host connected.");
    }

    private void OnSteamDisconnected()
    {
        _connected = false;
        _guestConnected?.TrySetException(new IOException("Steam P2P peer disconnected."));
        _game?.Send(new { type = "PEER_LEFT" });
    }

    private void SendSteam(byte[] payload)
    {
        if (payload.Length is < 1 or > GameFrame.MaximumLength)
            throw new InvalidDataException("Steam packet length rejected.");

        Result result;
        if (_hostPeerConnection is { } conn)
            result = conn.SendMessage(payload, SendType.Reliable);
        else if (_guestConnection is { Connected: true } guest)
            result = guest.Connection.SendMessage(payload, SendType.Reliable);
        else
            throw new IOException("Steam P2P connection is not ready.");
        if (result != Result.OK)
            throw new IOException($"Steam send failed: {result}");
    }

    private void OnSteamMessage(IntPtr data, int size)
    {
        if (!_connected || size is <= 0 or > GameFrame.MaximumLength) return;
        var payload = new byte[size];
        Marshal.Copy(data, payload, 0, size);
        _game?.Send(payload);
    }

    private void ResetSteamSession()
    {
        _connected = false;
        _guestConnected?.TrySetCanceled();
        _guestConnected = null;
        _hostPeerConnection = null;
        _guestConnection?.Close();
        _guestConnection = null;
        _hostSocket?.Close();
        _hostSocket = null;
        if (_lobby is { } lobby) lobby.Leave();
        _lobby = null;
    }

    public void Dispose()
    {
        _stop.Cancel();
        _local.Stop();
        _game?.Close();
        ResetSteamSession();
        if (SteamClient.IsValid) SteamClient.Shutdown();
        _stop.Dispose();
    }

    // Facepunch SteamNetworkingSockets callbacks are run by PumpAsync.
    private sealed class HostSocket : SocketManager
    {
        public SteamBridgeServer? Bridge;
        public override void OnConnecting(Connection connection, ConnectionInfo info)
        {
            if (Bridge is not null && info.Identity.IsSteamId && Bridge.IsLobbyGuest(info.Identity.SteamId))
                connection.Accept();
            else
                connection.Close();
        }

        public override void OnConnected(Connection connection, ConnectionInfo info)
        {
            base.OnConnected(connection, info);
            Bridge?.OnHostConnected(connection);
        }

        public override void OnDisconnected(Connection connection, ConnectionInfo info)
        {
            base.OnDisconnected(connection, info);
            Bridge?.OnSteamDisconnected();
        }

        public override void OnMessage(Connection connection, NetIdentity identity,
            IntPtr data, int size, long messageNum, long recvTime, int channel)
            => Bridge?.OnSteamMessage(data, size);
    }

    private sealed class GuestConnection : ConnectionManager
    {
        public SteamBridgeServer? Bridge;
        public override void OnConnected(ConnectionInfo info)
        {
            base.OnConnected(info);
            Bridge?.OnGuestConnected();
        }

        public override void OnDisconnected(ConnectionInfo info)
        {
            base.OnDisconnected(info);
            Bridge?.OnSteamDisconnected();
        }

        public override void OnMessage(IntPtr data, int size, long messageNum, long recvTime, int channel)
            => Bridge?.OnSteamMessage(data, size);
    }

    private sealed class GameSession(TcpClient tcp) : IDisposable
    {
        private readonly Channel<byte[]> _outgoing = Channel.CreateUnbounded<byte[]>(new UnboundedChannelOptions
        {
            SingleReader = true, SingleWriter = false
        });
        private Task _writing = Task.CompletedTask;
        private readonly CancellationTokenSource _close = new();

        public void StartWriter(CancellationToken cancellation)
        {
            _writing = Task.Run(async () =>
            {
                using var linked = CancellationTokenSource.CreateLinkedTokenSource(_close.Token, cancellation);
                await foreach (byte[] msg in _outgoing.Reader.ReadAllAsync(linked.Token))
                    await GameFrame.WriteAsync(tcp.GetStream(), msg, linked.Token);
            }, CancellationToken.None);
        }

        public void Send(object value) => Send(GameFrame.Json(value));
        public void Send(byte[] data) => _outgoing.Writer.TryWrite(data);

        public async Task FinishAsync()
        {
            _outgoing.Writer.TryComplete();
            try { await _writing.WaitAsync(TimeSpan.FromSeconds(2)); }
            catch (OperationCanceledException) { }
            catch (TimeoutException) { }
            catch (IOException) { }
        }

        public void Close() => _close.Cancel();
        public void Dispose() => _close.Dispose();
    }
}
