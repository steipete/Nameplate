using System.Text.Json;
using System.Text.Json.Serialization;
using Nameplate.Core;
using Xunit;

namespace Nameplate.Core.Tests;

public sealed class TagPositionTests
{
    private sealed record Vector(
        string Name, TagPosition Position, double Width, double Height, double TagWidth, double TagHeight,
        double Inset, double HorizontalOffset, double VerticalOffset, double X, double Y);

    [Fact]
    public void SharedPlacementVectors()
    {
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        options.Converters.Add(new JsonStringEnumConverter());
        var vectors = JsonSerializer.Deserialize<Vector[]>(
            File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "tag-placement.json")), options)!;
        foreach (var v in vectors)
        {
            var origin = TagPlacement.Origin(v.Position, v.Width, v.Height, v.TagWidth, v.TagHeight,
                v.Inset, v.HorizontalOffset, v.VerticalOffset);
            Assert.True(origin == (v.X, v.Y), v.Name);
        }
    }

    [Theory]
    [InlineData("topLeft", TagPosition.TopLeft)]
    [InlineData("topCenter", TagPosition.TopCenter)]
    [InlineData("topRight", TagPosition.TopRight)]
    [InlineData("leftCenter", TagPosition.LeftCenter)]
    [InlineData("rightCenter", TagPosition.RightCenter)]
    [InlineData("bottomLeft", TagPosition.BottomLeft)]
    [InlineData("bottomCenter", TagPosition.BottomCenter)]
    [InlineData("bottomRight", TagPosition.BottomRight)]
    public void ExistingKeyAcceptsCornersAndCenters(string raw, TagPosition position)
    {
        var json = $$$"""{"layers":{"tagCorner":"{{{raw}}}","tagHorizontalOffset":1200,"tagVerticalOffset":-600}}""";
        var settings = JsonSerializer.Deserialize<LocalSettings>(json)!;
        Assert.Equal(position, settings.Layers.TagCorner);
        Assert.Equal(1200, settings.Layers.TagHorizontalOffset);
        Assert.Equal(-600, settings.Layers.TagVerticalOffset);
        Assert.Equal(settings, JsonSerializer.Deserialize<LocalSettings>(JsonSerializer.Serialize(settings)));
        Assert.Equal(ScreenCorner.BottomRight, settings.Layers.WatermarkCorner);
    }

    [Theory]
    [InlineData(0, TagPosition.TopLeft)]
    [InlineData(1, TagPosition.TopRight)]
    [InlineData(2, TagPosition.BottomLeft)]
    [InlineData(3, TagPosition.BottomRight)]
    public void LegacyNumericCornersKeepTheirMeaning(int value, TagPosition expected)
    {
        var json = $$$"""{"layers":{"tagCorner":{{{value}}}}}""";
        Assert.Equal(expected, JsonSerializer.Deserialize<LocalSettings>(json)!.Layers.TagCorner);
    }

    [Fact]
    public void NonFiniteOffsetsAreNeutral()
    {
        Assert.Equal((880d, 335d), TagPlacement.Origin(TagPosition.RightCenter,
            1000, 700, 100, 30, 20, double.NaN, double.PositiveInfinity));
    }
}
