import AppKit
import Foundation
import NameplateCore
import notify

// nameplate CLI — poke the running Nameplate app from scripts and agents.
//
//   nameplate attention <message> [--title <t>] [--duration <s>] [--color <hex>]
//   nameplate splash
//   nameplate settings

let bundleID = "com.steipete.nameplate"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func usage() -> Never {
    print("""
    usage:
      nameplate attention <message> [--title <title>] [--duration <seconds>] [--color <hex>]
      nameplate splash
      nameplate settings

    attention shows a topmost message card with pulsating screen borders —
    use it when an agent needs the human, and always say why.
    """)
    exit(2)
}

/// The app must be running to render anything; launch it if needed.
func ensureAppRunning() {
    let running = NSWorkspace.shared.runningApplications.contains {
        $0.bundleIdentifier?.hasPrefix(bundleID) == true
    }
    if running { return }

    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        fail("Nameplate.app is not installed (bundle id \(bundleID) not found).")
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    let semaphore = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, _ in
        semaphore.signal()
    }
    _ = semaphore.wait(timeout: .now() + 5)
    // Give the fresh instance a beat to register its notification listeners.
    Thread.sleep(forTimeInterval: 0.8)
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }
arguments.removeFirst()

switch command {
case "attention":
    var title: String?
    var duration: Double?
    var color: String?
    var messageParts: [String] = []

    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        func flagValue() -> String {
            index += 1
            guard index < arguments.count else { fail("missing value for \(argument)") }
            return arguments[index]
        }
        switch argument {
        case "--title": title = flagValue()
        case "--duration":
            guard let value = Double(flagValue()) else { fail("--duration expects seconds") }
            duration = value
        case "--color": color = flagValue()
        case "--help", "-h": usage()
        default: messageParts.append(argument)
        }
        index += 1
    }

    let message = messageParts.joined(separator: " ")
    guard !message.isEmpty else { fail("attention needs a message — say why you need the human.") }

    ensureAppRunning()
    do {
        try AttentionRequest(title: title, message: message, duration: duration, color: color).write()
    } catch {
        fail("could not write attention request: \(error.localizedDescription)")
    }
    notify_post(AttentionRequest.notificationName)

case "splash":
    ensureAppRunning()
    notify_post("com.steipete.nameplate.splash")

case "settings":
    ensureAppRunning()
    notify_post("com.steipete.nameplate.settings")

case "--help", "-h", "help":
    usage()

default:
    fail("unknown command: \(command)")
}
