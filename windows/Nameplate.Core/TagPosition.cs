namespace Nameplate.Core;

// `tagCorner` keeps its existing key and corner values; watermark corners stay separate.
public enum TagPosition
{
    TopLeft = 0, TopCenter = 4, TopRight = 1,
    LeftCenter = 5, RightCenter = 6,
    BottomLeft = 2, BottomCenter = 7, BottomRight = 3,
}

public static class TagPlacement
{
    public static (double X, double Y) Origin(
        TagPosition position, double width, double height, double tagWidth, double tagHeight,
        double inset, double horizontalOffset, double verticalOffset)
    {
        var horizontal = position switch
        {
            TagPosition.TopLeft or TagPosition.LeftCenter or TagPosition.BottomLeft => -1,
            TagPosition.TopCenter or TagPosition.BottomCenter => 0,
            _ => 1,
        };
        var vertical = position switch
        {
            TagPosition.TopLeft or TagPosition.TopCenter or TagPosition.TopRight => -1,
            TagPosition.LeftCenter or TagPosition.RightCenter => 0,
            _ => 1,
        };
        return (AxisOrigin(horizontal, width, tagWidth, inset, horizontalOffset),
            AxisOrigin(vertical, height, tagHeight, inset, verticalOffset));
    }

    private static double Finite(double value) => double.IsFinite(value) ? value : 0;

    private static double AxisOrigin(int anchor, double extent, double item, double inset, double offset)
    {
        var available = Math.Max(0, Finite(extent) - Math.Max(0, Finite(item)));
        inset = Math.Clamp(Finite(inset), 0, available / 2);
        offset = Finite(offset);
        var proposed = anchor switch
        {
            -1 => inset + Math.Max(0, offset),
            0 => available / 2 + offset,
            _ => available - inset - Math.Max(0, offset),
        };
        return Math.Clamp(proposed, inset, available - inset);
    }
}
