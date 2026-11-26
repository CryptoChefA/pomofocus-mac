import AppKit
import Carbon.HIToolbox
import PomofocusShared
import SwiftUI

/// A key combination: the key, its modifiers and how to show it.
struct Hotkey: Codable, Equatable {
    var keyCode: UInt32
    /// `NSEvent.ModifierFlags` raw value, device-independent bits only.
    var modifiers: UInt
    var label: String

    var flags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var display: String {
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + label
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    /// From a key press while recording. Needs ⌘, ⌥ or ⌃, unless it's a function key,
    /// so typing in another app can't set it off.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let code = UInt32(event.keyCode)
        let function = Self.functionKeys[code]
        guard function != nil || !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let label = function ?? Self.namedKeys[code]
            ?? event.charactersIgnoringModifiers?.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !label.isEmpty else { return nil }
        self.keyCode = code
        self.modifiers = flags.rawValue
        self.label = label
    }

    private static let functionKeys: [UInt32: String] = [
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3", UInt32(kVK_F4): "F4",
        UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6", UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8",
        UInt32(kVK_F9): "F9", UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
        UInt32(kVK_F13): "F13", UInt32(kVK_F14): "F14", UInt32(kVK_F15): "F15", UInt32(kVK_F16): "F16",
        UInt32(kVK_F17): "F17", UInt32(kVK_F18): "F18", UInt32(kVK_F19): "F19",
    ]

    private static let namedKeys: [UInt32: String] = [
        UInt32(kVK_Space): "Space", UInt32(kVK_Return): "↩", UInt32(kVK_Tab): "⇥",
        UInt32(kVK_LeftArrow): "←", UInt32(kVK_RightArrow): "→", UInt32(kVK_UpArrow): "↑", UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_Home): "↖", UInt32(kVK_End): "↘", UInt32(kVK_PageUp): "⇞", UInt32(kVK_PageDown): "⇟",
    ]
}

/// What a shortcut can do. Each runs the same action as the widget's buttons.
enum HotkeyAction: String, CaseIterable, Identifiable, Codable {
    case toggle, next, skipBreak, end, show

    var id: String { rawValue }

    var title: String {
        switch self {
        case .toggle: "Start or pause"
        case .next: "Next"
        case .skipBreak: "Skip break"
        case .end: "End session"
        case .show: "Show Pomofocus"
        }
    }

    var detail: String {
        switch self {
        case .toggle: "Starts a block, or pauses and resumes the one running"
        case .next: "After the bell, starts the break or the next block"
        case .skipBreak: "Ends the break and starts focusing"
        case .end: "Ends the session and saves it"
        case .show: "Brings the window to the front"
        }
    }

    var control: PomofocusControl? {
        switch self {
        case .toggle: .toggle
        case .next: .next
        case .skipBreak: .skipBreak
        case .end: .end
        case .show: nil
        }
    }
}

/// Shortcuts that work from any app, set in Settings → Shortcuts. They use the system's
/// hot key registration, which needs no Accessibility permission and never sees other keys.
@MainActor
@Observable
final class GlobalHotkeys {
    static let shared = GlobalHotkeys()
    private static let storageKey = "globalHotkeys"

    private(set) var hotkeys: [HotkeyAction: Hotkey] = [:]
    /// Shortcuts another app already holds, so Settings can say so.
    private(set) var taken: Set<HotkeyAction> = []
    /// While one is being recorded, none fire.
    var isRecording = false { didSet { isRecording ? unregisterAll() : registerAll() } }

