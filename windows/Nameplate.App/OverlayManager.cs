using System.Globalization;
using System.ComponentModel;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Nameplate.Core;
using Forms = System.Windows.Forms;

namespace Nameplate.App;

internal sealed class OverlayManager : IDisposable
{
    private static readonly TimeSpan DecorationAnimationDuration = TimeSpan.FromMilliseconds(200);

    private readonly List<DecorationWindow> persistentWindows = [];
    private readonly HashSet<Window> retiringWindows = [];
    private readonly List<SplashWindow> splashWindows = [];
    private readonly List<AttentionWindow> attentionWindows = [];
    private readonly ConfigStore config;
    private MachineIdentity? renderedIdentity;
    private LayerSettings? renderedSettings;
    private string[] renderedScreens = [];
    private GlobalMouseMonitor? attentionClickMonitor;
    private int attentionGeneration;

    private enum DecorationLayer
    {
        Frame,
        Tag,
        Watermark,
    }

    private sealed record DecorationWindow(DecorationLayer Layer, string ScreenKey, OverlayWindow Window);

    public OverlayManager(ConfigStore config)
    {
        this.config = config;
        Rebuild(animate: false, force: true);
    }

    public void Dispose()
    {
        ClosePersistentImmediately();
        CloseWindows(splashWindows);
        CloseAttention();
    }

