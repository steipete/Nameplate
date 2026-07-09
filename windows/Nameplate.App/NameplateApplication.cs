using System.Text.Json;
using System.Windows;
using Application = System.Windows.Application;
using Microsoft.Win32;
using Nameplate.Core;

namespace Nameplate.App;

internal sealed class NameplateApplication : Application
{
    private ConfigStore? config;
    private OverlayManager? overlays;
    private TrayController? tray;
    private PipeServer? pipeServer;
    private SessionNotificationWindow? sessionWindow;

    public NameplateApplication()
    {
        ShutdownMode = ShutdownMode.OnExplicitShutdown;
    }

    protected override void OnStartup(StartupEventArgs args)
    {
        base.OnStartup(args);
        config = new ConfigStore();
        overlays = new OverlayManager(config);
        tray = new TrayController(config, overlays.ShowSplash, Shutdown);
        pipeServer = new PipeServer(json => Dispatcher.InvokeAsync(() => HandlePipeCommand(json)));
        sessionWindow = new SessionNotificationWindow(HandleSessionNotification);
        config.Changed += OnConfigChanged;
        SystemEvents.DisplaySettingsChanged += OnDisplaySettingsChanged;
    }

    protected override void OnExit(ExitEventArgs args)
    {
        SystemEvents.DisplaySettingsChanged -= OnDisplaySettingsChanged;
        if (config is not null)
        {
            config.Changed -= OnConfigChanged;
        }

        sessionWindow?.Dispose();
        pipeServer?.Dispose();
        tray?.Dispose();
        overlays?.Dispose();
        config?.Dispose();
        base.OnExit(args);
    }

    private void HandlePipeCommand(string json)
    {
        switch (PipeServer.GetCommand(json)?.ToLowerInvariant())
        {
            case "activate":
            case "splash":
                overlays?.ShowSplash();
                break;
            case "attention":
                var request = AttentionRequest.FromJson(json);
                if (request is not null && !string.IsNullOrWhiteSpace(request.Message))
                {
                    overlays?.ShowAttention(request);
                }

                break;
        }
    }

    private void HandleSessionNotification(int notification)
    {
        if (config is null || overlays is null)
        {
            return;
        }

        var shouldShow = notification switch
        {
            NativeMethods.WtsRemoteConnect => config.Settings.Splash.OnRemoteConnect,
            NativeMethods.WtsSessionUnlock => config.Settings.Splash.OnSessionUnlock,
            _ => false,
        };
        if (shouldShow)
        {
            overlays.ShowSplash();
        }
    }

    private void OnConfigChanged(object? sender, EventArgs args)
    {
        _ = Dispatcher.InvokeAsync(() =>
        {
            overlays?.Rebuild();
            tray?.RefreshIdentity();
        });
    }

    private void OnDisplaySettingsChanged(object? sender, EventArgs args)
    {
        _ = Dispatcher.InvokeAsync(() => overlays?.Rebuild());
    }
}