    @ObservationIgnored weak var model: AppModel?
    @ObservationIgnored private var registered: [HotkeyAction: EventHotKeyRef] = [:]
    @ObservationIgnored private var handler: EventHandlerRef?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([String: Hotkey].self, from: data) {
            for (key, hotkey) in saved {
                if let action = HotkeyAction(rawValue: key) { hotkeys[action] = hotkey }
            }
        }
    }

    /// Called once at launch with the app's model.
    func start(model: AppModel) {
        self.model = model
        installHandler()
        registerAll()
    }

    func set(_ hotkey: Hotkey?, for action: HotkeyAction) {
        // One combination does one thing: taking it from another action clears that one.
        if let hotkey {
            for (other, existing) in hotkeys where other != action
                && existing.keyCode == hotkey.keyCode && existing.modifiers == hotkey.modifiers {
                hotkeys[other] = nil
            }
        }
        hotkeys[action] = hotkey
        save()
        if !isRecording { registerAll() }
    }

    private func save() {
        let plain = Dictionary(uniqueKeysWithValues: hotkeys.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(plain) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            let index = Int(id.id)
            Task { @MainActor in GlobalHotkeys.shared.fire(index) }
            return noErr
        }, 1, &spec, nil, &handler)
    }

    private func fire(_ index: Int) {
        guard HotkeyAction.allCases.indices.contains(index) else { return }
        let action = HotkeyAction.allCases[index]
        if let control = action.control {
            model?.perform(control)
        } else {
            NSApp.activate()
            NSApp.windows.first { $0.canBecomeMain && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
        }
    }

    private func unregisterAll() {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered = [:]
    }

    private func registerAll() {
        unregisterAll()
        var failed: Set<HotkeyAction> = []
        for (index, action) in HotkeyAction.allCases.enumerated() {
            guard let hotkey = hotkeys[action] else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: OSType(0x504D_4643), id: UInt32(index)) // "PMFC"
            let status = RegisterEventHotKey(hotkey.keyCode, hotkey.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref)
            if status == noErr, let ref { registered[action] = ref } else { failed.insert(action) }
        }
        taken = failed
    }
}

// MARK: - Settings

struct ShortcutSettingsCard: View {
    @State private var hotkeys = GlobalHotkeys.shared

    var body: some View {
        SettingsCard(title: "Shortcuts", icon: "keyboard",
                     summary: hotkeys.hotkeys.isEmpty ? "None set" : "\(hotkeys.hotkeys.count) set") {
            Text("These work from any app, so you can start your break after the bell without switching back.")
                .font(.system(size: 11))
                .foregroundStyle(NonnaTheme.secondaryInk)
            ForEach(HotkeyAction.allCases) { action in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(action.title)
                            .font(.system(size: 12, weight: .medium))
                        Text(hotkeys.taken.contains(action) ? "Another app already uses this shortcut. Pick another." : action.detail)
                            .font(.system(size: 10))
                            .foregroundStyle(hotkeys.taken.contains(action) ? NonnaTheme.terracotta : NonnaTheme.secondaryInk)
                    }
                    Spacer(minLength: 12)
                    ShortcutRecorder(hotkey: hotkeys.hotkeys[action]) { hotkeys.set($0, for: action) }
                }
            }
        }
    }
}

/// Click, then press the keys. Esc cancels; Delete clears.
struct ShortcutRecorder: View {
    let hotkey: Hotkey?
    let onChange: (Hotkey?) -> Void
    @State private var recording = false
    @State private var monitor: Any?
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button { recording ? stop() : record() } label: {
                Text(recording ? "Type shortcut" : hotkey?.display ?? "Record shortcut")
                    .font(.system(size: 12, weight: hotkey == nil || recording ? .regular : .semibold).monospacedDigit())
                    .foregroundStyle(recording ? NonnaTheme.terracotta : hotkey == nil ? NonnaTheme.secondaryInk : NonnaTheme.ink)
                    .frame(width: 130, height: 26)
                    .background(NonnaTheme.raisedPaper.opacity(hovering || recording ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(recording ? NonnaTheme.terracotta : NonnaTheme.line, lineWidth: recording ? 1.2 : 0.8)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(recording ? "Press a key with ⌘, ⌥ or ⌃. Esc cancels" : "Click to set a shortcut")

            Button { onChange(nil) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(NonnaTheme.secondaryInk)
            .opacity(hotkey == nil || recording ? 0 : 1)
            .disabled(hotkey == nil || recording)
            .accessibilityLabel("Clear shortcut")
        }
        .onDisappear { stop() }
    }

    private func record() {
        recording = true
        GlobalHotkeys.shared.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch Int(event.keyCode) {
            case kVK_Escape:
                stop()
            case kVK_Delete, kVK_ForwardDelete:
                onChange(nil)
                stop()
            default:
                guard let hotkey = Hotkey(event: event) else { NSSound.beep(); return nil }
                onChange(hotkey)
                stop()
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            GlobalHotkeys.shared.isRecording = false
        }
    }
}
