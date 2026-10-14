import Combine
import Foundation

/// 书架总仓库：书籍索引、书源、书签、阅读进度的唯一事实来源。
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    @Published private(set) var sources: [BookSource] = []
    @Published private(set) var bookmarks: [Bookmark] = []
    @Published private(set) var progress: [String: ReadingProgress] = [:]

    private let defaults = UserDefaults.standard

    // MARK: - 生命周期

    init() {
        load()
    }

    func load() {
        books = FileStore.readJSON([Book].self, from: FileStore.libraryFile) ?? []
        sources = FileStore.readJSON([BookSource].self, from: FileStore.sourcesFile) ?? []
        bookmarks = FileStore.readJSON([Bookmark].self, from: FileStore.bookmarksFile) ?? []
        progress = FileStore.readJSON([String: ReadingProgress].self, from: FileStore.progressFile) ?? [:]
        books.sort()
    }

    private func persist() {
        try? FileStore.writeJSON(books, to: FileStore.libraryFile)
    }

    private func persistSources() {
        try? FileStore.writeJSON(sources, to: FileStore.sourcesFile)
    }

    private func persistBookmarks() {
        try? FileStore.writeJSON(bookmarks, to: FileStore.bookmarksFile)
    }

    private func persistProgress() {
        try? FileStore.writeJSON(progress, to: FileStore.progressFile)
    }

    // MARK: - 书籍

    func book(withId id: UUID) -> Book? {
        books.first { $0.id == id }
    }

    func upsert(_ book: Book) {
        if let index = books.firstIndex(where: { $0.id == book.id }) {
            books[index] = book
        } else {
            books.append(book)
        }
        books.sort()
        persist()
    }

    func remove(_ book: Book) {
        books.removeAll { $0.id == book.id }
        progress.removeValue(forKey: book.id.uuidString)
        bookmarks.removeAll { $0.bookId == book.id }
        FileStore.removeBookArtifacts(for: book.id)
        if !book.fileName.isEmpty {
            try? FileManager.default.removeItem(at: FileStore.booksDirectory.appendingPathComponent(book.fileName))
        }
        persist()
        persistBookmarks()
        persistProgress()
    }

    func setPinned(_ book: Book, pinned: Bool) {
        var copy = book
        copy.isPinned = pinned
        upsert(copy)
    }

    func move(_ book: Book, toGroup group: String) {
        var copy = book
        copy.group = group
        upsert(copy)
    }

    var groups: [String] {
        var set = Set(books.map(\.group))
        set.insert("默认")
        return set.sorted()
    }

    // MARK: - 进度

    func progress(for bookId: UUID) -> ReadingProgress? {
        progress[bookId.uuidString]
    }

    func updateProgress(bookId: UUID, chapterIndex: Int, pageIndex: Int, characterOffset: Int, percent: Double) {
        let key = bookId.uuidString
        var entry = progress[key] ?? ReadingProgress()
        entry.chapterIndex = chapterIndex
        entry.pageIndex = pageIndex
        entry.characterOffset = characterOffset
        entry.percent = percent
        entry.updatedAt = Date()
        progress[key] = entry

        if let index = books.firstIndex(where: { $0.id == bookId }) {
            books[index].lastReadAt = Date()
        }
        persistProgress()
        persist()
    }

    func addReadingTime(bookId: UUID, seconds: Double) {
        guard seconds > 0 else { return }
        let key = bookId.uuidString
        var entry = progress[key] ?? ReadingProgress()
        entry.totalReadingSeconds += seconds
        progress[key] = entry
        persistProgress()
    }

    // MARK: - 书签

    func bookmarks(for bookId: UUID) -> [Bookmark] {
        bookmarks
            .filter { $0.bookId == bookId }
            .sorted { lhs, rhs in
                if lhs.chapterIndex != rhs.chapterIndex { return lhs.chapterIndex < rhs.chapterIndex }
                return lhs.characterOffset < rhs.characterOffset
            }
    }

    @discardableResult
    func addBookmark(_ bookmark: Bookmark) {
        guard !bookmarks.contains(where: {
            $0.bookId == bookmark.bookId &&
                $0.chapterIndex == bookmark.chapterIndex &&
                $0.characterOffset == bookmark.characterOffset &&
                $0.kind == bookmark.kind
        }) else { return }
        bookmarks.append(bookmark)
        persistBookmarks()
    }    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        persistBookmarks()
    }

    // MARK: - 书源

    func source(withId id: UUID) -> BookSource? {
        sources.first { $0.id == id }
    }

    var enabledSources: [BookSource] {
        sources.filter(\.enabled)
    }

    func replaceSources(_ incoming: [BookSource]) {
        var merged = sources
        for source in incoming {
            if let index = merged.firstIndex(where: { $0.sourceURL == source.sourceURL }) {
                var updated = source
                updated.id = merged[index].id
                updated.enabled = merged[index].enabled
                merged[index] = updated
            } else {
                merged.append(source)
            }
        }
        merged.sort { $0.sourceName < $1.sourceName }
        sources = merged
        persistSources()
    }

    func toggleSource(_ source: BookSource) {
        guard let index = sources.firstIndex(where: { $0.id == source.id }) else { return }
        sources[index].enabled.toggle()
        persistSources()
    }

    func removeSource(_ source: BookSource) {
        sources.removeAll { $0.id == source.id }
        persistSources()
    }
}

// MARK: - 排序

extension Book: Comparable {
    static func < (lhs: Book, rhs: Book) -> Bool {
        if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
        let l = lhs.lastReadAt ?? .distantPast
        let r = rhs.lastReadAt ?? .distantPast
        if l != r { return l > r }
        return lhs.addedAt > rhs.addedAt
    }
}

extension Book {
    var lastReadDescription: String {
        guard let date = lastReadAt else { return "未读" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .abbreviated
        return "上次阅读 " + formatter.localizedString(for: date, relativeTo: Date())
    }
}
