using System.Runtime.InteropServices;

namespace Nameplate.App;

internal static partial class NativeMethods
{
    public const int WmWtsSessionChange = 0x02B1;
    public const int WtsRemoteConnect = 0x3;
    public const int WtsSessionUnlock = 0x8;

    private const int GwlExStyle = -20;
    private const int WsExLayered = 0x00080000;
    private const int WsExTransparent = 0x00000020;
    private const int WsExNoActivate = 0x08000000;
    private const int WsExToolWindow = 0x00000080;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;

    public static void ConfigureOverlay(nint handle, bool clickThrough)
    {
        var style = GetWindowLong(handle, GwlExStyle) | WsExLayered | WsExToolWindow;
        if (clickThrough)
        {
            style |= WsExTransparent | WsExNoActivate;
        }

        _ = SetWindowLong(handle, GwlExStyle, style);
    }

    public static void PositionWindow(nint handle, System.Drawing.Rectangle bounds)
    {
        _ = SetWindowPos(handle, new nint(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, SwpNoActivate | SwpShowWindow);
    }

    /// <summary>DPI scale (1.0 = 96dpi) for the monitor hosting the window.
    /// Correct as soon as the HWND exists, unlike VisualTreeHelper.GetDpi which
    /// WPF only populates after the window is shown.</summary>
    public static double DpiScale(nint handle)
    {
        var dpi = GetDpiForWindow(handle);
        return dpi == 0 ? 1.0 : dpi / 96.0;
    }

    [LibraryImport("user32.dll")]
    private static partial uint GetDpiForWindow(nint hwnd);

    [LibraryImport("user32.dll", EntryPoint = "GetWindowLongW", SetLastError = true)]
    private static partial int GetWindowLong(nint window, int index);

    [LibraryImport("user32.dll", EntryPoint = "SetWindowLongW", SetLastError = true)]
    private static partial int SetWindowLong(nint window, int index, int newValue);

    [LibraryImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetWindowPos(
        nint window,
        nint insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);

    [LibraryImport("wtsapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool WTSRegisterSessionNotification(nint window, uint flags);

    [LibraryImport("wtsapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool WTSUnRegisterSessionNotification(nint window);

    [LibraryImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static partial bool DestroyIcon(nint icon);
}
