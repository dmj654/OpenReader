import Combine
import Foundation
import SwiftUI
import UIKit

/// 阅读页视图模型：桥接 SwiftUI 界面与 UIKit 翻页容器。
@MainActor
final class ReaderViewModel: ObservableObject {
    let book: Book
    let library: LibraryStore
    let settings: ReaderSettingsStore
    let engine: ReaderEngine

    @Published private(set) var location: ReaderLocation = .zero
    @Published var pendingJump: ReaderLocation?
    @Published var menuVisible = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var pageSize: CGSize = .zero
    @Published var sliderValue: Double = 0
    @Published var isSpeaking = false
    @Published var toastMessage: String?
    @Published var chaptersRevision = 0

    enum ActiveSheet: Identifiable {
        case chapterList
        case settings
        case bookmarks
        case search

        var id: Self { self }
    }

    @Published var activeSheet: ActiveSheet?

    private let tts = TTSController()
    private var cancellables = Set<AnyCancellable>()
    private var readingTimer: Timer?
    private var sessionSeconds: Double = 0

    init(book: Book, library: LibraryStore, settings: ReaderSettingsStore = .shared) {
        self.book = book
        self.library = library
        self.settings = settings
        self.engine = ReaderEngine(settings: settings, book: book)

        restoreProgress()
        sliderValue = currentPercent

        tts.onFinished = { [weak self] in
            self?.advanceSpeakingPage()
        }
        tts.onStateChanged = { [weak self] speaking in
            self?.isSpeaking = speaking
        }

        settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.engine.invalidateLayout()
                self.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - 主题

    var resolvedTheme: ReaderTheme {
        settings.theme
    }

    // MARK: - 进度

    private func restoreProgress() {
        if let saved = library.progress(for: book.id) {
            let chapter = max(0, min(saved.chapterIndex, max(0, engine.chapters.count - 1)))
            location = ReaderLocation(chapter: chapter, page: max(0, saved.pageIndex))
        } else {
            location = .zero
        }
    }

    var currentPercent: Double {
        if engine.chapters.isEmpty { return 0 }
        let offset = engine.characterOffset(pageIndex: location.page, inChapter: location.chapter)
        return engine.percent(chapter: location.chapter, characterOffset: offset)
    }

    var currentChapterTitle: String {
        engine.chapterTitle(at: location.chapter)
    }

    var locationDescription: String {
        guard !engine.chapters.isEmpty else { return "加载中…" }
        return "第 \(location.chapter + 1) / \(engine.chapters.count) 章"
    }

    func didPageTurn(to newLocation: ReaderLocation) {
        location = newLocation
        sliderValue = currentPercent
        saveProgress()
        Task { await prepareChapterIfNeeded(newLocation.chapter) }
    }

    private func saveProgress() {
        guard engine.chapters.indices.contains(location.chapter) else { return }
        let offset = engine.characterOffset(pageIndex: location.page, inChapter: location.chapter)
        let percent = engine.percent(chapter: location.chapter, characterOffset: offset)
        library.updateProgress(
            bookId: book.id,
            chapterIndex: location.chapter,
            pageIndex: location.page,
            characterOffset: offset,
            percent: percent
        )
    }

    // MARK: - 交互

    func handleTap(_ zone: ReaderTapZone) {
        if menuVisible {
            menuVisible = false
            return
        }
        guard settings.tappableTurnPage else {
            if zone == .center { menuVisible = true }
            return
        }
        switch zone {
        case .center:
            menuVisible = true
        case .leading:
            jump(to: engine.previousLocation(from: location))
        case .trailing:
            jump(to: engine.nextLocation(from: location))
        }
    }

    func pageForward() {
        jump(to: engine.nextLocation(from: location))
    }

    func pageBackward() {
        jump(to: engine.previousLocation(from: location))
    }

    func jump(toChapter index: Int) {
        guard engine.chapters.indices.contains(index) else { return }
        jump(to: ReaderLocation(chapter: index, page: 0))
    }

    func jump(toCharacterOffset offset: Int, inChapter index: Int) {
        guard engine.chapters.indices.contains(index) else { return }
        jump(to: engine.location(chapter: index, characterOffset: offset))
    }

    private func jump(to target: ReaderLocation?) {
        guard let target else {
            showToast("已经是最后一页了")
            return
        }
        menuVisible = false
        pendingJump = target
    }

    /// 进度条拖动结束
    func commitSlider() {
        guard let target = engine.chapterAndOffset(forPercent: sliderValue) else { return }
        jump(to: engine.location(chapter: target.chapter, characterOffset: target.offset))
    }

    func toggleNightMode() {
        let isDark = settings.theme.isDark
        settings.themeIndex = isDark ? 1 : 5
        Haptics.light()
    }

    func updatePageSize(_ size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        guard size != pageSize else { return }
        pageSize = size
        engine.updatePageSize(size)
        objectWillChange.send()
    }

    func showToast(_ message: String) {
        toastMessage = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            if self?.toastMessage == message {
                self?.toastMessage = nil
            }
        }
    }

