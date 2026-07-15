using System.ComponentModel;
using System.Runtime.InteropServices;

namespace Nameplate.App;

/// <summary>Observes global mouse-down events without suppressing or rewriting them.</summary>
internal sealed class GlobalMouseMonitor : IDisposable
{
    private const int WhMouseLl = 14;
    private const int WmLeftButtonDown = 0x0201;
    private const int WmRightButtonDown = 0x0204;
    private const int WmMiddleButtonDown = 0x0207;
    private const int WmXButtonDown = 0x020B;
    private const uint WmQuit = 0x0012;

    private readonly Action mouseDown;
    private readonly HookProcedure procedure;
    private readonly ManualResetEventSlim ready = new();
    private readonly Thread thread;
    private Exception? startupError;
    private uint threadId;
    private nint hook;

    public GlobalMouseMonitor(Action mouseDown)
    {
        this.mouseDown = mouseDown;
        procedure = OnHook;
        thread = new Thread(RunMessageLoop)
        {
            IsBackground = true,
            Name = "Nameplate global mouse monitor",
        };
        thread.Start();
        ready.Wait();
        if (startupError is not null)
        {
            throw startupError;
        }
    }

    public void Dispose()
    {
        if (threadId == 0)
        {
            return;
        }

        _ = PostThreadMessage(threadId, WmQuit, 0, 0);
        thread.Join();
        threadId = 0;
        ready.Dispose();
    }

    private void RunMessageLoop()
    {
        threadId = GetCurrentThreadId();
        _ = PeekMessage(out _, 0, 0, 0, 0);
        hook = SetWindowsHookEx(WhMouseLl, procedure, GetModuleHandle(null), 0);
        if (hook == 0)
        {
            startupError = new Win32Exception(Marshal.GetLastWin32Error(), "Could not install the global mouse monitor.");
            threadId = 0;
            ready.Set();
            return;
        }

        ready.Set();
        try
        {
            while (GetMessage(out var message, 0, 0, 0) > 0)
            {
                _ = TranslateMessage(ref message);
                _ = DispatchMessage(ref message);
            }
        }
        finally
        {
            _ = UnhookWindowsHookEx(hook);
            hook = 0;
        }
    }

    private nint OnHook(int code, nint message, nint data)
    {
        if (code >= 0 && IsButtonDownMessage((int)message))
        {
            try
            {
                mouseDown();
            }
            catch
            {
                // Never let application shutdown race through the native hook boundary.
            }
        }

        return CallNextHookEx(0, code, message, data);
    }

    private static bool IsButtonDownMessage(int message) => message is
        WmLeftButtonDown or WmRightButtonDown or WmMiddleButtonDown or WmXButtonDown;

    private delegate nint HookProcedure(int code, nint message, nint data);

    [StructLayout(LayoutKind.Sequential)]
    private struct Message
    {
        public nint Window;
        public uint Value;
        public nuint WParam;
        public nint LParam;
        public uint Time;
        public int PointX;
        public int PointY;
        public uint Private;
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern nint SetWindowsHookEx(int hookId, HookProcedure procedure, nint module, uint threadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(nint hook);

    [DllImport("user32.dll")]
    private static extern nint CallNextHookEx(nint hook, int code, nint message, nint data);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern int GetMessage(out Message message, nint window, uint minimum, uint maximum);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PeekMessage(out Message message, nint window, uint minimum, uint maximum, uint remove);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool TranslateMessage([In] ref Message message);

    [DllImport("user32.dll")]
    private static extern nint DispatchMessage([In] ref Message message);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool PostThreadMessage(uint threadId, uint message, nuint wParam, nint lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern nint GetModuleHandle(string? moduleName);

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();
}
