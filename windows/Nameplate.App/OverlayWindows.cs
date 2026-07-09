using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Forms = System.Windows.Forms;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using FontFamily = System.Windows.Media.FontFamily;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using VerticalAlignment = System.Windows.VerticalAlignment;

namespace Nameplate.App;

internal abstract class OverlayWindow : Window
{
    protected OverlayWindow(Forms.Screen screen, bool clickThrough)
    {
        Screen = screen;
        ClickThrough = clickThrough;
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = !clickThrough;
        Topmost = true;
        Left = screen.Bounds.Left;
        Top = screen.Bounds.Top;
        Width = screen.Bounds.Width;
        Height = screen.Bounds.Height;
        SourceInitialized += OnSourceInitialized;
    }

    protected Forms.Screen Screen { get; }

    private bool ClickThrough { get; }

    private void OnSourceInitialized(object? sender, EventArgs args)
    {
        var handle = new WindowInteropHelper(this).Handle;
        NativeMethods.ConfigureOverlay(handle, ClickThrough);
        // Screen.Bounds are physical pixels; WPF's Left/Top/Width/Height are
        // DIPs. On a scaled display (e.g. 150%) the overlay is then dpi-scale×
        // too large, pushing the right/bottom border and its rounded corners
        // off-screen. GetDpiForWindow (not VisualTreeHelper.GetDpi, which WPF
        // only fills in after the window is shown) gives the correct scale now.
        var scale = NativeMethods.DpiScale(handle);
        Left = Screen.Bounds.Left / scale;
        Top = Screen.Bounds.Top / scale;
        Width = Screen.Bounds.Width / scale;
        Height = Screen.Bounds.Height / scale;
        NativeMethods.PositionWindow(handle, Screen.Bounds);
    }
}

internal sealed class FrameWindow : OverlayWindow
{
    public FrameWindow(Forms.Screen screen, Brush accent, Nameplate.Core.LayerSettings settings)
        : base(screen, true)
    {
        var radius = Math.Max(0, settings.FrameCornerRadius);
        Content = new Border
        {
            BorderBrush = accent,
            BorderThickness = new Thickness(Math.Clamp(settings.FrameThickness, 1, 40)),
            CornerRadius = new CornerRadius(
                settings.RoundTopLeft ? radius : 0,
                settings.RoundTopRight ? radius : 0,
                settings.RoundBottomRight ? radius : 0,
                settings.RoundBottomLeft ? radius : 0),
            Opacity = Math.Clamp(settings.FrameOpacity, 0, 1),
        };
    }
}

internal sealed class TagWindow : OverlayWindow
{
    public TagWindow(Forms.Screen screen, Brush accent, Nameplate.Core.MachineIdentity identity, Nameplate.Core.ScreenCorner corner)
        : base(screen, true)
    {
        var textColor = Nameplate.Core.ColorHex.PrefersDarkText(identity.ColorHex) ? Brushes.Black : Brushes.White;
        var panel = new StackPanel { Orientation = Orientation.Horizontal };
        if (!string.IsNullOrWhiteSpace(identity.Glyph))
        {
            panel.Children.Add(new TextBlock
            {
                Text = identity.Glyph,
                FontFamily = new FontFamily("Segoe UI Emoji"),
                FontSize = 18,
                Margin = new Thickness(0, 0, 7, 0),
                Foreground = textColor,
                VerticalAlignment = VerticalAlignment.Center,
            });
        }

        panel.Children.Add(new TextBlock
        {
            Text = identity.Name,
            FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI"),
            FontWeight = FontWeights.SemiBold,
            FontSize = 17,
            Foreground = textColor,
            VerticalAlignment = VerticalAlignment.Center,
        });

        var pill = new Border
        {
            Background = accent,
            CornerRadius = new CornerRadius(13),
            Padding = new Thickness(14, 8, 14, 8),
            Margin = new Thickness(20),
            Child = panel,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Top,
        };
        Anchor(pill, corner);
        Content = pill;
    }

    private static void Anchor(FrameworkElement element, Nameplate.Core.ScreenCorner corner)
    {
        element.HorizontalAlignment = corner is Nameplate.Core.ScreenCorner.TopRight or Nameplate.Core.ScreenCorner.BottomRight
            ? HorizontalAlignment.Right
            : HorizontalAlignment.Left;
        element.VerticalAlignment = corner is Nameplate.Core.ScreenCorner.BottomLeft or Nameplate.Core.ScreenCorner.BottomRight
            ? VerticalAlignment.Bottom
            : VerticalAlignment.Top;
    }
}

internal sealed class WatermarkWindow : OverlayWindow
{
    public WatermarkWindow(
        Forms.Screen screen,
        Brush accent,
        Nameplate.Core.MachineIdentity identity,
        Nameplate.Core.ScreenCorner corner,
        double opacity)
        : base(screen, true)
    {
        var text = new TextBlock
        {
            Text = identity.Name,
            FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI"),
            FontWeight = FontWeights.Bold,
            FontSize = 92,
            Foreground = accent,
            Opacity = Math.Clamp(opacity, 0, 1),
            Margin = new Thickness(34),
            HorizontalAlignment = corner is Nameplate.Core.ScreenCorner.TopRight or Nameplate.Core.ScreenCorner.BottomRight
                ? HorizontalAlignment.Right
                : HorizontalAlignment.Left,
            VerticalAlignment = corner is Nameplate.Core.ScreenCorner.BottomLeft or Nameplate.Core.ScreenCorner.BottomRight
                ? VerticalAlignment.Bottom
                : VerticalAlignment.Top,
        };
        Content = text;
    }
}

