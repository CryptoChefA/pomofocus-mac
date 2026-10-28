import AppKit
import SwiftUI

/// Finds a newer Pomofocus on GitHub and installs it in place, so updating is one click.
/// The only request is to the public releases page; nothing about you or your data is sent.
@MainActor
@Observable
final class Updater {
    static let shared = Updater()

    struct Release: Equatable, Codable {
        let version: String
        let notes: String
        let downloadURL: URL
    }

    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
    }

    var phase: Phase = .idle
    var showsSheet = false
    /// A newer version waiting to be installed: shows the red dot on Settings and the
    /// banner. Remembered across launches until it's installed.
    private(set) var available: Release?
    var showsWhatsNew = false
    /// Saves the user's data before the app quits to update. Set by the app at launch.
    @ObservationIgnored var prepareToQuit: (() async -> Bool)?

    static let releasesPage = URL(string: "https://github.com/CryptoChefA/pomofocus-mac/releases/latest")!
    private static let latestAPI = URL(string: "https://api.github.com/repos/CryptoChefA/pomofocus-mac/releases/latest")!
    static let autoCheckKey = "checkForUpdatesAutomatically"
    private static let lastCheckKey = "lastUpdateCheck"
    private static let availableKey = "availableUpdate"

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    private init() {
        // Bring back an update found earlier, if it's still newer than this copy.
        if let data = UserDefaults.standard.data(forKey: Self.availableKey),
           let release = try? JSONDecoder().decode(Release.self, from: data),
           Self.isVersion(release.version, newerThan: currentVersion) {
            available = release
        } else {
            UserDefaults.standard.removeObject(forKey: Self.availableKey)
        }
    }

    private func remember(_ release: Release?) {
        available = release
        if let release, let data = try? JSONEncoder().encode(release) {
            UserDefaults.standard.set(data, forKey: Self.availableKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.availableKey)
        }
    }

    /// The banner's Update now: opens the progress sheet and installs straight away.
    func installAvailable() {
        guard let release = available else { return }
        phase = .available(release)
        showsSheet = true
        Task { await install(release) }
    }

    /// At most once a day, quietly; only speaks up when there's something new.
    func checkAutomaticallyIfDue() async {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.autoCheckKey) as? Bool ?? true else { return }
        if let last = defaults.object(forKey: Self.lastCheckKey) as? Date, Date().timeIntervalSince(last) < 86_400 { return }
        await check(userInitiated: false)
    }

    func check(userInitiated: Bool) async {
        guard phase != .checking, phase != .downloading, phase != .installing else { return }
        if userInitiated { showsSheet = true }
        phase = .checking
        do {
            var request = URLRequest(url: Self.latestAPI, timeoutInterval: 20)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Pomofocus/\(currentVersion)", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.unreachable }
            let release = try Self.parse(data)
            UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
            if Self.isVersion(release.version, newerThan: currentVersion) {
                remember(release)
                // Asked for: answer with the sheet. Found on the daily check: just the red dot
                // on Settings and the banner there, no pop-up.
                phase = userInitiated ? .available(release) : .idle
            } else {
                remember(nil)
                phase = userInitiated ? .upToDate : .idle
            }
        } catch {
            phase = userInitiated ? .failed("Couldn't reach GitHub. Check your connection and try again.") : .idle
        }
    }

    /// Downloads the new version, checks it's really Pomofocus, swaps it in and reopens.
    func install(_ release: Release) async {
        phase = .downloading
        do {
            let (zip, _) = try await URLSession.shared.download(from: release.downloadURL)
            phase = .installing
            let work = FileManager.default.temporaryDirectory.appendingPathComponent("PomofocusUpdate-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let newApp = work.appendingPathComponent("Pomofocus.app")

            // Only ever install a bundle that is this app, newer, and intact.
            guard let bundle = Bundle(url: newApp),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  let version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String,
                  Self.isVersion(version, newerThan: currentVersion) else { throw UpdateError.notPomofocus }
            try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])

            let target = Bundle.main.bundleURL
            guard FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                throw UpdateError.noPermission
            }
            // Never quit to update if the user's data didn't save.
            guard await prepareToQuit?() ?? true else { throw UpdateError.notSaved }
            try launchSwap(newApp: newApp, target: target)
            // An open sheet makes macOS refuse to quit, so close them first.
            for window in NSApp.windows {
                if let sheet = window.attachedSheet { window.endSheet(sheet) }
            }
            NSApp.terminate(nil)
            // Data is already saved; if something still holds the app open, leave anyway.
            try? await Task.sleep(for: .seconds(3))
            exit(0)
        } catch let error as UpdateError {
            phase = .failed(error.message)
        } catch {
            phase = .failed("The download didn't finish. Try again, or download it from the website.")
        }
    }

    /// A tiny script that waits for Pomofocus to quit, replaces it, and opens the new one.
    /// If anything fails, the old app is put back.
    private func launchSwap(newApp: URL, target: URL) throws {
        let backup = target.path + ".previous"
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        rm -rf "$3"
        if mv "$2" "$3" && /usr/bin/ditto "$1" "$2"; then
          rm -rf "$3"
        else
          rm -rf "$2"; mv "$3" "$2"
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$2" 2>/dev/null
        /usr/bin/open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "pomofocus-update", newApp.path, target.path, backup]
        try process.run()
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: tool)
            process.arguments = arguments
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: UpdateError.notPomofocus)
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }

    // MARK: - Parsing

    static func parse(_ data: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browser_download_url: URL
            }
            let tag_name: String
            let body: String?
            let assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let asset = payload.assets.first(where: { $0.name == "Pomofocus.zip" }),
              asset.browser_download_url.scheme == "https",
              asset.browser_download_url.host == "github.com",
              asset.browser_download_url.path.hasPrefix("/CryptoChefA/pomofocus-mac/releases/download/") else { throw UpdateError.unreachable }
        let version = payload.tag_name.hasPrefix("v") ? String(payload.tag_name.dropFirst()) : payload.tag_name
        return Release(version: version, notes: payload.body ?? "", downloadURL: asset.browser_download_url)
    }

    /// "0.23.0" is newer than "0.22.1"; missing parts count as 0.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(a.count, b.count) {
            let (x, y) = (index < a.count ? a[index] : 0, index < b.count ? b[index] : 0)
            if x != y { return x > y }
        }
        return false
    }

    enum UpdateError: Error {
        case unreachable, notPomofocus, noPermission, notSaved

        var message: String {
            switch self {
            case .unreachable: "Couldn't reach GitHub. Check your connection and try again."
            case .notPomofocus: "The download didn't check out, so nothing was changed. Try again later."
            case .noPermission: "Pomofocus can't replace itself in this folder. Download the new version from the website instead."
            case .notSaved: "Your latest changes couldn't be saved, so Pomofocus didn't update. Nothing was changed."
            }
        }
    }
}

