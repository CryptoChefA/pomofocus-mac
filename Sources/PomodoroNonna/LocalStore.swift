import Foundation

actor LocalStore {
    static let shared = LocalStore()

    private let fileManager: FileManager
    private let customURL: URL?

    init(fileManager: FileManager = .default, customURL: URL? = nil) {
        self.fileManager = fileManager
        self.customURL = customURL
    }

    private var folderURL: URL {
        get throws {
            if let customURL { return customURL.deletingLastPathComponent() }
            let support = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let folder = support.appendingPathComponent("Pomofocus", isDirectory: true)
            let legacyFolder = support.appendingPathComponent("Pomodoro Nonna", isDirectory: true)
            if !fileManager.fileExists(atPath: folder.path),
               fileManager.fileExists(atPath: legacyFolder.path) {
                try fileManager.moveItem(at: legacyFolder, to: folder)
            }
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    private var dataURL: URL {
        get throws {
            if let customURL { return customURL }
            let folder = try folderURL
            let url = folder.appendingPathComponent("pomofocus-data.json")
            let legacyURL = folder.appendingPathComponent("nonna-data.json")
            if !fileManager.fileExists(atPath: url.path),
               fileManager.fileExists(atPath: legacyURL.path) {
                try fileManager.moveItem(at: legacyURL, to: url)
            }
            return url
        }
    }

    private var attachmentsURL: URL {
        get throws {
            let folder = try folderURL.appendingPathComponent("Images", isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
    }

    func load() throws -> AppData {
        let url = try dataURL
        guard fileManager.fileExists(atPath: url.path) else { return .starter }
        let data = try Data(contentsOf: url)
        return try JSONDecoder.nonna.decode(AppData.self, from: data)
    }

    func save(_ appData: AppData) throws {
        let url = try dataURL
        let encoded = try JSONEncoder.nonna.encode(appData)
        try encoded.write(to: url, options: [.atomic])
    }

    func url() throws -> URL { try dataURL }

    func saveImage(_ data: Data, named fileName: String) throws {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        try data.write(to: attachmentsURL.appendingPathComponent(fileName), options: [.atomic])
    }

    func deleteImage(named fileName: String) throws {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent else { return }
        let url = try attachmentsURL.appendingPathComponent(fileName)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    nonisolated static func attachmentURL(for fileName: String) -> URL? {
        guard fileName == URL(fileURLWithPath: fileName).lastPathComponent,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let current = support
            .appendingPathComponent("Pomofocus", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: current.path) { return current }
        return support
            .appendingPathComponent("Pomodoro Nonna", isDirectory: true)
            .appendingPathComponent("Images", isDirectory: true)
            .appendingPathComponent(fileName)
    }
}

private extension JSONEncoder {
    static var nonna: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}

private extension JSONDecoder {
    static var nonna: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
