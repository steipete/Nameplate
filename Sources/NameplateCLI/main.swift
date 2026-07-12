import AppKit
import Foundation
import NameplateCore
import notify

// nameplate CLI — poke the running Nameplate app from scripts and agents.
//
//   nameplate attention <message> [--title <t>] [--duration <s>] [--color <hex>]
//                                [--wait] [--timeout <s>]
//   nameplate splash
//   nameplate settings
//   nameplate dismiss

let bundleID = "com.steipete.nameplate"

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func writeToStandardError(_ message: String) {
    FileHandle.standardError.write(Data((message + "\n").utf8))
}

func usage() -> Never {
    print("""
    usage:
      nameplate attention <message> [--title <title>] [--duration <seconds>] [--color <hex>]
        [--wait] [--timeout <seconds>]
        (no --duration: card stays until clicked)
        (--wait timeout defaults to 600 seconds; exits 0 clicked, 3 app-dismissed,
         4 timed out, expired, or superseded)
      nameplate splash
      nameplate settings
      nameplate dismiss

    attention shows a topmost message card with pulsating screen borders —
    use it when an agent needs the human, and always say why.
    """)
    exit(2)
}

/// The app must be running to render anything; launch it if needed.
/// Returns true when the app had to be cold-launched.
@discardableResult
func ensureAppRunning() -> Bool {
    let running = NSWorkspace.shared.runningApplications.contains {
        $0.bundleIdentifier?.hasPrefix(bundleID) == true
    }
    if running { return false }

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
    return true
}

/// Darwin notifications are not queued; on a cold launch the app might still
/// be starting when the first post fires. The app consumes attention requests
/// from disk at startup, and for the notification-only commands we simply
/// post again after a grace period.
func post(_ name: String, retryAfterColdLaunch coldLaunched: Bool) {
    notify_post(name)
    if coldLaunched {
        Thread.sleep(forTimeInterval: 1.5)
        notify_post(name)
    }
}

/// Waits on the Darwin notification and polls the file because notifications
/// are not queued and can be missed between posting the request and registering.
func waitForAttentionAck(id: String, timeout: TimeInterval) -> AttentionAck? {
    AttentionAck.pruneStale()
    let semaphore = DispatchSemaphore(value: 0)
    var token: Int32 = 0
    let status = notify_register_dispatch(
        AttentionAck.notificationName,
        &token,
        DispatchQueue.global(qos: .userInitiated)) { (_: Int32) in
        semaphore.signal()
    }
    defer {
        if status == 0 {
            notify_cancel(token)
        }
    }

    let deadline = ProcessInfo.processInfo.systemUptime + timeout
    while true {
        if let ack = AttentionAck.consume(matching: id) {
            return ack
        }
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else {
            return AttentionAck.consume(matching: id)
        }
        _ = semaphore.wait(timeout: .now() + min(0.5, remaining))
    }
}

var arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else { usage() }
arguments.removeFirst()

switch command {
case "attention":
    var title: String?
    var duration: Double?
    var color: String?
    var shouldWait = false
    var timeoutSpecified = false
    var timeout: TimeInterval = 600
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
        case "--color":
            let value = flagValue()
            guard let normalized = ColorHex.normalize(value) else {
                fail("--color must be a 3- or 6-digit hex color")
            }
            color = normalized
        case "--wait": shouldWait = true
        case "--timeout":
            timeoutSpecified = true
            guard let value = Double(flagValue()), value.isFinite, value > 0 else {
                fail("--timeout expects a positive number of seconds")
            }
            timeout = value
        case "--help", "-h": usage()
        default: messageParts.append(argument)
        }
        index += 1
    }

    let message = messageParts.joined(separator: " ")
    guard !message.isEmpty else { fail("attention needs a message — say why you need the human.") }
    guard !timeoutSpecified || shouldWait else { fail("--timeout requires --wait") }
    let requestID = shouldWait ? UUID().uuidString : nil

    do {
        try AttentionRequest(
            id: requestID,
            title: title,
            message: message,
            duration: duration,
            color: color,
            createdAt: Date()).write()
    } catch {
        fail("could not write attention request: \(error.localizedDescription)")
    }
    // On a cold launch the app consumes the request file at startup, so a
    // missed notification cannot drop the alert.
    ensureAppRunning()
    notify_post(AttentionRequest.notificationName)

    if let requestID {
        guard let ack = waitForAttentionAck(id: requestID, timeout: timeout) else {
            AttentionAck.remove(matching: requestID)
            writeToStandardError("attention outcome: timed out")
            exit(4)
        }
        writeToStandardError("attention outcome: \(ack.outcome.rawValue)")
        switch ack.outcome {
        case .clicked:
            exit(0)
        case .autoDismissed:
            exit(3)
        case .expired, .superseded:
            exit(4)
        }
    }

case "splash":
    let coldLaunched = ensureAppRunning()
    post("com.steipete.nameplate.splash", retryAfterColdLaunch: coldLaunched)

case "settings":
    let coldLaunched = ensureAppRunning()
    post("com.steipete.nameplate.settings", retryAfterColdLaunch: coldLaunched)

case "dismiss":
    let cutoff = Date()
    do {
        try AttentionDismissal(createdAt: cutoff).write()
    } catch {
        fail("could not write attention dismissal: \(error.localizedDescription)")
    }
    AttentionRequest.discardAll(upTo: cutoff)
    notify_post(AttentionDismissal.notificationName)

case "--help", "-h", "help":
    usage()

default:
    fail("unknown command: \(command)")
}
