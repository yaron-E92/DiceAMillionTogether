using System.Buffers.Binary;
using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using DiceAMillionTogether.Core;
using DiceAMillionTogether.Relay;

static void Check(bool expression, string label)
{
    if (!expression) throw new Exception("FAIL: " + label);
    Console.WriteLine("PASS: " + label);
}

static async Task Send(TcpClient tcp, object json)
{
    byte[] payload = JsonSerializer.SerializeToUtf8Bytes(json);
    byte[] header = new byte[4];
    BinaryPrimitives.WriteUInt32LittleEndian(header, (uint)payload.Length);
    await tcp.GetStream().WriteAsync(header);
    await tcp.GetStream().WriteAsync(payload);
}

static async Task<JsonDocument> Receive(TcpClient tcp)
{
    using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    byte[] header = new byte[4];
    await tcp.GetStream().ReadExactlyAsync(header, timeout.Token);
    uint length = BinaryPrimitives.ReadUInt32LittleEndian(header);
    if (length is < 1 or > 65536) throw new InvalidDataException("Bad relay response size.");
    byte[] content = new byte[(int)length];
    await tcp.GetStream().ReadExactlyAsync(content, timeout.Token);
    return JsonDocument.Parse(content);
}

static string Get(JsonDocument doc, string prop) =>
    doc.RootElement.GetProperty(prop).GetString()!;

static async Task<TcpClient> Connect(int port)
{
    var tcp = new TcpClient();
    await tcp.ConnectAsync(IPAddress.Loopback, port);
    return tcp;
}

// Cross-hand item logic belongs in C#, not GML.
var scoring = CrossHandScoring.Evaluate(
    [new("own", Player.Host, 100m), new("other", Player.Guest, 100m)],
    [CrossHandScoring.GenerousDie(Player.Host)]);
Check(scoring.HostScore == 50m && scoring.GuestScore == 300m && scoring.SharedScore == 350m,
    "Generous Die multiplies own ×0.5 and partner ×3");
Check(scoring.Dice[0].Owner == Player.Host && scoring.Dice[1].Owner == Player.Guest,
    "Dice ownership preserved");

var chained = CrossHandScoring.Evaluate(
    [new("host", Player.Host, 100m), new("guest", Player.Guest, 100m)],
    [CrossHandScoring.GenerousDie(Player.Host), CrossHandScoring.GenerousDie(Player.Guest)]);
Check(chained.HostScore == 150m && chained.GuestScore == 150m,
    "Modifiers from both players stack symmetrically");

bool invalidFailed = false;
try
{
    CrossHandScoring.Evaluate([new("die", Player.Host, 1m)],
        [new CrossHandModifier("invalid", Player.Guest, -1m, 1m)]);
}
catch (ArgumentOutOfRangeException) { invalidFailed = true; }
Check(invalidFailed, "Invalid multiplier rejected");

await using var server = new RelayServer(IPAddress.Loopback, 0);
server.Start();
int port = server.Port;

using var invalid = await Connect(port);
await Send(invalid, new { type = "HELLO", proto = 999, mode = "create" });
using (var response = await Receive(invalid))
    Check(Get(response, "type") == "ERROR", "Wrong protocol rejected");

using var host = await Connect(port);
await Send(host, new { type = "HELLO", proto = 1, mod = "test", mode = "create" });
string code;
using (var response = await Receive(host))
{
    code = Get(response, "code");
    Check(Get(response, "type") == "ROOM" && Get(response, "role") == "host"
        && code.Length == 6, "Room created with six-character code");
}

using var browser = await Connect(port);
await Send(browser, new { type = "HELLO", proto = 1, mod = "test", mode = "list" });
await Send(browser, new { type = "LIST_REQUEST" });
using (var response = await Receive(browser))
{
    Check(Get(response, "type") == "LOBBIES"
          && response.RootElement.GetProperty("codes").EnumerateArray()
            .Any(item => item.GetString() == code),
        "Open room appears in lobby browser");
}

await Send(browser, new { type = "JOIN", code });
using (var response = await Receive(browser))
    Check(Get(response, "type") == "ROOM" && Get(response, "role") == "guest",
        "Browser joins a room");
using (var response = await Receive(host))
    Check(Get(response, "type") == "PEER_JOINED", "Host receives peer join event");

using var third = await Connect(port);
await Send(third, new { type = "HELLO", proto = 1, mod = "test", mode = "join", code });
using (var response = await Receive(third))
    Check(Get(response, "msg") == "room full", "Third player cannot join full room");

await Send(host, new { type = "ROLL_COMMIT", dice = new[] { "alpha", "beta" }, owner = "host" });
using (var response = await Receive(browser))
    Check(Get(response, "type") == "ROLL_COMMIT"
          && response.RootElement.GetProperty("dice").GetArrayLength() == 2,
        "GameMaker roll payload forwarded without modification");

await Send(browser, new { type = "READY", state = true });
using (var response = await Receive(host))
    Check(Get(response, "type") == "READY", "Game message forwarded from guest to host");

await Send(browser, new { type = "LOG", line = "private detail: never forward" });
await Send(browser, new { type = "CHAR_PICK", ide = "example" });
using (var response = await Receive(host))
    Check(Get(response, "type") == "CHAR_PICK", "Private LOG ignored by relay");

browser.Dispose();
using (var response = await Receive(host))
    Check(Get(response, "type") == "PEER_LEFT", "Peer disconnect propagates");

using var checkGone = await Connect(port);
await Send(checkGone, new { type = "HELLO", proto = 1, mod = "test", mode = "join", code });
using (var response = await Receive(checkGone))
    Check(Get(response, "msg") == "room not found", "Disconnected room cleaned up");

Console.WriteLine("All .NET integration and scoring checks passed.");
