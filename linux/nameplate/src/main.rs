mod cli;
mod config;
mod daemon;
mod overlays;
mod platform;

use gtk::prelude::*;
use nameplate_core::DaemonCommand;
use std::cell::RefCell;
use std::rc::Rc;
use std::sync::mpsc;
use std::time::Duration;
#[cfg(target_os = "linux")]
use std::time::Instant;

enum Event {
    Command(DaemonCommand),
    #[cfg(target_os = "linux")]
    GlobalClick(Instant),
    Reload,
    MonitorsChanged,
    Unlock,
}

struct Runtime {
    overlays: RefCell<overlays::OverlayManager>,
    _hold: gtk::gio::ApplicationHoldGuard,
    _fleet_monitor: Option<gtk::gio::FileMonitor>,
    _logind_subscription: Option<gtk::gio::SignalSubscription>,
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    if !args.is_empty() {
        match cli::parse_command(&args) {
            Ok(Some(command)) => {
                if let Err(error) = daemon::send_to_daemon(&command) {
                    eprintln!("nameplate: {error}");
                    std::process::exit(1);
                }
            }
            Ok(None) => cli::print_help(),
            Err(error) => {
                eprintln!("nameplate: {error}\n");
                cli::print_help();
                std::process::exit(2);
            }
        }
        return;
    }

    run_daemon();
}

fn run_daemon() {
    let application = gtk::Application::builder()
        .application_id("com.steipete.nameplate.linux")
        .flags(gtk::gio::ApplicationFlags::NON_UNIQUE)
        .build();

    application.connect_activate(|application| {
        install_transparent_css();
        let (sender, receiver) = mpsc::channel();
        if let Err(error) = daemon::start_socket_listener(sender.clone()) {
            eprintln!("nameplate: socket: {error}");
            application.quit();
            return;
        }

        let overlays = overlays::OverlayManager::new(application);
        let fleet_monitor = config::watch_config(sender.clone())
            .map_err(|error| {
                eprintln!("nameplate: config watch: {error}");
                error
            })
            .ok();
        let logind_subscription = subscribe_to_unlock(sender.clone());
        let runtime = Rc::new(Runtime {
            overlays: RefCell::new(overlays),
            _hold: application.hold(),
            _fleet_monitor: fleet_monitor,
            _logind_subscription: logind_subscription,
        });

        if let Some(display) = gtk::gdk::Display::default() {
            if !platform::start_global_click_monitor(&display, sender.clone()) {
                eprintln!("nameplate: global attention-click monitoring requires X11");
            }
            let monitors = display.monitors();
            let sender = sender.clone();
            monitors.connect_items_changed(move |_, _, _, _| {
                let _ = sender.send(Event::MonitorsChanged);
            });
        }

        // GDK can finish publishing the initial monitor list during activation.
        // Attach its change handler first, then build windows on the next main-loop turn.
        let runtime_for_initial_rebuild = Rc::clone(&runtime);
        gtk::glib::idle_add_local_once(move || {
            runtime_for_initial_rebuild.overlays.borrow_mut().rebuild();
        });

        let runtime_for_events = Rc::clone(&runtime);
        gtk::glib::timeout_add_local(Duration::from_millis(40), move || {
            while let Ok(event) = receiver.try_recv() {
                let mut overlays = runtime_for_events.overlays.borrow_mut();
                match event {
                    Event::Command(DaemonCommand::Splash) => overlays.show_splash(true),
                    Event::Command(DaemonCommand::Attention {
                        message,
                        title,
                        duration,
                        color,
                    }) => overlays.show_attention(message, title, duration, color),
                    #[cfg(target_os = "linux")]
                    Event::GlobalClick(clicked_at) => {
                        overlays.dismiss_attention_from_click(clicked_at)
                    }
                    Event::Reload => overlays.reload(),
                    Event::MonitorsChanged => {
                        overlays.rebuild();
                        overlays.show_splash(false);
                    }
                    Event::Unlock => overlays.show_splash(false),
                }
            }
            gtk::glib::ControlFlow::Continue
        });
    });

    application.connect_shutdown(|_| daemon::remove_socket());
    application.run();
}

fn install_transparent_css() {
    let provider = gtk::CssProvider::new();
    provider.load_from_data(".nameplate-overlay { background: transparent; }");
    if let Some(display) = gtk::gdk::Display::default() {
        gtk::style_context_add_provider_for_display(
            &display,
            &provider,
            gtk::STYLE_PROVIDER_PRIORITY_APPLICATION,
        );
    }
}

fn subscribe_to_unlock(sender: mpsc::Sender<Event>) -> Option<gtk::gio::SignalSubscription> {
    let connection =
        match gtk::gio::bus_get_sync(gtk::gio::BusType::System, gtk::gio::Cancellable::NONE) {
            Ok(connection) => connection,
            Err(error) => {
                eprintln!("nameplate: logind unavailable: {error}");
                return None;
            }
        };
    Some(connection.subscribe_to_signal(
        Some("org.freedesktop.login1"),
        Some("org.freedesktop.login1.Session"),
        Some("Unlock"),
        None,
        None,
        gtk::gio::DBusSignalFlags::NONE,
        move |_| {
            let _ = sender.send(Event::Unlock);
        },
    ))
}
