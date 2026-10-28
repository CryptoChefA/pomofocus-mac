import Foundation

/// Something already timed that could become a task: a name typed into "What are you
/// working on?", or a list from before Tasks existed. Offered once, after updating.
struct WorkSuggestion: Identifiable, Equatable, Sendable {
    enum Source: Equatable, Sendable { case workedOn, list }

    let title: String
    let listID: UUID?
    let source: Source
    /// Focus blocks that used this name; 0 for a list.
    let blocks: Int
    let lastUsed: Date?
    /// Ticked to begin with: lists, and up to five pieces of work used more than once in the
    /// last two weeks. A one-off like "Clean room", or something long finished, is shown
    /// but left unticked, so the first look at Tasks isn't another long list.
    var startsPicked: Bool

    var id: String { "\(source)-\(WorkImport.key(title))" }
}

enum WorkImport {
    static let offeredKey = "workImportOffered"

    /// "Business law", "BUSINESS LAW " and "Business  Law" are the same piece of work.
    static func key(_ title: String) -> String {
        tidy(title).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func tidy(_ title: String) -> String {
        title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static let recent: TimeInterval = 14 * 86_400
    static let pickedLimit = 5

    /// Newest work first, then the lists. Anything already in Tasks is left out.
    static func suggestions(sessions: [FocusSession], lists: [FocusTask], todos: [TodoItem], now: Date = Date()) -> [WorkSuggestion] {
        let inTasks = Set(todos.map { key($0.title) })
        let open = lists.filter { !$0.isArchived }
        let openLists = Set(open.map(\.id))
        // A block's list by its id, or by name if the list was made again since.
        func list(of block: FocusSession) -> UUID? {
            if let id = block.taskID, openLists.contains(id) { return id }
            return open.first { key($0.name) == key(block.taskName) }?.id
        }
        let named = Dictionary(grouping: sessions.filter { $0.focusedSeconds > 0 && !key($0.intention).isEmpty }) { key($0.intention) }

        var worked = named.compactMap { name, parts -> WorkSuggestion? in
            guard !inTasks.contains(name) else { return nil }
            // The spelling used most, the newest one on a tie.
            let spellings = Dictionary(grouping: parts) { tidy($0.intention) }
            let title = spellings.max { a, b in
                (a.value.count, a.value.map(\.startedAt).max()!) < (b.value.count, b.value.map(\.startedAt).max()!)
            }!.key
            // Filed under the list it got the most time in, if that list is still around.
            let timeByList = Dictionary(grouping: parts.compactMap { part in list(of: part).map { ($0, part.focusedSeconds) } }) { $0.0 }
                .mapValues { $0.reduce(0) { $0 + $1.1 } }
            let listID = timeByList.max { ($0.value, $0.key.uuidString) < ($1.value, $1.key.uuidString) }?.key
            // A block split across lists is several records with one blockID; count it once.
            let blocks = Set(parts.map { $0.blockID ?? $0.id }).count
            let lastUsed = parts.map(\.startedAt).max()!
            return WorkSuggestion(title: title, listID: listID, source: .workedOn, blocks: blocks, lastUsed: lastUsed,
                                  startsPicked: blocks > 1 && now.timeIntervalSince(lastUsed) < recent)
        }
        .sorted { ($0.lastUsed ?? .distantPast, $0.blocks) > ($1.lastUsed ?? .distantPast, $1.blocks) }
        for index in worked.indices.filter({ worked[$0].startsPicked }).dropFirst(pickedLimit) {
            worked[index].startsPicked = false
        }

        let taken = inTasks.union(worked.map { key($0.title) })
        let fromLists = lists.filter { !$0.isArchived && !taken.contains(key($0.name)) && !key($0.name).isEmpty }
            .map { WorkSuggestion(title: $0.name, listID: $0.id, source: .list, blocks: 0, lastUsed: nil, startsPicked: true) }
        return worked + fromLists
    }
}
