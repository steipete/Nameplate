using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using Nameplate.Core;
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

    internal void BringToFront()
    {
        NativeMethods.PositionWindow(new WindowInteropHelper(this).Handle, Screen.Bounds);
    }

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
    private readonly Rectangle frame;
    private readonly Rectangle glow;
    private readonly Border plate;
    private readonly ScaleTransform frameScale = new(1, 1);
    private readonly ScaleTransform glowScale = new(0.78, 0.78);
    private readonly ScaleTransform plateScale = new(0.88, 0.88);
    private readonly bool reduceMotion;

    public SplashWindow(Forms.Screen screen, Brush accent, Nameplate.Core.MachineIdentity identity)
        : base(screen, true)
    {
        var accentColor = accent is SolidColorBrush solid ? solid.Color : Colors.MediumSeaGreen;
        frame = new Rectangle
        {
            Margin = new Thickness(7),
            RadiusX = 22,
            RadiusY = 22,
            Stroke = accent,
            StrokeThickness = 7,
            RenderTransform = frameScale,
            RenderTransformOrigin = new Point(0.5, 0.5),
            Effect = new DropShadowEffect
            {
                Color = accentColor,
                BlurRadius = 18,
                Opacity = 0.9,
                ShadowDepth = 0,
            },
        };

        var glowBrush = accent.Clone();
        glowBrush.Opacity = 0.16;
        glow = new Rectangle
        {
            Margin = new Thickness(7),
            RadiusX = 22,
            RadiusY = 22,
            Stroke = glowBrush,
            StrokeThickness = 2,
            Opacity = 0,
            RenderTransform = glowScale,
            RenderTransformOrigin = new Point(0.5, 0.5),
        };
        plate = CreateIdentityPlate(identity, accent, accentColor);
        plate.Opacity = 0;
        plate.RenderTransform = plateScale;
        plate.RenderTransformOrigin = new Point(0.5, 0.5);

        var grid = new Grid();
        grid.Children.Add(frame);
        grid.Children.Add(glow);
        grid.Children.Add(plate);
        Content = grid;

        reduceMotion = !SystemParameters.ClientAreaAnimation;
        if (reduceMotion)
        {
            ApplyPresentedState();
        }
        Loaded += OnLoaded;
        Closed += OnClosed;
    }

    public async Task ShowForAsync(TimeSpan duration)
    {
        Show();
        _ = ExitContentAfterAsync(duration);
        try
        {
            await Task.Delay(duration, lifetime.Token);
            BeginAnimation(
                OpacityProperty,
                new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(500))
                {
                    EasingFunction = new CubicEase { EasingMode = EasingMode.EaseIn },
                });
            await Task.Delay(500, lifetime.Token);
            Close();
        }
        catch (OperationCanceledException)
        {
        }
    }

    private static Border CreateIdentityPlate(MachineIdentity identity, Brush accent, Color accentColor)
    {
        var stack = new StackPanel();
        if (!string.IsNullOrWhiteSpace(identity.Glyph))
        {
            stack.Children.Add(new TextBlock
            {
                Text = identity.Glyph,
                FontFamily = new FontFamily("Segoe UI Emoji"),
                FontSize = 76,
                Foreground = Brushes.White,
                TextAlignment = TextAlignment.Center,
                Margin = new Thickness(0, 0, 0, 18),
            });
        }
        stack.Children.Add(new TextBlock
        {
            Text = identity.Name,
            FontFamily = new FontFamily("Segoe UI Variable Display, Segoe UI"),
            FontSize = 64,
            FontWeight = FontWeights.Bold,
            Foreground = Brushes.White,
            TextAlignment = TextAlignment.Center,
            TextWrapping = TextWrapping.Wrap,
        });
        stack.Children.Add(new TextBlock
        {
            Text = Environment.MachineName,
            FontFamily = new FontFamily("Cascadia Mono, Consolas"),
            FontSize = 15,
            FontWeight = FontWeights.Medium,
            Foreground = new SolidColorBrush(Color.FromArgb(140, 255, 255, 255)),
            TextAlignment = TextAlignment.Center,
            Margin = new Thickness(0, 18, 0, 0),
        });
        return new Border
        {
            MaxWidth = 720,
            Background = new SolidColorBrush(Color.FromArgb(189, 0, 0, 0)),
            BorderBrush = accent,
            BorderThickness = new Thickness(4),
            CornerRadius = new CornerRadius(32),
            Padding = new Thickness(64, 44, 64, 44),
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Effect = new DropShadowEffect
            {
                Color = accentColor,
                BlurRadius = 36,
                Opacity = 0.3,
                ShadowDepth = 0,
            },
            Child = stack,
        };
    }

    private void OnLoaded(object sender, RoutedEventArgs args)
    {
        if (reduceMotion)
        {
            return;
        }

        var perimeter = RoundedRectanglePerimeter(
            Math.Max(1, frame.ActualWidth),
            Math.Max(1, frame.ActualHeight),
            22);
        var dashUnits = perimeter / frame.StrokeThickness;
        frame.StrokeDashArray = new DoubleCollection { dashUnits, dashUnits };
        frame.StrokeDashOffset = dashUnits;
        frame.BeginAnimation(
            Shape.StrokeDashOffsetProperty,
            new DoubleAnimation(dashUnits, 0, TimeSpan.FromSeconds(0.62))
            {
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseInOut },
            });
        glow.BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.55))
            {
                BeginTime = TimeSpan.FromSeconds(0.08),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            });
        AnimateScale(glowScale, 0.78, 1.03, TimeSpan.FromSeconds(0.55), TimeSpan.FromSeconds(0.08), new CubicEase { EasingMode = EasingMode.EaseOut });
        plate.BeginAnimation(
            OpacityProperty,
            new DoubleAnimation(0, 1, TimeSpan.FromSeconds(0.48))
            {
                BeginTime = TimeSpan.FromSeconds(0.2),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut },
            });
        AnimateScale(plateScale, 0.88, 1, TimeSpan.FromSeconds(0.48), TimeSpan.FromSeconds(0.2), new BackEase { Amplitude = 0.18, EasingMode = EasingMode.EaseOut });
    }

    private async Task ExitContentAfterAsync(TimeSpan holdDuration)
    {
        try
        {
            await Task.Delay(SplashAnimation.ExitDelay(holdDuration, reduceMotion), lifetime.Token);
            var duration = SplashAnimation.ExitDuration(reduceMotion);
            var ease = new CubicEase { EasingMode = EasingMode.EaseIn };
            frame.BeginAnimation(OpacityProperty, new DoubleAnimation(frame.Opacity, 0, duration) { EasingFunction = ease });
            glow.BeginAnimation(OpacityProperty, new DoubleAnimation(glow.Opacity, 0, duration) { EasingFunction = ease });
            plate.BeginAnimation(OpacityProperty, new DoubleAnimation(plate.Opacity, 0, duration) { EasingFunction = ease });
            if (!reduceMotion)
            {
                AnimateScale(frameScale, frameScale.ScaleX, 1.045, duration, TimeSpan.Zero, ease);
                AnimateScale(glowScale, glowScale.ScaleX, 1.08, duration, TimeSpan.Zero, ease);
                AnimateScale(plateScale, plateScale.ScaleX, 1.045, duration, TimeSpan.Zero, ease);
            }
        }
        catch (OperationCanceledException)
        {
        }
    }

    private void ApplyPresentedState()
    {
        frame.Opacity = 1;
        glow.Opacity = 1;
        plate.Opacity = 1;
        frameScale.ScaleX = frameScale.ScaleY = 1;
        glowScale.ScaleX = glowScale.ScaleY = 1;
        plateScale.ScaleX = plateScale.ScaleY = 1;
    }

    private static void AnimateScale(
        ScaleTransform transform,
        double from,
        double to,
        TimeSpan duration,
        TimeSpan beginTime,
        IEasingFunction easing)
    {
        var animation = new DoubleAnimation(from, to, duration)
        {
            BeginTime = beginTime,
            EasingFunction = easing,
        };
        transform.BeginAnimation(ScaleTransform.ScaleXProperty, animation);
        transform.BeginAnimation(ScaleTransform.ScaleYProperty, animation.Clone());
    }

    private static double RoundedRectanglePerimeter(double width, double height, double radius)
    {
        var boundedRadius = Math.Clamp(radius, 0, Math.Min(width, height) / 2);
        return 2 * (width + height - 4 * boundedRadius) + 2 * Math.PI * boundedRadius;
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
        : base(screen, true)
    {
        var grid = new Grid();
        var frame = new Rectangle
        {
            Stroke = accent,
            StrokeThickness = 12,
            RadiusX = 18,
            RadiusY = 18,
            Margin = new Thickness(6),
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

    private void OnClosed(object? sender, EventArgs args)
    {
        lifetime.Cancel();
        lifetime.Dispose();
    }
}
