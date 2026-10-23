using System.Diagnostics;
using System.IO;
using System.IO.Pipes;
using System.Security.AccessControl;
using System.Security.Principal;
using System.Text;
using System.Text.Json;

namespace Nameplate.App;

internal sealed class PipeServer : IDisposable
{
    public static readonly string PipeName = $"nameplate-{Process.GetCurrentProcess().SessionId}";

    private readonly Action<string> dispatch;
    private readonly CancellationTokenSource cancellation = new();
    private readonly Task serverTask;

    public PipeServer(Action<string> dispatch)
    {
        this.dispatch = dispatch;
        serverTask = ListenAsync(cancellation.Token);
    }

    public void Dispose()
    {
        cancellation.Cancel();
        serverTask.GetAwaiter().GetResult();
        cancellation.Dispose();
    }

    private async Task ListenAsync(CancellationToken cancellationToken)
    {
        try
        {
            using var identity = WindowsIdentity.GetCurrent();
            var user = identity.User ?? throw new InvalidOperationException("The current Windows user has no SID.");
            var security = new PipeSecurity();
            // CurrentUserOnly uses the token owner, which can be the Administrators group when elevated.
            security.AddAccessRule(new PipeAccessRule(user, PipeAccessRights.FullControl, AccessControlType.Allow));
            while (!cancellationToken.IsCancellationRequested)
            {
                await using var pipe = NamedPipeServerStreamAcl.Create(
                    PipeName,
                    PipeDirection.In,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous,
                    0,
                    0,
                    security);
                await pipe.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
                using var reader = new StreamReader(
                    pipe,
                    Encoding.UTF8,
                    detectEncodingFromByteOrderMarks: false,
                    bufferSize: 1024,
                    leaveOpen: false);
                var line = await reader.ReadLineAsync(cancellationToken).ConfigureAwait(false);
                if (!string.IsNullOrWhiteSpace(line))
                {
                    dispatch(line);
                }
            }
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
    }

    public static string? GetCommand(string json)
    {
        try
        {
            using var document = JsonDocument.Parse(json);
            return document.RootElement.TryGetProperty("command", out var value) ? value.GetString() : null;
        }
        catch (JsonException)
        {
            return null;
        }
    }
}
