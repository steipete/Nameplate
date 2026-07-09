using Nameplate.Core;
using Xunit;

namespace Nameplate.Core.Tests;

public sealed class CoreTests
{
    [Theory]
    [InlineData("megaclaw", 0)]
    [InlineData("clawmac", 5)]
    [InlineData("studio-1", 1)]
    [InlineData("win-fleet-07", 6)]
    [InlineData("ubuntu", 2)]
    [InlineData("desktop-3xk9", 5)]
    [InlineData("peters-mac-studio-1", 7)]
    public void DefaultColorMatchesMacParity(string host, int paletteIndex)
    {
        Assert.Equal(NameplatePalette.Colors[paletteIndex], NameplatePalette.DefaultColor(host));
    }

    [Theory]
    [InlineData("Megaclaw.local", "megaclaw")]
    [InlineData(" megaclaw.fritz.box ", "megaclaw")]
    [InlineData("DESKTOP-3XK9", "desktop-3xk9")]
    [InlineData("", "")]
    public void HostnameShorteningMatchesMac(string input, string expected)
    {
        Assert.Equal(expected, Hostnames.Short(input));
    }

    [Fact]
    public void FleetJsonParsesAndNormalizesKeys()
    {
        const string json = """
            {
              "MEGACLAW.local": {
                "name": "MEGACLAW",
                "color": "#1D9E75",
                "glyph": "🦞",
                "futureSetting": true
              }
            }
            """;

        var entries = FleetFile.Parse(json);
        var entry = Assert.Single(entries).Value;
        Assert.Equal("MEGACLAW", entry.Name);
        Assert.Equal("#1D9E75", entry.Color);
        Assert.Equal("🦞", entry.Glyph);
        Assert.Same(entry, FleetFile.Entry(entries, "megaclaw.example.com"));
    }

    [Fact]
    public void MalformedFleetJsonIsIgnored()
    {
        Assert.Empty(FleetFile.Parse("{ definitely not json"));
    }

    [Theory]
    [InlineData("#abc", "#AABBCC")]
    [InlineData(" 3fa ", "#33FFAA")]
    [InlineData("#33fFaA", "#33FFAA")]
    [InlineData("##abc", null)]
    [InlineData("#12", null)]
    [InlineData("#12345g", null)]
    public void HexNormalizationMatchesMac(string input, string? expected)
    {
        Assert.Equal(expected, ColorHex.Normalize(input));
    }

    [Fact]
    public void PillTextUsesMacLuminanceThreshold()
    {
        Assert.True(ColorHex.PrefersDarkText("#EF9F27"));
        Assert.True(ColorHex.PrefersDarkText("#8BC34A"));
        Assert.False(ColorHex.PrefersDarkText("#1D9E75"));
    }

    [Fact]
    public void LayerDefaultsUseSquareFrameCorners()
    {
        var layers = new LayerSettings();

        Assert.False(layers.RoundTopLeft);
        Assert.False(layers.RoundTopRight);
        Assert.False(layers.RoundBottomLeft);
        Assert.False(layers.RoundBottomRight);
    }

    [Fact]
    public void AttentionRequestJsonRoundTrips()
    {
        var request = new AttentionRequest
        {
            Message = "Unlock 1Password",
            Title = "Agent attention",
            Duration = 9.5,
            Color = "#D4537E",
        };

        Assert.Equal(request, AttentionRequest.FromJson(request.ToJson()));
    }
}
