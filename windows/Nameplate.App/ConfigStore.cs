using System.IO;
using System.Text.Json;
using Timer = System.Threading.Timer;
using Nameplate.Core;

namespace Nameplate.App;

internal sealed class ConfigStore : IDisposable
{
    private readonly string host = Environment.MachineName;
    private readonly List<FileSystemWatcher> watchers = [];
    private readonly object reloadLock = new();
    private Timer? reloadTimer;

    public ConfigStore()
    {
        FleetPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".config", "nameplate", "fleet.json");
        SettingsPath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Nameplate", "settings.json");
        Reload();
        Watch(FleetPath);
        Watch(SettingsPath);
    }

    public event EventHandler? Changed;

    public string FleetPath { get; }

    public string SettingsPath { get; }

    public string ConfigFolder => Path.GetDirectoryName(SettingsPath)!;

    public LocalSettings Settings { get; private set; } = new();

    public MachineIdentity Identity { get; private set; } = IdentityResolver.Resolve(Environment.MachineName, new LocalSettings(), null);

    public void Save(LocalSettings settings)
    {
        Directory.CreateDirectory(ConfigFolder);
        var json = JsonSerializer.Serialize(settings, new JsonSerializerOptions(JsonOptions.Default) { WriteIndented = true });
        File.WriteAllText(SettingsPath, json);
        Settings = settings;
        ReloadIdentity();
        Changed?.Invoke(this, EventArgs.Empty);
    }

    public void Dispose()
    {
        foreach (var watcher in watchers)
        {
            watcher.Dispose();
        }

        reloadTimer?.Dispose();
    }

    private void Reload()
    {
        Settings = LoadSettings();
        ReloadIdentity();
    }

    private void ReloadIdentity()
    {
        var fleet = LoadFleet();
        Identity = IdentityResolver.Resolve(host, Settings, FleetFile.Entry(fleet, host));
    }

    private LocalSettings LoadSettings()
    {
        try
        {
            return File.Exists(SettingsPath)
                ? JsonSerializer.Deserialize<LocalSettings>(File.ReadAllText(SettingsPath), JsonOptions.Default) ?? new LocalSettings()
                : new LocalSettings();
        }
        catch (JsonException)
        {
            return new LocalSettings();
        }
        catch (IOException)
        {
            return new LocalSettings();
        }
    }

    private IReadOnlyDictionary<string, FleetEntry> LoadFleet()
    {
        try
        {
            return File.Exists(FleetPath) ? FleetFile.Parse(File.ReadAllText(FleetPath)) : new Dictionary<string, FleetEntry>();
        }
        catch (IOException)
        {
            return new Dictionary<string, FleetEntry>();
        }
    }

    private void Watch(string path)
    {
        var directory = Path.GetDirectoryName(path)!;
        Directory.CreateDirectory(directory);
        var watcher = new FileSystemWatcher(directory, Path.GetFileName(path))
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.FileName | NotifyFilters.CreationTime,
            EnableRaisingEvents = true,
        };
        watcher.Changed += OnFileChanged;
        watcher.Created += OnFileChanged;
        watcher.Deleted += OnFileChanged;
        watcher.Renamed += OnFileRenamed;
        watchers.Add(watcher);
    }

    private void OnFileChanged(object sender, FileSystemEventArgs args) => ScheduleReload();

    private void OnFileRenamed(object sender, RenamedEventArgs args) => ScheduleReload();

    private void ScheduleReload()
    {
        lock (reloadLock)
        {
            reloadTimer?.Dispose();
            reloadTimer = new Timer(_ =>
            {
                Reload();
                Changed?.Invoke(this, EventArgs.Empty);
            }, null, 150, Timeout.Infinite);
        }
    }
}
