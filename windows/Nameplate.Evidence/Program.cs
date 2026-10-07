using System.IO;
using System.Drawing.Imaging;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Nameplate.Core;
using Forms = System.Windows.Forms;
using Application = System.Windows.Application;
using Color = System.Windows.Media.Color;

namespace Nameplate.App;

internal static class EvidenceProgram
{
    [STAThread]
    private static void Main(string[] args)
    {
        var output = Path.GetFullPath(args.Single());
        Directory.CreateDirectory(output);
        Forms.Application.SetHighDpiMode(Forms.HighDpiMode.PerMonitorV2);
        _ = new Application { ShutdownMode = ShutdownMode.OnExplicitShutdown };
        var screen = Forms.Screen.PrimaryScreen ?? throw new InvalidOperationException("No live Windows desktop available.");
        var accent = new SolidColorBrush(Color.FromRgb(29, 158, 117));
        var label = new TextBlock
        {
            Text = "Nameplate runtime evidence\nWindows CI virtual desktop",
            Foreground = Brushes.White, FontSize = 24, TextAlignment = TextAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
        };
        var backdrop = new Window
        {
            WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize,
            ShowInTaskbar = false, Background = new SolidColorBrush(Color.FromRgb(15, 20, 26)),
            Content = label,
        };
        backdrop.Show();
        var backdropHandle = new WindowInteropHelper(backdrop).Handle;
        var scale = NativeMethods.DpiScale(backdropHandle);
        backdrop.Width = screen.Bounds.Width / scale;
        backdrop.Height = screen.Bounds.Height / scale;
        NativeMethods.PositionWindow(backdropHandle, screen.Bounds);
        Pump();
        var rows = new List<object>();
        var cases = Enum.GetValues<TagPosition>().Select(p => (Position: p, X: 0d, Y: 0d)).ToList();
        cases.Add((TagPosition.RightCenter, 0, -100));
        cases.Add((TagPosition.RightCenter, 0, 100));
        cases.Add((TagPosition.TopCenter, -100, 0));
        cases.Add((TagPosition.BottomRight, 100000, 100000));
        foreach (var item in cases)
        {
            label.Text = $"Nameplate runtime evidence\nWindows CI virtual desktop\n{item.Position} · offsets {item.X}, {item.Y}\nNative display scale {scale:0.##}×";
            var settings = new LayerSettings { TagCorner = item.Position, TagHorizontalOffset = item.X, TagVerticalOffset = item.Y };
            var tag = new TagWindow(screen, accent, new MachineIdentity("Evidence machine", "#1D9E75", "★"), settings);
            tag.Show();
            tag.UpdateLayout();
            Pump();
            var handle = new WindowInteropHelper(tag).Handle;
            if (handle == 0) throw new InvalidOperationException("No native overlay HWND.");
            var canvas = (Canvas)tag.Content;
            var pill = (Border)canvas.Children[0];
            var rect = pill.TransformToAncestor(canvas).TransformBounds(new Rect(pill.RenderSize));
            var expected = TagPlacement.Origin(item.Position, canvas.ActualWidth, canvas.ActualHeight,
                rect.Width, rect.Height, 20, item.X, item.Y);
            if (Math.Abs(rect.X - expected.X) > 1 || Math.Abs(rect.Y - expected.Y) > 1)
                throw new InvalidOperationException($"Incorrect live tag placement: {item.Position} {rect}");
            using var screenshot = new System.Drawing.Bitmap(screen.Bounds.Width, screen.Bounds.Height);
            using (var graphics = System.Drawing.Graphics.FromImage(screenshot))
                graphics.CopyFromScreen(screen.Bounds.Location, System.Drawing.Point.Empty, screen.Bounds.Size);
            var greenPixels = 0;
            var minX = screenshot.Width; var minY = screenshot.Height; var maxX = -1; var maxY = -1;
            for (var y = 0; y < screenshot.Height; y++)
            for (var x = 0; x < screenshot.Width; x++)
            {
                var pixel = screenshot.GetPixel(x, y);
                if (Math.Abs(pixel.R - 29) > 8 || Math.Abs(pixel.G - 158) > 8 || Math.Abs(pixel.B - 117) > 8) continue;
                greenPixels++;
                minX = Math.Min(minX, x); minY = Math.Min(minY, y);
                maxX = Math.Max(maxX, x); maxY = Math.Max(maxY, y);
            }
            if (greenPixels < 100 || Math.Abs(minX - rect.X * scale) > 4 || Math.Abs(minY - rect.Y * scale) > 4)
                throw new InvalidOperationException($"Screen capture did not prove the live overlay: {item.Position} ({greenPixels} pixels at {minX},{minY}).");
            var name = $"{item.Position}-{item.X}-{item.Y}.png";
            screenshot.Save(Path.Combine(output, name), ImageFormat.Png);
            rows.Add(new { position = item.Position.ToString(), item.X, item.Y, displayScale = scale,
                displayWidth = screen.Bounds.Width, displayHeight = screen.Bounds.Height,
                actualPillDips = new { rect.X, rect.Y, rect.Width, rect.Height }, greenPixels,
                capturedPixelBounds = new { minX, minY, maxX, maxY }, screenshot = name, nativeHandlePresent = true });
            tag.Close();
            Pump();
        }
        File.WriteAllText(Path.Combine(output, "runtime.json"), JsonSerializer.Serialize(new
        {
            revision = Environment.GetEnvironmentVariable("NAMEPLATE_EVIDENCE_SHA"),
            environment = "Live WPF windows on a GitHub-hosted Windows VM; one virtual monitor, actual OS DPI",
            os = Environment.OSVersion.ToString(), cases = rows,
        }, new JsonSerializerOptions { WriteIndented = true }));
        backdrop.Close();
        Console.WriteLine($"Captured and verified {rows.Count} production TagWindow cases at native scale {scale}×.");
    }

    private static void Pump()
    {
        var frame = new DispatcherFrame();
        var timer = new DispatcherTimer(DispatcherPriority.Background) { Interval = TimeSpan.FromMilliseconds(300) };
        timer.Tick += (_, _) => { timer.Stop(); frame.Continue = false; };
        timer.Start();
        Dispatcher.PushFrame(frame);
    }
}
