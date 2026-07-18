import AppKit
import Combine

struct QuickNote: Identifiable, Codable, Equatable {
    let id: UUID
    var text: String
    var date: Date
}

struct Bookmark: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var urlString: String

    var url: URL? { URL(string: urlString) }
}

/// Quick notes and saved links, both living in the notch.
@MainActor
final class NotesStore: ObservableObject {
    @Published var notes: [QuickNote] = [] { didSet { persistNotes() } }
    @Published var bookmarks: [Bookmark] = [] { didSet { persistBookmarks() } }

    private var loading = true

    init() {
        notes = Persistence.load([QuickNote].self, from: "notes.json") ?? []
        bookmarks = Persistence.load([Bookmark].self, from: "bookmarks.json") ?? []
        loading = false
    }

    func addNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        notes.insert(QuickNote(id: UUID(), text: trimmed, date: Date()), at: 0)
    }

    func removeNote(_ note: QuickNote) {
        notes.removeAll { $0.id == note.id }
    }

    func updateNote(_ note: QuickNote, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == note.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            notes.remove(at: index)
        } else {
            notes[index].text = trimmed
        }
    }

    func addBookmark(title: String, urlString: String) {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            normalized = "https://" + normalized
        }
        guard URL(string: normalized) != nil else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        bookmarks.insert(
            Bookmark(id: UUID(), title: name.isEmpty ? normalized : name, urlString: normalized),
            at: 0
        )
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
    }

    func open(_ bookmark: Bookmark) {
        guard let url = bookmark.url else { return }
        NSWorkspace.shared.open(url)
    }

    private func persistNotes() {
        guard !loading else { return }
        Persistence.save(notes, to: "notes.json")
    }

    private func persistBookmarks() {
        guard !loading else { return }
        Persistence.save(bookmarks, to: "bookmarks.json")
    }
}