    public void Rebuild(bool animate = true, bool force = false)
    {
        var identity = config.Identity;
        var settings = config.Settings.Layers;
        var screens = Forms.Screen.AllScreens;
        var screenKeys = screens.Select(ScreenKey).ToArray();
        var appearanceChanged = renderedIdentity != identity
            || renderedSettings is null
            || AppearanceOnly(renderedSettings) != AppearanceOnly(settings);
        var screensChanged = !renderedScreens.SequenceEqual(screenKeys);
        var enabledLayersChanged = renderedSettings is null
            || renderedSettings.FrameEnabled != settings.FrameEnabled
            || renderedSettings.TagEnabled != settings.TagEnabled
            || renderedSettings.WatermarkEnabled != settings.WatermarkEnabled;
        if (!force && !appearanceChanged && !screensChanged && !enabledLayersChanged)
        {
            return;
        }

        CloseWindows(splashWindows);
        CloseAttention();
        if (force || appearanceChanged || screensChanged)
        {
            ReplaceDecorations(screens, identity, settings, animate);
        }
        else
        {
            ReconcileEnabledLayers(screens, identity, settings, animate);
        }

        renderedIdentity = identity;
        renderedSettings = settings;
        renderedScreens = screenKeys;
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
        CloseAttention();
        var generation = ++attentionGeneration;
        var normalized = ColorHex.Normalize(request.Color) ?? config.Identity.ColorHex;
        var accent = Brush(normalized);
        var identity = config.Identity with { ColorHex = normalized };
        // No duration = sticky until the next mouse click anywhere.
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
        try
        {
            attentionClickMonitor = new GlobalMouseMonitor(() =>
            {
                _ = Application.Current.Dispatcher.BeginInvoke(() => DismissAttention(generation));
            });
        }
        catch (Win32Exception error)
        {
            Console.Error.WriteLine($"Nameplate: global click monitoring unavailable: {error.Message}");
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

    private void OnAttentionDismissRequested(object? sender, EventArgs args)
    {
        if (sender is AttentionWindow window && attentionWindows.Contains(window))
        {
            CloseAttention();
        }
    }

    private void DismissAttention(int generation)
    {
        if (generation == attentionGeneration)
        {
            CloseAttention();
        }
    }

    private void CloseAttention()
    {
        attentionClickMonitor?.Dispose();
        attentionClickMonitor = null;
        CloseWindows(attentionWindows);
    }

    private void ReplaceDecorations(
        Forms.Screen[] screens,
        MachineIdentity identity,
        LayerSettings settings,
        bool animate)
    {
        var previous = persistentWindows.ToArray();
        persistentWindows.Clear();
        foreach (var screen in screens)
        {
            foreach (var layer in EnabledLayers(settings))
            {
                AddDecoration(layer, screen, identity, settings, animate);
            }
        }

        foreach (var decoration in previous)
        {
            HidePersistent(decoration.Window, animate);
        }
    }

    private void ReconcileEnabledLayers(
        Forms.Screen[] screens,
        MachineIdentity identity,
        LayerSettings settings,
        bool animate)
    {
        var enabled = EnabledLayers(settings).ToHashSet();
        foreach (var decoration in persistentWindows.Where(item => !enabled.Contains(item.Layer)).ToArray())
        {
            persistentWindows.Remove(decoration);
            HidePersistent(decoration.Window, animate);
        }

        foreach (var screen in screens)
        {
            var screenKey = ScreenKey(screen);
            foreach (var layer in enabled)
            {
                if (persistentWindows.Any(item => item.Layer == layer && item.ScreenKey == screenKey))
                {
                    continue;
                }
                AddDecoration(layer, screen, identity, settings, animate);
            }
        }
        RestackDecorations(screens, settings);
    }

    private void RestackDecorations(Forms.Screen[] screens, LayerSettings settings)
    {
        foreach (var screen in screens)
        {
            var screenKey = ScreenKey(screen);
            foreach (var layer in EnabledLayers(settings))
            {
                persistentWindows
                    .First(item => item.Layer == layer && item.ScreenKey == screenKey)
                    .Window
                    .BringToFront();
            }
        }
    }

    private void AddDecoration(
        DecorationLayer layer,
        Forms.Screen screen,
        MachineIdentity identity,
        LayerSettings settings,
        bool animate)
    {
        var accent = Brush(identity.ColorHex);
        OverlayWindow window = layer switch
        {
            DecorationLayer.Frame => new FrameWindow(screen, accent, settings),
            DecorationLayer.Tag => new TagWindow(screen, accent, identity, settings.TagCorner),
            DecorationLayer.Watermark => new WatermarkWindow(
                screen,
                accent,
                identity,
                settings.WatermarkCorner,
                settings.WatermarkOpacity),
            _ => throw new ArgumentOutOfRangeException(nameof(layer)),
        };
        persistentWindows.Add(new DecorationWindow(layer, ScreenKey(screen), window));
        ShowPersistent(window, animate);
    }

    private static IEnumerable<DecorationLayer> EnabledLayers(LayerSettings settings)
    {
        if (settings.FrameEnabled) yield return DecorationLayer.Frame;
        if (settings.TagEnabled) yield return DecorationLayer.Tag;
        if (settings.WatermarkEnabled) yield return DecorationLayer.Watermark;
    }

    private static LayerSettings AppearanceOnly(LayerSettings settings) => settings with
    {
        FrameEnabled = false,
        TagEnabled = false,
        WatermarkEnabled = false,
    };

    private static string ScreenKey(Forms.Screen screen) =>
        $"{screen.DeviceName}:{screen.Bounds.X}:{screen.Bounds.Y}:{screen.Bounds.Width}:{screen.Bounds.Height}";

    private static void ShowPersistent(Window window, bool animate)
    {
        var shouldAnimate = animate && SystemParameters.ClientAreaAnimation;
        window.Opacity = shouldAnimate ? 0 : 1;
        window.Show();
        if (!shouldAnimate)
        {
            return;
        }

        var animation = new DoubleAnimation(0, 1, DecorationAnimationDuration)
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut },
        };
        animation.Completed += (_, _) =>
        {
            if (!window.IsLoaded) return;
            window.BeginAnimation(Window.OpacityProperty, null);
            window.Opacity = 1;
        };
        window.BeginAnimation(Window.OpacityProperty, animation);
    }

    private void HidePersistent(Window window, bool animate)
    {
        if (!animate || !SystemParameters.ClientAreaAnimation || !window.IsLoaded)
        {
            window.Close();
            return;
        }

        var currentOpacity = window.Opacity;
        window.BeginAnimation(Window.OpacityProperty, null);
        window.Opacity = currentOpacity;
        retiringWindows.Add(window);
        var animation = new DoubleAnimation(currentOpacity, 0, DecorationAnimationDuration)
        {
            EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut },
        };
        animation.Completed += (_, _) =>
        {
            retiringWindows.Remove(window);
            if (window.IsLoaded)
            {
                window.Close();
            }
        };
        window.BeginAnimation(Window.OpacityProperty, animation);
    }

    private void ClosePersistentImmediately()
    {
        foreach (var decoration in persistentWindows.ToArray())
        {
            decoration.Window.Close();
        }
        persistentWindows.Clear();
        foreach (var window in retiringWindows.ToArray())
        {
            window.Close();
        }
        retiringWindows.Clear();
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
