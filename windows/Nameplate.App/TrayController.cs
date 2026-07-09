using System.IO;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Net;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using Nameplate.Core;
using Forms = System.Windows.Forms;

namespace Nameplate.App;

internal sealed class TrayController : IDisposable
{
    private readonly ConfigStore config;
    private readonly Action showSplash;
    private readonly Action quit;
    private readonly Forms.NotifyIcon notifyIcon;
    private readonly Forms.ToolStripMenuItem hostLine = new();
    private readonly Forms.ToolStripMenuItem ipLine = new();
    private readonly Forms.ToolStripMenuItem uptimeLine = new();
    private Forms.ToolStripMenuItem? frameItem;
    private Forms.ToolStripMenuItem? tagItem;
    private Forms.ToolStripMenuItem? watermarkItem;
    private bool refreshingChecks;
    private Icon? icon;

    public TrayController(ConfigStore config, Action showSplash, Action quit)
    {
        this.config = config;
        this.showSplash = showSplash;
        this.quit = quit;
        notifyIcon = new Forms.NotifyIcon
        {
            Text = $"Nameplate — {config.Identity.Name}",
            Visible = true,
        };
        notifyIcon.DoubleClick += OnDoubleClick;
        BuildMenu();
        RefreshIdentity();
    }

    public void RefreshIdentity()
    {
        icon?.Dispose();
        icon = CreatePlateIcon(config.Identity.ColorHex);
        notifyIcon.Icon = icon;
        notifyIcon.Text = Truncate($"Nameplate — {config.Identity.Name}", 63);
        refreshingChecks = true;
        frameItem!.Checked = config.Settings.Layers.FrameEnabled;
        tagItem!.Checked = config.Settings.Layers.TagEnabled;
        watermarkItem!.Checked = config.Settings.Layers.WatermarkEnabled;
        refreshingChecks = false;
    }

    public void Dispose()
    {
        notifyIcon.Visible = false;
        notifyIcon.Dispose();
        icon?.Dispose();
    }

    private void BuildMenu()
    {
        var menu = new Forms.ContextMenuStrip();
        menu.Opening += OnMenuOpening;

        frameItem = ToggleItem("Frame", config.Settings.Layers.FrameEnabled, value =>
            UpdateLayers(config.Settings.Layers with { FrameEnabled = value }));
        tagItem = ToggleItem("Name tag", config.Settings.Layers.TagEnabled, value =>
            UpdateLayers(config.Settings.Layers with { TagEnabled = value }));
        watermarkItem = ToggleItem("Watermark", config.Settings.Layers.WatermarkEnabled, value =>
            UpdateLayers(config.Settings.Layers with { WatermarkEnabled = value }));
        menu.Items.AddRange([frameItem!, tagItem!, watermarkItem!]);
        menu.Items.Add(new Forms.ToolStripSeparator());

        var splash = new Forms.ToolStripMenuItem("Show splash");
        splash.Click += OnShowSplash;
        menu.Items.Add(splash);

        var openConfig = new Forms.ToolStripMenuItem("Open config folder");
        openConfig.Click += OnOpenConfig;
        menu.Items.Add(openConfig);
        menu.Items.Add(new Forms.ToolStripSeparator());

        foreach (var item in new[] { hostLine, ipLine, uptimeLine })
        {
            item.Enabled = false;
            menu.Items.Add(item);
        }

        menu.Items.Add(new Forms.ToolStripSeparator());
        var quitItem = new Forms.ToolStripMenuItem("Quit Nameplate");
        quitItem.Click += OnQuit;
        menu.Items.Add(quitItem);
        notifyIcon.ContextMenuStrip = menu;
    }

    private Forms.ToolStripMenuItem ToggleItem(string label, bool initial, Action<bool> changed)
    {
        var item = new Forms.ToolStripMenuItem(label) { Checked = initial, CheckOnClick = true };
        item.CheckedChanged += (_, _) =>
        {
            if (!refreshingChecks)
            {
                changed(item.Checked);
            }
        };
        return item;
    }

    private void UpdateLayers(LayerSettings layers)
    {
        config.Save(config.Settings with { Layers = layers });
    }

    private void OnDoubleClick(object? sender, EventArgs args) => showSplash();

    private void OnShowSplash(object? sender, EventArgs args) => showSplash();

    private void OnOpenConfig(object? sender, EventArgs args)
    {
        Directory.CreateDirectory(config.ConfigFolder);
        Process.Start(new ProcessStartInfo("explorer.exe", config.ConfigFolder) { UseShellExecute = true });
    }

    private void OnQuit(object? sender, EventArgs args) => quit();

    private void OnMenuOpening(object? sender, System.ComponentModel.CancelEventArgs args)
    {
        hostLine.Text = $"Hostname: {Hostnames.Short(Environment.MachineName)}";
        ipLine.Text = $"IP: {PrimaryIpAddress()}";
        uptimeLine.Text = $"Uptime: {FormatUptime(TimeSpan.FromMilliseconds(Environment.TickCount64))}";
    }

    private static string PrimaryIpAddress()
    {
        return NetworkInterface.GetAllNetworkInterfaces()
            .Where(network => network.OperationalStatus == OperationalStatus.Up && network.NetworkInterfaceType != NetworkInterfaceType.Loopback)
            .SelectMany(network => network.GetIPProperties().UnicastAddresses)
            .Select(address => address.Address)
            .FirstOrDefault(address => address.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(address))
            ?.ToString() ?? "Unavailable";
    }

    private static string FormatUptime(TimeSpan uptime) =>
        uptime.TotalDays >= 1 ? $"{(int)uptime.TotalDays}d {uptime.Hours}h {uptime.Minutes}m" : $"{uptime.Hours}h {uptime.Minutes}m";

    private static Icon CreatePlateIcon(string colorHex)
    {
        var normalized = ColorHex.Normalize(colorHex) ?? NameplatePalette.Fallback.Hex;
        using var bitmap = new Bitmap(32, 32, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var graphics = Graphics.FromImage(bitmap);
        graphics.SmoothingMode = SmoothingMode.AntiAlias;
        graphics.Clear(Color.Transparent);
        using var plate = new GraphicsPath();
        plate.AddArc(2, 7, 8, 8, 180, 90);
        plate.AddArc(22, 7, 8, 8, 270, 90);
        plate.AddArc(22, 21, 8, 8, 0, 90);
        plate.AddArc(2, 21, 8, 8, 90, 90);
        plate.CloseFigure();
        using var fill = new SolidBrush(ColorTranslator.FromHtml(normalized));
        graphics.FillPath(fill, plate);
        using var dot = new SolidBrush(ColorHex.PrefersDarkText(normalized) ? Color.Black : Color.White);
        graphics.FillEllipse(dot, 13, 14, 6, 6);

        var handle = bitmap.GetHicon();
        try
        {
            using var temporary = Icon.FromHandle(handle);
            return (Icon)temporary.Clone();
        }
        finally
        {
            _ = NativeMethods.DestroyIcon(handle);
        }
    }

    private static string Truncate(string value, int maxLength) => value.Length <= maxLength ? value : value[..maxLength];
}
