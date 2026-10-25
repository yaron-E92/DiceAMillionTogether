using System.Net;
using DiceAMillionTogether.Relay;

var host = Environment.GetEnvironmentVariable("DMT_BIND") ?? "127.0.0.1";
var portText = Environment.GetEnvironmentVariable("DMT_PORT") ?? "7777";
if (!IPAddress.TryParse(host, out var address) ||
    !int.TryParse(portText, out var port) || port is < 1 or > 65535)
{
    Console.Error.WriteLine("Invalid relay config. Set DMT_BIND to an IP and DMT_PORT to 1..65535.");
    return 2;
}

using var stop = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    stop.Cancel();
};

await using var server = new RelayServer(address, port);
server.Start();
Console.WriteLine($"DiceAMillionTogether relay listening on {address}:{server.Port} (protocol v1)");
Console.WriteLine("WARNING: Plain TCP without authentication. Bind only to trusted LAN/VPN interfaces.");
try
{
    await server.Completion.WaitAsync(stop.Token);
}
catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
return 0;
