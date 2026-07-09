using System.Text.Json.Serialization;

namespace Nameplate.Core;

public sealed record LocalSettings
{
    [JsonPropertyName("name")]
    public string? Name { get; init; }

    [JsonPropertyName("color")]
    public string? Color { get; init; }

    [JsonPropertyName("glyph")]
    public string? Glyph { get; init; }

    [JsonPropertyName("layers")]
    public LayerSettings Layers { get; init; } = new();

    [JsonPropertyName("splash")]
    public SplashSettings Splash { get; init; } = new();
}

public sealed record LayerSettings
{
    [JsonPropertyName("frameEnabled")]
    public bool FrameEnabled { get; init; } = true;

    [JsonPropertyName("tagEnabled")]
    public bool TagEnabled { get; init; } = true;

    [JsonPropertyName("watermarkEnabled")]
    public bool WatermarkEnabled { get; init; }

    [JsonPropertyName("frameThickness")]
    public double FrameThickness { get; init; } = 8;

    [JsonPropertyName("frameOpacity")]
    public double FrameOpacity { get; init; } = 0.9;

    [JsonPropertyName("frameCornerRadius")]
    public double FrameCornerRadius { get; init; } = 18;

    [JsonPropertyName("roundTopLeft")]
    public bool RoundTopLeft { get; init; }

    [JsonPropertyName("roundTopRight")]
    public bool RoundTopRight { get; init; }

    [JsonPropertyName("roundBottomLeft")]
    public bool RoundBottomLeft { get; init; }

    [JsonPropertyName("roundBottomRight")]
    public bool RoundBottomRight { get; init; }

    [JsonPropertyName("tagCorner")]
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public ScreenCorner TagCorner { get; init; } = ScreenCorner.BottomLeft;

    [JsonPropertyName("watermarkCorner")]
    [JsonConverter(typeof(JsonStringEnumConverter))]
    public ScreenCorner WatermarkCorner { get; init; } = ScreenCorner.BottomRight;

    [JsonPropertyName("watermarkOpacity")]
    public double WatermarkOpacity { get; init; } = 0.14;
}

public sealed record SplashSettings
{
    [JsonPropertyName("duration")]
    public double Duration { get; init; } = 2.5;

    [JsonPropertyName("onRemoteConnect")]
    public bool OnRemoteConnect { get; init; } = true;

    [JsonPropertyName("onSessionUnlock")]
    public bool OnSessionUnlock { get; init; } = true;
}

public static class IdentityResolver
{
    public static MachineIdentity Resolve(string host, LocalSettings settings, FleetEntry? fleet)
    {
        var shortHost = Hostnames.Short(host);
        var localName = settings.Name?.Trim();
        var name = fleet?.Name ?? (string.IsNullOrEmpty(localName) ? shortHost : localName);
        var defaultColor = NameplatePalette.DefaultColor(shortHost).Hex;
        var color = ColorHex.Normalize(fleet?.Color ?? settings.Color ?? defaultColor) ?? defaultColor;
        var glyph = fleet?.Glyph ?? settings.Glyph?.Trim() ?? string.Empty;
        return new MachineIdentity(name, color, glyph);
    }
}
