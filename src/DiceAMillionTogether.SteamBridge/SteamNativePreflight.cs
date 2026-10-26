using System.Runtime.InteropServices;

namespace DiceAMillionTogether.SteamBridge;

/// <summary>
/// Fail with an actionable native dependency error BEFORE Steamworks initialization,
/// so a missing DLL is never misreported as publisher-disabled matchmaking.
/// </summary>
internal static class SteamNativePreflight
{
    public static void Verify()
    {
        if (!OperatingSystem.IsWindows() || !Environment.Is64BitProcess)
            throw new PlatformNotSupportedException(
                "The Steam companion currently requires 64-bit Windows.");

        string path = Path.Combine(AppContext.BaseDirectory, "steam_api64.dll");
        if (!File.Exists(path))
            throw new FileNotFoundException(
                "Steam's native steam_api64.dll was not staged beside the .NET application. " +
                "Restore packages and rebuild the bridge; Facepunch.Steamworks.Library " +
                "2.3.3 should supply it automatically.", path);

        try
        {
            // Loading the absolute path tests architecture and transitive
            // native dependencies; the Steamworks P/Invokes later resolve
            // the same filename through the application directory.
            IntPtr handle = NativeLibrary.Load(path);
            NativeLibrary.Free(handle);
        }
        catch (BadImageFormatException ex)
        {
            throw new InvalidOperationException(
                "steam_api64.dll is not a compatible x64 Windows binary: " + path, ex);
        }
        catch (DllNotFoundException ex)
        {
            throw new InvalidOperationException(
                "steam_api64.dll exists but Windows could not load it or one of its native " +
                "dependencies: " + path, ex);
        }
    }
}
