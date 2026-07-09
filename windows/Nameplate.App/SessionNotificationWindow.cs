using System.Windows.Interop;

namespace Nameplate.App;

internal sealed class SessionNotificationWindow : IDisposable
{
    private const uint NotifyForThisSession = 0;
    private static readonly nint MessageOnlyParent = new(-3);
    private readonly HwndSource source;

    public SessionNotificationWindow(Action<int> notification)
    {
        Notification = notification;
        source = new HwndSource(new HwndSourceParameters("Nameplate.SessionEvents")
        {
            ParentWindow = MessageOnlyParent,
            Width = 0,
            Height = 0,
            WindowStyle = 0,
        });
        source.AddHook(WindowProcedure);
        _ = NativeMethods.WTSRegisterSessionNotification(source.Handle, NotifyForThisSession);
    }

    private Action<int> Notification { get; }

    public void Dispose()
    {
        _ = NativeMethods.WTSUnRegisterSessionNotification(source.Handle);
        source.RemoveHook(WindowProcedure);
        source.Dispose();
    }

    private nint WindowProcedure(nint window, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == NativeMethods.WmWtsSessionChange)
        {
            Notification(wParam.ToInt32());
        }

        return 0;
    }
}
