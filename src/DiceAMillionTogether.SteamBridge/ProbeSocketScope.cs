using Steamworks;
namespace DiceAMillionTogether.SteamBridge;

/// <summary>
/// Steam-only capability check: validate the game AppID can create an SDR
/// listener. Does not accept peers or modify game files.
/// </summary>
internal sealed class ProbeSocketScope : IDisposable
{
    private readonly Steamworks.SocketManager _socket = SteamNetworkingSockets.CreateRelaySocket<ProbeSocket>();

    public void Dispose() => _socket.Close();

    private sealed class ProbeSocket : Steamworks.SocketManager
    {
        public override void OnConnecting(Steamworks.Data.Connection connection,
            Steamworks.Data.ConnectionInfo info) => connection.Close();
    }
}
