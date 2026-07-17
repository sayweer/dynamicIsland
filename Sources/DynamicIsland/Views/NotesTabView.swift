import SwiftUI

/// Quick notes on the left, saved links on the right.
struct NotesTabView: View {
    @EnvironmentObject private var notes: NotesStore
    @EnvironmentObject private var browser: BrowserModel
    @EnvironmentObject private var vm: NotchViewModel

    @State private var newNote = ""
    @State private var newBookmark = ""

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            notesColumn
            Divider().overlay(Color.white.opacity(0.1))
            bookmarksColumn
        }
        .islandCard()
    }

    private var notesColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Hızlı Notlar", symbol: "note.text", tint: .yellow)
            HStack(spacing: 6) {
                TextField("Not yaz ve Enter'a bas…", text: $newNote)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                    .onSubmit(addNote)
                Button(action: addNote) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(IslandButtonStyle())
            }
            if notes.notes.isEmpty {
                Text("Aklınızdakini hemen buraya bırakın.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(notes.notes) { note in
                            HStack(alignment: .top, spacing: 6) {
                                Text(note.text)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(3)
                                    .textSelection(.enabled)
                                Spacer(minLength: 4)
                                Button {
                                    withAnimation(Motion.standard) { notes.removeNote(note) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                .buttonStyle(IslandButtonStyle())
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.yellow.opacity(0.08))
                            )
                            .transition(.opacity)
                        }
                    }
                    .animation(Motion.standard, value: notes.notes.count)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bookmarksColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            CardTitle("Yer İmleri", symbol: "bookmark.fill", tint: .blue)
            HStack(spacing: 6) {
                TextField("Bağlantı yapıştır…", text: $newBookmark)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.07)))
                    .onSubmit(addBookmark)
                Button(action: addBookmark) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(IslandButtonStyle())
            }
            if notes.bookmarks.isEmpty {
                Text("Sık kullandığınız bağlantıları kaydedin.")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(notes.bookmarks) { bookmark in
                            HStack(spacing: 6) {
                                Image(systemName: "link")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.blue)
                                Text(bookmark.title)
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 4)
                                Button {
                                    withAnimation(Motion.standard) { notes.removeBookmark(bookmark) }
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                .buttonStyle(IslandButtonStyle())
                            }
                            .padding(7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.blue.opacity(0.08))
                            )
                            .contentShape(RoundedRectangle(cornerRadius: 8))
                            .transition(.opacity)
                            .onTapGesture { notes.open(bookmark) }
                            .contextMenu {
                                Button("Varsayılan Tarayıcıda Aç") { notes.open(bookmark) }
                                Button("Island Tarayıcısında Aç") {
                                    browser.load(bookmark.urlString)
                                    vm.activeTab = .browser
                                }
                                Divider()
                                Button("Sil") { notes.removeBookmark(bookmark) }
                            }
                        }
                    }
                    .animation(Motion.standard, value: notes.bookmarks.count)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addNote() {
        notes.addNote(newNote)
        newNote = ""
    }

    private func addBookmark() {
        notes.addBookmark(title: "", urlString: newBookmark)
        newBookmark = ""
    }
}
