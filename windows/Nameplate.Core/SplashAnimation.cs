namespace Nameplate.Core;

public static class SplashAnimation
{
    public static TimeSpan ExitDuration(bool reduceMotion) =>
        TimeSpan.FromSeconds(reduceMotion ? 0.2 : 0.38);

    public static TimeSpan ExitDelay(TimeSpan holdDuration, bool reduceMotion)
    {
        var seconds = reduceMotion
            ? Math.Max(0, holdDuration.TotalSeconds - 0.2)
            : Math.Max(0.75, holdDuration.TotalSeconds - 0.42);
        return TimeSpan.FromSeconds(seconds);
    }
}
