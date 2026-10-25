using DiceAMillionTogether.SteamBridge;

const uint gameAppId = 3430340;

using var stopped = new CancellationTokenSource();
Console.CancelKeyPress += (_, args) => { args.Cancel = true; stopped.Cancel(); };

try
{
    using var server = new SteamBridgeServer(gameAppId);
    await server.RunAsync(stopped.Token);
    return 0;
}
catch (Exception e)
{
    Console.Error.WriteLine($"STEAM BRIDGE FAILED: {e}");
    Console.Error.WriteLine("Steam must be running, with a logged-in account owning Dice A Million.");
    Console.Error.WriteLine("This game may not enable Steam matchmaking for external mods.");
    return 1;
}