/// The "a new version is ready" sheet, also used for Check for Updates.
struct UpdateSheet: View {
    @Bindable var updater = Updater.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            switch updater.phase {
            case .available(let release):
                header("Pomofocus \(release.version) is ready", "You have \(updater.currentVersion). Your sessions, tasks and settings stay exactly as they are.")
                if !release.notes.isEmpty {
                    ScrollView {
                        Text(Self.markdown(release.notes))
                            .font(.system(size: 12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 220)
                    .padding(12)
                    .background(NonnaTheme.paper, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                buttons {
                    Button("Later") { updater.showsSheet = false }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("Update now") { Task { await updater.install(release) } }
                        .buttonStyle(NonnaButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            case .checking:
                header("Checking for updates…", nil)
                ProgressView().controlSize(.small)
            case .downloading, .installing:
                header(updater.phase == .downloading ? "Downloading…" : "Installing…", "Pomofocus will close and reopen on its own in a moment.")
                ProgressView().controlSize(.small)
            case .upToDate:
                header("You're up to date", "Pomofocus \(updater.currentVersion) is the newest version.")
                buttons { Spacer(); okButton }
            case .failed(let message):
                header("Update didn't work", message)
                buttons {
                    Button("Open download page") { NSWorkspace.shared.open(Updater.releasesPage) }
                        .buttonStyle(NonnaButtonStyle(prominent: false))
                    Spacer()
                    okButton
                }
            case .idle:
                EmptyView()
            }
        }
        .padding(28)
        .frame(width: 460, alignment: .leading)
        .background(NonnaTheme.cream)
        .foregroundStyle(NonnaTheme.ink)
        .preferredColorScheme(NonnaTheme.colorScheme)
        .interactiveDismissDisabled(updater.phase == .downloading || updater.phase == .installing)
    }

    private var okButton: some View {
        Button("OK") { updater.showsSheet = false }
            .buttonStyle(NonnaButtonStyle())
            .keyboardShortcut(.defaultAction)
    }

    private func header(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 22, weight: .regular, design: .serif))
            if let detail {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func buttons<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack { content() }
    }

    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

/// Settings card: current version, a check button, and the automatic-check switch.
struct UpdateSettingsCard: View {
    @Bindable var updater = Updater.shared
    @AppStorage(Updater.autoCheckKey) private var automatic = true

    var body: some View {
        SettingsCard(title: "Updates", icon: "arrow.down.circle") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're on version \(updater.currentVersion)")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Updating keeps all your sessions, tasks and settings.")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Button("What's new") { updater.showsWhatsNew = true }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                Button(updater.available == nil ? "Update Pomofocus" : "Update now") {
                    if updater.available != nil { updater.installAvailable() } else { Task { await updater.check(userInitiated: true) } }
                }
                    .buttonStyle(NonnaButtonStyle(prominent: false))
                    .disabled(updater.phase == .checking)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Check automatically")
                        .font(.system(size: 12, weight: .medium))
                    Text("Once a day, asks GitHub for the newest version number. Nothing about you is sent.")
                        .font(.system(size: 10))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                }
                Spacer()
                Toggle("Check automatically", isOn: $automatic)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            DisclosureGroup("Sound credits") {
                Text(AmbientSound.credits)
                    .font(.system(size: 10))
                    .foregroundStyle(NonnaTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, 4)
            }
            .font(.system(size: 11))
        }
    }
}


/// "Pomofocus 0.22.2 is ready", across the top of Settings, with Update now.
struct UpdateBanner: View {
    @Bindable var updater = Updater.shared

    var body: some View {
        if let release = updater.available {
            HStack(spacing: 14) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(NonnaTheme.terracotta)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Pomofocus \(release.version) is ready")
                        .font(.system(size: 14, weight: .semibold))
                    Text(Self.summary(release.notes))
                        .font(.system(size: 12))
                        .foregroundStyle(NonnaTheme.secondaryInk)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Button("What's in it") {
                    updater.showsSheet = true
                    updater.phase = .available(release)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(NonnaTheme.secondaryInk)
                Button("Update now") { updater.installAvailable() }
                    .buttonStyle(NonnaButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(NonnaTheme.raisedPaper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(NonnaTheme.terracotta.opacity(0.5), lineWidth: 1)
            }
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// The first plain sentence of the release notes, without markdown.
    static func summary(_ notes: String) -> String {
        let plain = notes.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "#", with: "")
        let line = plain.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty } ?? ""
        return line.isEmpty ? "Your sessions and settings stay as they are." : line
    }
}
