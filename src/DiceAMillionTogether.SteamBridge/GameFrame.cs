using System.Buffers.Binary;
using System.Text.Json;

namespace DiceAMillionTogether.SteamBridge;

/// <summary>
/// The unmodified GameMaker co-op script uses precisely this framing.
/// Steam NetworkingSockets transports just the JSON payload, reliably.
/// </summary>
public static class GameFrame
{
    public const int MaximumLength = 65536;

    public static async ValueTask<byte[]> ReadAsync(Stream stream, CancellationToken ct)
    {
        byte[] header = new byte[4];
        await stream.ReadExactlyAsync(header, ct);
        uint length = BinaryPrimitives.ReadUInt32LittleEndian(header);
        if (length is 0 or > MaximumLength)
            throw new InvalidDataException($"Invalid frame length {length}.");
        byte[] payload = new byte[(int)length];
        await stream.ReadExactlyAsync(payload, ct);
        return payload;
    }

    public static async Task WriteAsync(Stream stream, ReadOnlyMemory<byte> payload, CancellationToken ct)
    {
        if (payload.Length is 0 or > MaximumLength)
            throw new InvalidDataException("Invalid outbound frame.");
        byte[] header = new byte[4];
        BinaryPrimitives.WriteUInt32LittleEndian(header, (uint)payload.Length);
        await stream.WriteAsync(header, ct);
        await stream.WriteAsync(payload, ct);
    }

    public static byte[] Json(object value) => JsonSerializer.SerializeToUtf8Bytes(value);

    public static JsonDocument Parse(byte[] value)
    {
        var doc = JsonDocument.Parse(value);
        if (doc.RootElement.ValueKind != JsonValueKind.Object)
        {
            doc.Dispose();
            throw new InvalidDataException("Expected JSON object.");
        }
        return doc;
    }
}
