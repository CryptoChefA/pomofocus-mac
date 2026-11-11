import AppKit
import Foundation
import SwiftUI

/// Silences notifications while a focus block runs. macOS doesn't let apps switch Focus
/// modes themselves, so Pomofocus uses two tiny shortcuts in the Shortcuts app: one turns
/// Do Not Disturb on, the other turns it off. Pomofocus makes them on this Mac, the person
/// adds them with one click each, and from then on it runs them with `shortcuts run` as
/// blocks start and stop.
@MainActor @Observable
final class FocusQuiet {
    static let shared = FocusQuiet()

    /// Settings → Experience. Off until someone turns it on.
    static let enabledKey = "focus.silenceNotifications"
    static let onName = "Pomofocus Quiet On"
    static let offName = "Pomofocus Quiet Off"
    /// Whether Pomofocus last turned Do Not Disturb on, kept across launches so a crash or a
    /// force quit mid-block never leaves notifications silenced.
    private static let appliedKey = "focus.silenceApplied"

    /// Both shortcuts are in the Shortcuts app; nil until checked.
    private(set) var installed: Bool?
    private(set) var installing = false
    private(set) var problem: String?

    @ObservationIgnored private var waitForInstall: Task<Void, Never>?

    private var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    private var applied: Bool {
        get { UserDefaults.standard.bool(forKey: Self.appliedKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.appliedKey) }
    }

    private init() {
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FocusQuiet.shared.turnOffBeforeQuitting() }
        }
    }

    /// Call whenever the timer changes. `quiet` is true while a focus block is counting.
    func update(quiet: Bool) {
        let wanted = quiet && enabled
        guard wanted != applied else { return }
        applied = wanted
        Self.run(wanted ? Self.onName : Self.offName)
    }

    private func turnOffBeforeQuitting() {
        guard applied else { return }
        applied = false
        Self.run(Self.offName, waitUpTo: 4)
    }

    // MARK: Shortcuts

    /// Looks in the Shortcuts app for the two shortcuts.
    func checkInstalled() async {
        let names = await Self.output(of: ["list"])
        let lines = Set(names.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) })
        installed = lines.contains(Self.onName) && lines.contains(Self.offName)
    }

    /// Writes the two shortcuts, has this Mac sign them (Shortcuts only imports signed
    /// ones), and opens them in the Shortcuts app to be added. Then waits for them to appear.
    func install() {
        guard !installing else { return }
        installing = true
        problem = nil
        Task {
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Pomofocus Shortcuts", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var signed: [URL] = []
            for (name, on) in [(Self.onName, true), (Self.offName, false)] {
                let unsigned = folder.appendingPathComponent("\(name) (unsigned).shortcut")
                let output = folder.appendingPathComponent("\(name).shortcut")
                guard let data = Self.shortcutFile(turningOn: on), (try? data.write(to: unsigned)) != nil else { continue }
                try? FileManager.default.removeItem(at: output)
                _ = await Self.output(of: ["sign", "--mode", "anyone", "--input", unsigned.path, "--output", output.path])
                if FileManager.default.fileExists(atPath: output.path) { signed.append(output) }
            }
            guard signed.count == 2 else {
                problem = "The shortcuts couldn't be prepared. Shortcuts needs you to be signed in to iCloud to add them. You can also make them yourself: in Shortcuts, add a Set Focus action that turns Do Not Disturb on, name it \"\(Self.onName)\", and a second that turns it off, named \"\(Self.offName)\"."
                installing = false
                return
            }
            for url in signed {
                NSWorkspace.shared.open(url)
                try? await Task.sleep(for: .seconds(1.2))
            }
            waitForAdded()
        }
    }

    private func waitForAdded() {
        waitForInstall?.cancel()
        waitForInstall = Task {
            for _ in 0..<90 {
                await checkInstalled()
                if installed == true { break }
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
            }
            installing = false
        }
    }

    /// A one-action shortcut: Set Focus, Do Not Disturb, on or off.
    private static func shortcutFile(turningOn on: Bool) -> Data? {
        let file: [String: Any] = [
            "WFWorkflowClientVersion": "2607.0.3",
            "WFWorkflowMinimumClientVersion": 900,
            "WFWorkflowMinimumClientVersionString": "900",
            "WFWorkflowIcon": ["WFWorkflowIconStartColor": on ? 463_140_863 : 255, "WFWorkflowIconGlyphNumber": 59511],
            "WFWorkflowImportQuestions": [Any](),
            "WFWorkflowTypes": [Any](),
            "WFWorkflowInputContentItemClasses": [Any](),
            "WFWorkflowActions": [[
                "WFWorkflowActionIdentifier": "is.workflow.actions.dnd.set",
                "WFWorkflowActionParameters": [
                    "Enabled": on ? 1 : 0,
                    "AssertionType": "Turned Off",
                    "FocusModes": ["Identifier": "com.apple.donotdisturb.mode.default", "DisplayString": "Do Not Disturb"],
                ] as [String: Any],
            ] as [String: Any]],
        ]
        return try? PropertyListSerialization.data(fromPropertyList: file, format: .binary, options: 0)
    }

    // MARK: Running the Shortcuts command

    private nonisolated static func run(_ name: String, waitUpTo seconds: Double = 0) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
        process.arguments = ["run", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil, seconds > 0 else { return }
        let deadline = Date().addingTimeInterval(seconds)
        while process.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
    }

    private nonisolated static func output(of arguments: [String]) async -> String {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            guard (try? process.run()) != nil else { return "" }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }.value
    }
}

/// Settings → Experience: the switch, and the one-time setup of the two shortcuts.
struct FocusQuietSettingsRow: View {
    @Environment(AppModel.self) private var model
    @AppStorage(FocusQuiet.enabledKey) private var enabled = false
    private var quiet: FocusQuiet { FocusQuiet.shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Silence notifications during focus")
                        .font(.system(size: 12, weight: .medium))
                    Text("Turns on Do Not Disturb while a block runs, and back off for breaks")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer(minLength: 12)
                Toggle("Silence notifications during focus", isOn: $enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            if enabled {
                if quiet.installed == false {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "moon.fill")
                            .foregroundStyle(NonnaTheme.terracotta)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Pomofocus does this with two small shortcuts. Click Add Shortcut for each one when the Shortcuts app opens.")
                                .font(.system(size: 11))
                                .fixedSize(horizontal: false, vertical: true)
                            if let problem = quiet.problem {
                                Text(problem)
                                    .font(.system(size: 10))
                                    .foregroundStyle(NonnaTheme.alert)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 8)
                        Button(quiet.installing ? "Waiting for Shortcuts…" : "Add the shortcuts") { quiet.install() }
                            .buttonStyle(NonnaButtonStyle(prominent: !quiet.installing))
                            .disabled(quiet.installing)
                    }
                    .padding(12)
                    .background(NonnaTheme.pane(NonnaTheme.raisedPaper, 0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.banner(reduceMotion: false))
                } else if quiet.installed == true {
                    Label("Ready. Do Not Disturb turns on with your next block.", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.sage)
                }
            }
        }
        .animation(NonnaMotion.dismiss, value: quiet.installed)
        .task(id: enabled) {
            if enabled { await quiet.checkInstalled() }
        }
        .onChange(of: enabled) { _, _ in
            // Turned off mid-block, Do Not Disturb goes off straight away; turned on, it
            // comes on if a block is already running.
            quiet.update(quiet: model.isQuietTime)
        }
    }
}