internal sealed class SplashWindow : OverlayWindow
{
    private readonly CancellationTokenSource lifetime = new();

    public SplashWindow(Forms.Screen screen, Brush accent, Nameplate.Core.MachineIdentity identity)
        : base(screen, true)
    {
        var foreground = Nameplate.Core.ColorHex.PrefersDarkText(identity.ColorHex) ? Brushes.Black : Brushes.White;
        Content = CreateCard(identity, accent, foreground, 32, 22);
        Opacity = 0;
        Closed += OnClosed;
    }

    public async Task ShowForAsync(TimeSpan duration)
    {
        Show();
        BeginAnimation(OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(220)));
        try
        {
            await Task.Delay(duration, lifetime.Token);
            BeginAnimation(OpacityProperty, new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(350)));
            await Task.Delay(350, lifetime.Token);
            Close();
        }
        catch (OperationCanceledException)
        {
        }
    }

    internal static Border CreateCard(Nameplate.Core.MachineIdentity identity, Brush accent, Brush foreground, double fontSize, double padding)
    {
        var text = string.IsNullOrWhiteSpace(identity.Glyph) ? identity.Name : $"{identity.Glyph}  {identity.Name}";
        return new Border
        {
            Background = accent,
            CornerRadius = new CornerRadius(22),
            Padding = new Thickness(padding, padding * 0.65, padding, padding * 0.65),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 28, Opacity = 0.35, ShadowDepth = 8 },
            Child = new TextBlock
            {
                Text = text,
                FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI"),
                FontSize = fontSize,
                FontWeight = FontWeights.Bold,
                Foreground = foreground,
                TextAlignment = TextAlignment.Center,
            },
        };
    }

    private void OnClosed(object? sender, EventArgs args)
    {
        lifetime.Cancel();
        lifetime.Dispose();
    }
}

internal sealed class AttentionWindow : OverlayWindow
{
    private readonly CancellationTokenSource lifetime = new();

    public AttentionWindow(
        Forms.Screen screen,
        Brush accent,
        Nameplate.Core.MachineIdentity identity,
        Nameplate.Core.AttentionRequest request)
        : base(screen, false)
    {
        var grid = new Grid { Background = Brushes.Transparent };
        var frame = new Border
        {
            BorderBrush = accent,
            BorderThickness = new Thickness(12),
            CornerRadius = new CornerRadius(18),
            Opacity = 0.45,
        };
        frame.BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(0.25, 1, TimeSpan.FromMilliseconds(700))
            {
                AutoReverse = true,
                RepeatBehavior = RepeatBehavior.Forever,
            });
        grid.Children.Add(frame);

        var card = CreateAttentionCard(accent, identity.ColorHex, request);
        grid.Children.Add(card);
        Content = grid;
        MouseLeftButtonDown += OnMouseLeftButtonDown;
        Closed += OnClosed;
    }

    public event EventHandler? DismissRequested;

    public async Task ShowForAsync(TimeSpan? duration)
    {
        Show();
        if (duration is not TimeSpan timeout) return;
        try
        {
            await Task.Delay(timeout, lifetime.Token);
            DismissRequested?.Invoke(this, EventArgs.Empty);
        }
        catch (OperationCanceledException)
        {
        }
    }

    private static Border CreateAttentionCard(Brush accent, string colorHex, Nameplate.Core.AttentionRequest request)
    {
        var foreground = Nameplate.Core.ColorHex.PrefersDarkText(colorHex) ? Brushes.Black : Brushes.White;
        var stack = new StackPanel { MaxWidth = 650 };
        stack.Children.Add(new TextBlock
        {
            Text = request.Title ?? "Attention needed",
            FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI"),
            FontSize = 18,
            FontWeight = FontWeights.Bold,
            Foreground = foreground,
            TextWrapping = TextWrapping.Wrap,
        });
        stack.Children.Add(new TextBlock
        {
            Text = request.Message,
            FontFamily = new FontFamily("Segoe UI Variable Text, Segoe UI"),
            FontSize = 26,
            FontWeight = FontWeights.SemiBold,
            Foreground = foreground,
            TextWrapping = TextWrapping.Wrap,
            Margin = new Thickness(0, 10, 0, 10),
        });
        stack.Children.Add(new TextBlock
        {
            Text = "Click anywhere to dismiss",
            FontSize = 13,
            Foreground = foreground,
            Opacity = 0.7,
        });
        return new Border
        {
            Background = accent,
            CornerRadius = new CornerRadius(22),
            Padding = new Thickness(28, 22, 28, 22),
            Margin = new Thickness(48),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Effect = new System.Windows.Media.Effects.DropShadowEffect { BlurRadius = 34, Opacity = 0.42, ShadowDepth = 9 },
            Child = stack,
        };
    }

    private void OnMouseLeftButtonDown(object sender, MouseButtonEventArgs args) => DismissRequested?.Invoke(this, EventArgs.Empty);

    private void OnClosed(object? sender, EventArgs args)
    {
        lifetime.Cancel();
        lifetime.Dispose();
    }
}
