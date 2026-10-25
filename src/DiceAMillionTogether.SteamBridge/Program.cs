using DiceAMillionTogether.SteamBridge;
using Steamworks;

const uint gameAppId = 3430340;

if (args.Contains("--probe", StringComparer.Ordinal))
{
    // Test the publisher-controlled Steamworks capability BEFORE running the
    // GameMaker patcher or trying a full two-client session.
    try
    {
        SteamClient.Init(gameAppId, asyncCallbacks: false);
        if (!SteamClient.IsLoggedOn)
            throw new InvalidOperationException("Steam API initialized, but account is not logged on.");

        Console.WriteLine($"Steam user: {SteamClient.Name} ({SteamClient.SteamId}) / app {gameAppId}");
        Console.WriteLine("Attempting to create a real Steam lobby for Dice A Million...");
        var request = SteamMatchmaking.CreateLobbyAsync(2);
        using var limit = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        while (!request.IsCompleted)
        {
            limit.Token.ThrowIfCancellationRequested();
            SteamClient.RunCallbacks();
            await Task.Delay(20, limit.Token);
        }

        var lobby = await request;
        if (lobby is null)
            throw new InvalidOperationException(
                "Steam lobby creation failed. This may be disabled by the game's publisher.");
        try
        {
            if (!lobby.Value.SetData("dmt_protocol", "1"))
                throw new InvalidOperationException("Steam lobby metadata write failed.");
            using var listener = new ProbeSocketScope();
            Console.WriteLine($"PASS: Steam lobby {lobby.Value.Id} created and metadata written.");
            Console.WriteLine("PASS: Steam relay P2P listener created.");
            Console.WriteLine("NEXT: test two owned Steam accounts to verify actual P2P connectivity.");
        }
        finally { lobby.Value.Leave(); }

        return 0;
    }
    catch (Exception ex)
    {
        Console.Error.WriteLine($"STEAM CAPABILITY PROBE FAILED: {ex.GetType().Name}: {ex.Message}");
        Console.Error.WriteLine("No game files were modified. A publisher-disabled Steamworks capability cannot be bypassed.");
        return 2;
    }
    finally { if (SteamClient.IsValid) SteamClient.Shutdown(); }
}

using var stopped = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) => { e.Cancel = true; stopped.Cancel(); };
try
{
    using var server = new SteamBridgeServer(gameAppId);
    await server.RunAsync(stopped.Token);
    return 0;
}
catch (Exception ex)
{
    Console.Error.WriteLine($"STEAM BRIDGE FAILED: {ex}");
    Console.Error.WriteLine("Steam must be running, with a logged-in account owning Dice A Million.");
    Console.Error.WriteLine("This game may not enable Steam matchmaking for external mods.");
    return 1;
}
