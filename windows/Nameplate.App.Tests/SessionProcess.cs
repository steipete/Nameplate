using System;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;

namespace Nameplate.Proof
{
    // Compiled by the SYSTEM probe too; keep this compatible with Windows PowerShell's C# compiler.
    public static class SessionProcess
    {
        public static uint ConsoleSessionId { get { return WTSGetActiveConsoleSessionId(); } }

        public static void Run(int sourceProcessId, int sessionId, string commandLine)
        {
            EnablePrivilege("SeTcbPrivilege");
            IntPtr process = OpenProcess(0x1000, false, sourceProcessId);
            if (process == IntPtr.Zero) throw new Win32Exception();
            IntPtr sourceToken = IntPtr.Zero;
            IntPtr token = IntPtr.Zero;
            try
            {
                if (!OpenProcessToken(process, 0x000A, out sourceToken)) throw new Win32Exception();
                if (!DuplicateTokenEx(sourceToken, 0x02000000, IntPtr.Zero, 2, 1, out token)) throw new Win32Exception();
                if (!SetTokenInformation(token, 12, ref sessionId, sizeof(int))) throw new Win32Exception();
                var startup = new StartupInfo { Size = Marshal.SizeOf(typeof(StartupInfo)) };
                ProcessInformation child;
                if (!CreateProcessAsUser(token, IntPtr.Zero, new StringBuilder(commandLine), IntPtr.Zero,
                    IntPtr.Zero, false, 0x08000000, IntPtr.Zero, IntPtr.Zero, ref startup, out child))
                    throw new Win32Exception();
                try
                {
                    using (var running = Process.GetProcessById(child.ProcessId))
                    {
                        if (!running.WaitForExit(45000))
                        {
                            running.Kill();
                            throw new TimeoutException("Second-session probe did not exit.");
                        }
                        if (running.ExitCode != 0) throw new InvalidOperationException("Second-session probe failed.");
                    }
                }
                finally
                {
                    CloseHandle(child.Thread);
                    CloseHandle(child.Process);
                }
            }
            finally
            {
                if (token != IntPtr.Zero) CloseHandle(token);
                if (sourceToken != IntPtr.Zero) CloseHandle(sourceToken);
                CloseHandle(process);
            }
        }

        private static void EnablePrivilege(string name)
        {
            IntPtr token;
            if (!OpenProcessToken(Process.GetCurrentProcess().Handle, 0x0028, out token)) throw new Win32Exception();
            try
            {
                Luid id;
                if (!LookupPrivilegeValue(IntPtr.Zero, name, out id)) throw new Win32Exception();
                var privileges = new TokenPrivileges { Count = 1, Id = id, Attributes = 2 };
                if (!AdjustTokenPrivileges(token, false, ref privileges, 0, IntPtr.Zero, IntPtr.Zero)) throw new Win32Exception();
                int error = Marshal.GetLastWin32Error();
                if (error != 0) throw new Win32Exception(error);
            }
            finally { CloseHandle(token); }
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct Luid { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)]
        private struct TokenPrivileges { public uint Count; public Luid Id; public uint Attributes; }
        [StructLayout(LayoutKind.Sequential)]
        private struct StartupInfo
        {
            public int Size;
            public IntPtr Reserved, Desktop, Title;
            public int X, Y, Width, Height, XChars, YChars, Fill, Flags;
            public short Show, ReservedSize;
            public IntPtr ReservedBytes, Input, Output, Error;
        }
        [StructLayout(LayoutKind.Sequential)]
        private struct ProcessInformation { public IntPtr Process, Thread; public int ProcessId, ThreadId; }

        [DllImport("kernel32.dll")] private static extern uint WTSGetActiveConsoleSessionId();
        [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr OpenProcess(uint access, bool inherit, int id);
        [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr handle);
        [DllImport("advapi32.dll", SetLastError = true)] private static extern bool OpenProcessToken(IntPtr process, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)] private static extern bool DuplicateTokenEx(IntPtr source, uint access, IntPtr attributes, int level, int type, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)] private static extern bool SetTokenInformation(IntPtr token, int type, ref int value, int size);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool LookupPrivilegeValue(IntPtr system, string name, out Luid id);
        [DllImport("advapi32.dll", SetLastError = true)] private static extern bool AdjustTokenPrivileges(IntPtr token, bool disable, ref TokenPrivileges privileges, int length, IntPtr previous, IntPtr returned);
        [DllImport("advapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)] private static extern bool CreateProcessAsUser(IntPtr token, IntPtr application, StringBuilder command, IntPtr processAttributes, IntPtr threadAttributes, bool inherit, uint flags, IntPtr environment, IntPtr directory, ref StartupInfo startup, out ProcessInformation information);
    }
}
