using System.Net;
using System.Net.Sockets;
using System.Text.Json;

namespace DiceAMillionTogether.SteamBridge;

/// <summary>
/// Two-machine real Steam transport diagnostic without GameMaker/UTMT.
/// This deliberately connects to the same localhost GameMaker-facing port
/// and uses its actual binary JSON framing; it does not mock Steam traffic.
/// </summary>
public static class SteamPeerSmoke
{
    private static readonly TimeSpan ConnectTimeout = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan PairingTimeout = TimeSpan.FromMinutes(4);
    private static readonly TimeSpan MessageTimeout = TimeSpan.FromSeconds(45);
    private const string Marker = "dmt-steam-p2p-smoke-v1";

    public static async Task RunAsync(string[] args, CancellationToken cancellation)
    {
        bool host = args.Length == 1 && args[0] == "--smoke-host";
        bool guest = args.Length == 2 && args[0] == "--smoke-join";
        if (!host && !guest)
            throw new ArgumentException("Usage: --smoke-host OR --smoke-join SIX_CHARACTER_CODE");

        string? roomCode = null;
        if (guest)
        {
            roomCode = args[1].Trim().ToUpperInvariant();
            if (roomCode.Length != 6 || roomCode.Any(c =>
                !("ABCDEFGHJKLMNPQRSTUVWXYZ23456789".Contains(c))))
                throw new ArgumentException("Join code must contain six lobby-code characters.");
        }

        using var tcp = new TcpClient();
        using var connectLimit = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        connectLimit.CancelAfter(ConnectTimeout);
        // SteamBridgeServer.RunAsync binds its localhost listener synchronously
        // before yielding; no retry-on-a-failed-TcpClient socket is needed.
        await tcp.ConnectAsync(IPAddress.Loopback, 7777, connectLimit.Token);

        var stream = tcp.GetStream();
        await SendAsync(stream, new
        {
            type = "HELLO",
            proto = 1,
            mod = Marker,
            mode = host ? "create" : "join",
            code = roomCode ?? ""
        }, cancellation);

        using JsonDocument joined = await ReceiveAsync(stream, PairingTimeout, cancellation);
        Expect(joined, "ROOM");
        string confirmedCode = joined.RootElement.GetProperty("code").GetString() ?? "";
        ExpectValue(joined, "role", host ? "host" : "guest");
        if (host)
        {
            Console.WriteLine($"LOBBY CODE: {confirmedCode}");
            Console.WriteLine("On your second PC, run: dotnet run --project src/DiceAMillionTogether.SteamBridge -c Release -- --smoke-join " + confirmedCode);
            Console.WriteLine("Waiting for the second Steam account (up to four minutes)...");
        }
        else if (!string.Equals(confirmedCode, roomCode, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The joined Steam lobby code did not match.");
        }

        if (host)
        {
            using var paired = await ReceiveAsync(stream, PairingTimeout, cancellation);
            Expect(paired, "PEER_JOINED");
            Console.WriteLine("PASS: remote Steam guest joined.");
            await SendAsync(stream, new { type = "DMT_SMOKE", marker = Marker, from = "host" }, cancellation);
            using var ack = await ReceiveAsync(stream, MessageTimeout, cancellation);
            ExpectValue(ack, "type", "DMT_SMOKE_ACK");
            ExpectValue(ack, "marker", Marker);
            ExpectValue(ack, "from", "guest");
            Console.WriteLine("PASS: guest received host payload and returned an authenticated Steam P2P response.");
            await SendAsync(stream, new { type = "DMT_SMOKE_DONE", marker = Marker, from = "host" }, cancellation);
            using var finalAck = await ReceiveAsync(stream, MessageTimeout, cancellation);
            ExpectValue(finalAck, "type", "DMT_SMOKE_DONE_ACK");
            ExpectValue(finalAck, "marker", Marker);
            Console.WriteLine("PASS: host-to-guest and guest-to-host reliable Steam messages completed.");
            // Keep the Steam socket alive long enough for the remote side to
            // receive a confirmed completion before the local game socket closes.
            await SendAsync(stream, new { type = "DMT_SMOKE_COMPLETE", marker = Marker }, cancellation);
            await Task.Delay(500, cancellation);
        }
        else
        {
            Console.WriteLine("PASS: joined Steam lobby and P2P session.");
            using var message = await ReceiveAsync(stream, MessageTimeout, cancellation);
            ExpectValue(message, "type", "DMT_SMOKE");
            ExpectValue(message, "marker", Marker);
            ExpectValue(message, "from", "host");
            Console.WriteLine("PASS: Steam host payload received.");
            await SendAsync(stream, new { type = "DMT_SMOKE_ACK", marker = Marker, from = "guest" }, cancellation);
            using var done = await ReceiveAsync(stream, MessageTimeout, cancellation);
            ExpectValue(done, "type", "DMT_SMOKE_DONE");
            ExpectValue(done, "marker", Marker);
            await SendAsync(stream, new { type = "DMT_SMOKE_DONE_ACK", marker = Marker, from = "guest" }, cancellation);
            using var complete = await ReceiveAsync(stream, MessageTimeout, cancellation);
            Expect(complete, "DMT_SMOKE_COMPLETE");
            ExpectValue(complete, "marker", Marker);
            Console.WriteLine("PASS: reply reached Steam host and confirmation returned.");
        }
    }

    private static async Task SendAsync(Stream stream, object value, CancellationToken ct)
        => await GameFrame.WriteAsync(stream, GameFrame.Json(value), ct);

    private static async Task<JsonDocument> ReceiveAsync(
        Stream stream, TimeSpan timeout, CancellationToken ct)
    {
        using var linked = CancellationTokenSource.CreateLinkedTokenSource(ct);
        linked.CancelAfter(timeout);
        try
        {
            var payload = await GameFrame.ReadAsync(stream, linked.Token);
            var document = GameFrame.Parse(payload);
            if (document.RootElement.TryGetProperty("type", out var type)
                && type.GetString() == "ERROR")
            {
                string error = document.RootElement.TryGetProperty("msg", out var msg)
                    ? msg.GetString() ?? "unknown" : "unknown";
                document.Dispose();
                throw new InvalidOperationException("Steam bridge returned an ERROR: " + error);
            }
            return document;
        }
        catch (OperationCanceledException) when (!ct.IsCancellationRequested)
        {
            throw new TimeoutException("Timed out waiting for Steam peer or response.");
        }
    }

    private static void Expect(JsonDocument document, string expected)
        => ExpectValue(document, "type", expected);

    private static void ExpectValue(JsonDocument document, string key, string expected)
    {
        if (!document.RootElement.TryGetProperty(key, out var actual)
            || actual.ValueKind != JsonValueKind.String || actual.GetString() != expected)
            throw new InvalidDataException(
                $"Unexpected '{key}', expected '{expected}': {document.RootElement.GetRawText()}");
    }
}
