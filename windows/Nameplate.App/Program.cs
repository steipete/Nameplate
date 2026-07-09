using System.IO;
using System.Diagnostics;
using System.IO.Pipes;
using System.Text;
using System.Text.Json;
using Nameplate.Core;

namespace Nameplate.App;

public static class Program
{
    private const string MutexName = "Local\\Nameplate";

    [STAThread]
    public static int Main(string[] args)
    {
        if (args.Length > 0)
        {
            return RunCommand(args);
        }

        using var mutex = new Mutex(true, MutexName, out var ownsMutex);
        if (!ownsMutex)
        {
            return PipeClient.SendAsync(JsonSerializer.Serialize(new PipeCommand { Command = "activate" }, JsonOptions.Default), false)
                .GetAwaiter().GetResult();
        }

        var application = new NameplateApplication();
        return application.Run();
    }

    private static int RunCommand(string[] args)
    {
        string json;
        switch (args[0].ToLowerInvariant())
        {
            case "splash" when args.Length == 1:
                json = JsonSerializer.Serialize(new PipeCommand { Command = "splash" }, JsonOptions.Default);
                break;
            case "attention":
                if (!TryParseAttention(args, out var request, out var error))
                {
                    Console.Error.WriteLine(error);
                    PrintUsage();
                    return 2;
                }

                json = request!.ToJson();
                break;
            default:
                PrintUsage();
                return 2;
        }

        return PipeClient.SendAsync(json, true).GetAwaiter().GetResult();
    }

    private static bool TryParseAttention(string[] args, out AttentionRequest? request, out string? error)
    {
        request = null;
        error = null;
        if (args.Length < 2 || args[1].StartsWith("--", StringComparison.Ordinal))
        {
            error = "attention requires a message.";
            return false;
        }

        string? title = null;
        string? color = null;
        double? duration = null;
        for (var index = 2; index < args.Length; index += 2)
        {
            if (index + 1 >= args.Length)
            {
                error = $"Missing value for {args[index]}.";
                return false;
            }

            var value = args[index + 1];
            switch (args[index])
            {
                case "--title":
                    title = value;
                    break;
                case "--duration" when double.TryParse(value, System.Globalization.CultureInfo.InvariantCulture, out var parsed) && parsed > 0:
                    duration = parsed;
                    break;
                case "--color" when ColorHex.Normalize(value) is { } normalized:
                    color = normalized;
                    break;
                case "--duration":
                    error = "Duration must be a positive number of seconds.";
                    return false;
                case "--color":
                    error = "Color must be a 3- or 6-digit hex value.";
                    return false;
                default:
                    error = $"Unknown option {args[index]}.";
                    return false;
            }
        }

        request = new AttentionRequest
        {
            Message = args[1],
            Title = title,
            Duration = duration,
            Color = color,
        };
        return true;
    }

    private static void PrintUsage()
    {
        Console.Error.WriteLine("Usage:");
        Console.Error.WriteLine("  nameplate splash");
        Console.Error.WriteLine("  nameplate attention \"<message>\" [--title <title>] [--duration <seconds>] [--color <hex>]");
    }
}

internal static class PipeClient
{
    public static async Task<int> SendAsync(string json, bool startIfNeeded)
    {
        if (await TrySendAsync(json).ConfigureAwait(false))
        {
            return 0;
        }

        if (!startIfNeeded || Environment.ProcessPath is not { } executable)
        {
            Console.Error.WriteLine("Nameplate is not running.");
            return 1;
        }

        Process.Start(new ProcessStartInfo(executable) { UseShellExecute = true });
        for (var attempt = 0; attempt < 40; attempt++)
        {
            await Task.Delay(100).ConfigureAwait(false);
            if (await TrySendAsync(json).ConfigureAwait(false))
            {
                return 0;
            }
        }

        Console.Error.WriteLine("Nameplate started but its command pipe did not become available.");
        return 1;
    }

    private static async Task<bool> TrySendAsync(string json)
    {
        try
        {
            await using var pipe = new NamedPipeClientStream(".", PipeServer.PipeName, PipeDirection.Out, PipeOptions.Asynchronous);
            using var timeout = new CancellationTokenSource(TimeSpan.FromMilliseconds(250));
            await pipe.ConnectAsync(timeout.Token).ConfigureAwait(false);
            await using var writer = new StreamWriter(pipe, new UTF8Encoding(false), bufferSize: 1024, leaveOpen: false) { AutoFlush = true };
            await writer.WriteLineAsync(json).ConfigureAwait(false);
            return true;
        }
        catch (IOException)
        {
            return false;
        }
        catch (OperationCanceledException)
        {
            return false;
        }
    }
}