    // MARK: - 书签

    var isBookmarkedHere: Bool {
        let offset = engine.characterOffset(pageIndex: location.page, inChapter: location.chapter)
        return library.bookmarks(for: book.id).contains {
            $0.chapterIndex == location.chapter && $0.characterOffset == offset && $0.kind == .bookmark
        }
    }

    func toggleBookmark() {
        let offset = engine.characterOffset(pageIndex: location.page, inChapter: location.chapter)
        let existing = library.bookmarks(for: book.id).first {
            $0.chapterIndex == location.chapter && $0.characterOffset == offset && $0.kind == .bookmark
        }
        if let existing {
            library.removeBookmark(existing)
            showToast("已移除书签")
        } else {
            let snippet = pageSnippet()
            library.addBookmark(
                Bookmark(
                    bookId: book.id,
                    chapterIndex: location.chapter,
                    characterOffset: offset,
                    text: snippet,
                    kind: .bookmark
                )
            )
            Haptics.success()
            showToast("已添加书签")
        }
        objectWillChange.send()
    }

    private func pageSnippet() -> String {
        guard let range = engine.pageCharacterRange(at: location),
              let chapter = engine.chapters[safe: location.chapter] else { return "" }
        if chapter.isHTML {
            let plain = EpubParser.stripTags(chapter.content)
            let start = min(range.location, plain.count)
            let length = min(range.length, plain.count - start)
            let startIdx = plain.index(plain.startIndex, offsetBy: start)
            let endIdx = plain.index(startIdx, offsetBy: length)
            return String(plain[startIdx..<endIdx]).condensedWhitespace.truncating(to: 80)
        }
        let startIdx = chapter.content.index(chapter.content.startIndex, offsetBy: min(range.location, chapter.content.count))
        let endIdx = chapter.content.index(startIdx, offsetBy: min(range.length, chapter.content.count - min(range.location, chapter.content.count)))
        return String(chapter.content[startIdx..<endIdx]).condensedWhitespace.truncating(to: 80)
    }

    // MARK: - 朗读

    func toggleSpeech() {
        if isSpeaking {
            tts.stop()
            isSpeaking = false
        } else {
            startSpeaking()
        }
    }

    private func startSpeaking() {
        guard let text = engine.plainText(from: location) else {
            showToast("当前页没有可朗读的内容")
            return
        }
        tts.speak(
            text: text,
            rate: Float(settings.speechRate) * 0.6 + 0.35,
            pitch: Float(settings.speechPitch)
        )
    }

    private func advanceSpeakingPage() {
        guard isSpeaking || tts.isActive else { return }
        guard let next = engine.nextLocation(from: location) else {
            showToast("已读完最后一页")
            return
        }
        location = next
        sliderValue = currentPercent
        saveProgress()
        if let text = engine.plainText(from: next) {
            tts.speak(
                text: text,
                rate: Float(settings.speechRate) * 0.6 + 0.35,
                pitch: Float(settings.speechPitch)
            )
        }
    }

    func stopSpeakingIfNeeded() {
        tts.stop()
    }

    // MARK: - 在线书籍

    func prepareChapterIfNeeded(_ index: Int) async {
        guard book.format == .online, engine.chapters.indices.contains(index) else { return }
        let chapter = engine.chapters[index]
        guard chapter.content.isEmpty, let url = chapter.url else { return }
        guard let sourceId = book.sourceId, let source = library.source(withId: sourceId) else { return }

        do {
            let content = try await BookSourceEngine.fetchContent(source: source, chapterURL: url)
            let updated = Chapter(
                title: chapter.title,
                content: content,
                isHTML: false,
                characterCount: content.count,
                url: chapter.url
            )
            engine.updateChapter(updated, at: index)
            chaptersRevision += 1
        } catch {
            showToast("加载章节失败：" + error.localizedDescription)
        }
    }

    func loadOnlineTOCIfNeeded() async {
        guard book.format == .online, engine.chapters.isEmpty else { return }
        guard let sourceId = book.sourceId,
              let source = library.source(withId: sourceId),
              let bookURL = book.remoteURL else { return }

        isLoading = true
        defer { isLoading = false }
        do {
            let chapters = try await BookSourceEngine.fetchTOC(source: source, bookURL: bookURL)
            engine.replaceChapters(chapters)
            chaptersRevision += 1
            BookImporter.persistChapters(chapters, for: book.id)
            restoreProgress()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 阅读时长

    func startReadingSession() {
        sessionSeconds = 0
        readingTimer?.invalidate()
        readingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.sessionSeconds += 5
            }
        }
        Task { await loadOnlineTOCIfNeeded() }
        Task { await prepareChapterIfNeeded(location.chapter) }
    }

    func endReadingSession() {
        readingTimer?.invalidate()
        readingTimer = nil
        library.addReadingTime(bookId: book.id, seconds: sessionSeconds)
        saveProgress()
        tts.stop()
    }
}
