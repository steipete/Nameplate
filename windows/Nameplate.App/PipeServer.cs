using System.IO;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using Nameplate.Core;

namespace Nameplate.App;

internal sealed class PipeServer : IDisposable
{
    public const string PipeName = "nameplate";

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
            while (!cancellationToken.IsCancellationRequested)
            {
                await using var pipe = new NamedPipeServerStream(
                    PipeName,
                    PipeDirection.In,
                    1,
                    PipeTransmissionMode.Byte,
                    PipeOptions.Asynchronous);
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
