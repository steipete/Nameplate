using System.Globalization;
using System.Windows;
using System.Windows.Media;
using Nameplate.Core;
using Forms = System.Windows.Forms;

namespace Nameplate.App;

internal sealed class OverlayManager : IDisposable
{
    private readonly List<Window> persistentWindows = [];
    private readonly List<SplashWindow> splashWindows = [];
    private readonly List<AttentionWindow> attentionWindows = [];
    private readonly ConfigStore config;

    public OverlayManager(ConfigStore config)
    {
        this.config = config;
        Rebuild();
    }

    public void Dispose()
    {
        CloseWindows(persistentWindows);
        CloseWindows(splashWindows);
        CloseWindows(attentionWindows);
    }

    public void Rebuild()
    {
        CloseWindows(persistentWindows);
        CloseWindows(splashWindows);
        CloseWindows(attentionWindows);
        var identity = config.Identity;
        var settings = config.Settings.Layers;
        var accent = Brush(identity.ColorHex);

        foreach (var screen in Forms.Screen.AllScreens)
        {
            if (settings.FrameEnabled)
            {
                ShowPersistent(new FrameWindow(screen, accent, settings));
            }

            if (settings.TagEnabled)
            {
                ShowPersistent(new TagWindow(screen, accent, identity, settings.TagCorner));
            }

            if (settings.WatermarkEnabled)
            {
                ShowPersistent(new WatermarkWindow(screen, accent, identity, settings.WatermarkCorner, settings.WatermarkOpacity));
            }
        }
    }

    public void ShowSplash()
    {
        CloseWindows(splashWindows);
        var duration = TimeSpan.FromSeconds(Math.Clamp(config.Settings.Splash.Duration, 0.5, 30));
        var accent = Brush(config.Identity.ColorHex);
        foreach (var screen in Forms.Screen.AllScreens)
        {
            var window = new SplashWindow(screen, accent, config.Identity);
            window.Closed += (_, _) => splashWindows.Remove(window);
            splashWindows.Add(window);
            _ = window.ShowForAsync(duration);
        }
    }

    public void ShowAttention(AttentionRequest request)
    {
        CloseWindows(attentionWindows);
        var normalized = ColorHex.Normalize(request.Color) ?? config.Identity.ColorHex;
        var accent = Brush(normalized);
        var identity = config.Identity with { ColorHex = normalized };
        // No duration = sticky until the card is clicked.
        TimeSpan? duration = request.Duration is double seconds
            ? TimeSpan.FromSeconds(Math.Clamp(seconds, 1, 3600))
            : null;
        foreach (var screen in Forms.Screen.AllScreens)
        {
            var window = new AttentionWindow(screen, accent, identity, request);
            window.DismissRequested += OnAttentionDismissRequested;
            attentionWindows.Add(window);
            _ = window.ShowForAsync(duration);
        }
    }

    private static SolidColorBrush Brush(string hex)
    {
        var normalized = ColorHex.Normalize(hex) ?? NameplatePalette.Fallback.Hex;
        var color = Color.FromRgb(
            byte.Parse(normalized.AsSpan(1, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
            byte.Parse(normalized.AsSpan(3, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture),
            byte.Parse(normalized.AsSpan(5, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture));
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }

    private void OnAttentionDismissRequested(object? sender, EventArgs args) => CloseWindows(attentionWindows);

    private void ShowPersistent(Window window)
    {
        persistentWindows.Add(window);
        window.Show();
    }

    private static void CloseWindows<T>(List<T> windows) where T : Window
    {
        foreach (var window in windows.ToArray())
        {
            window.Close();
        }

        windows.Clear();
    }
}
