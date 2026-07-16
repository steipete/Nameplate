use crate::Event;
use gtk::gio;
use gtk::prelude::*;
use nameplate_core::{Fleet, FleetEntry, Identity, Settings};
use std::fs;
use std::path::PathBuf;
use std::sync::mpsc;

#[derive(Clone, Debug, PartialEq)]
pub struct LoadedConfig {
    pub settings: Settings,
    pub identity: Identity,
}

pub fn config_dir() -> PathBuf {
    std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|home| PathBuf::from(home).join(".config")))
        .unwrap_or_else(|| PathBuf::from(".config"))
        .join("nameplate")
}

pub fn load() -> LoadedConfig {
    let directory = config_dir();
    let settings = fs::read(directory.join("settings.json"))
        .ok()
        .and_then(|data| match serde_json::from_slice(&data) {
            Ok(settings) => Some(settings),
            Err(error) => {
                eprintln!("nameplate: malformed settings.json: {error}");
                None
            }
        })
        .unwrap_or_default();
    let host = nameplate_core::current_hostname();
    let fleet: Option<Fleet> = fs::read(directory.join("fleet.json"))
        .ok()
        .and_then(|data| match nameplate_core::parse_fleet(&data) {
            Ok(fleet) => Some(fleet),
            Err(error) => {
                eprintln!("nameplate: malformed fleet.json: {error}");
                None
            }
        });
    let fleet_entry: Option<&FleetEntry> = fleet
        .as_ref()
        .and_then(|entries| entries.get(&nameplate_core::short_hostname(&host)));
    let identity = nameplate_core::resolve_identity(&host, &settings, fleet_entry);
    LoadedConfig { settings, identity }
}

pub fn watch_config(sender: mpsc::Sender<Event>) -> Result<gio::FileMonitor, gtk::glib::Error> {
    let directory = config_dir();
    if let Err(error) = fs::create_dir_all(&directory) {
        eprintln!("nameplate: cannot create {}: {error}", directory.display());
    }
    let monitor = gio::File::for_path(directory)
        .monitor_directory(gio::FileMonitorFlags::WATCH_MOVES, gio::Cancellable::NONE)?;
    monitor.connect_changed(move |_, file, other, _| {
        let relevant = |file: &gio::File| {
            file.basename()
                .and_then(|name| name.to_str().map(str::to_owned))
                .is_some_and(|name| name == "fleet.json" || name == "settings.json")
        };
        if relevant(file) || other.is_some_and(relevant) {
            let _ = sender.send(Event::Reload);
        }
    });
    Ok(monitor)
}
