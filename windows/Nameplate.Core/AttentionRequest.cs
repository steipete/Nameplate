using System.Text.Json;
using System.Text.Json.Serialization;

namespace Nameplate.Core;

public sealed record AttentionRequest
{
    [JsonPropertyName("command")]
    public string Command { get; init; } = "attention";

    [JsonPropertyName("message")]
    public required string Message { get; init; }

    [JsonPropertyName("title")]
    public string? Title { get; init; }

    [JsonPropertyName("duration")]
    public double? Duration { get; init; }

    [JsonPropertyName("color")]
    public string? Color { get; init; }

    public string ToJson() => JsonSerializer.Serialize(this, JsonOptions.Default);

    public static AttentionRequest? FromJson(string json)
    {
        try
        {
            return JsonSerializer.Deserialize<AttentionRequest>(json, JsonOptions.Default);
        }
        catch (JsonException)
        {
            return null;
        }
    }
}

public sealed record PipeCommand
{
    [JsonPropertyName("command")]
    public required string Command { get; init; }
}

public static class JsonOptions
{
    public static JsonSerializerOptions Default { get; } = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
    };
}
