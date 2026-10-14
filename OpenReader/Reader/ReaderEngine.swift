import Foundation
import UIKit

/// 阅读内核：章节内容 → 排版字符串 → 分页。
///
/// 颜色不写入排版字符串（绘制时由页面视图统一设置前景色），
/// 因此切换主题 / 夜间模式是零成本的，不会触发重新分页。
@MainActor
final class ReaderEngine: ObservableObject {
    let settings: ReaderSettingsStore

    @Published private(set) var chapters: [Chapter] = []

    /// 当前页面渲染尺寸（整页，含边距前）
    private(set) var pageSize: CGSize = .zero

    private var attributedCache = NSCache<NSNumber, NSAttributedString>()
    private var pageRanges: [Int: [NSRange]] = [:]
    private var layoutSignature: String = ""
    private var imagesDirectory: URL?
    private var isOnlineBook = false

    init(settings: ReaderSettingsStore, book: Book) {
        self.settings = settings
        imagesDirectory = book.format == .epub ? FileStore.imagesDirectory(for: book.id) : nil
        isOnlineBook = book.format == .online
        attributedCache.countLimit = 10
        loadPersistedChapters(for: book)
    }

    // MARK: - 章节数据

    func replaceChapters(_ newChapters: [Chapter]) {
        chapters = newChapters
        pageRanges.removeAll()
        attributedCache.removeAllObjects()
    }

    func updateChapter(_ chapter: Chapter, at index: Int) {
        guard chapters.indices.contains(index) else { return }
        chapters[index] = chapter
        pageRanges.removeValue(forKey: index)
        attributedCache.removeObject(forKey: NSNumber(value: index))
    }

    private func loadPersistedChapters(for book: Book) {
        if let stored = FileStore.readJSON([Chapter].self, from: FileStore.chaptersFile(for: book.id)),
           !stored.isEmpty {
            chapters = stored
            return
        }

        guard book.isLocal else { return }

        let url = FileStore.bookURL(for: book)
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        switch book.format {
        case .txt:
            if let data = try? Data(contentsOf: url, options: [.mappedIfSafe]) {
                let detected = EncodingDetector.detect(in: data)
                if let text = String(data: data, encoding: detected.encoding) {
                    let cleaned = text
                        .replacingOccurrences(of: "\u{FEFF}", with: "")
                        .replacingOccurrences(of: "\r\n", with: "\n")
                        .replacingOccurrences(of: "\r", with: "\n")
                    chapters = ChapterSplitter.split(cleaned).map {
                        Chapter.plain(title: $0.title.isEmpty ? "正文" : $0.title, content: $0.content)
                    }
                }
            }
        case .epub:
            if let parsed = try? EpubParser.parse(
                at: url,
                imagesDirectory: FileStore.imagesDirectory(for: book.id)
            ) {
                chapters = parsed.chapters
                BookImporter.persistChapters(parsed.chapters, for: book.id)
            }
        case .online:
            break
        }
    }

    // MARK: - 统计

    var totalCharacterCount: Int {
        chapters.reduce(0) { $0 + $1.characterCount }
    }

    func cumulativeOffsets() -> [Int] {
        var offsets: [Int] = []
        offsets.reserveCapacity(chapters.count + 1)
        var running = 0
        offsets.append(0)
        for chapter in chapters {
            running += chapter.characterCount
            offsets.append(running)
        }
        return offsets
    }

    func percent(chapter: Int, characterOffset: Int) -> Double {
        let offsets = cumulativeOffsets()
        guard chapters.indices.contains(chapter) else { return 0 }
        let base = offsets[chapter]
        let chapterLength = max(1, chapters[chapter].characterCount)
        let current = base + max(0, min(characterOffset, chapterLength))
        let total = max(1, offsets.last ?? 1)
        return min(1.0, Double(current) / Double(total))
    }

    /// 按百分比定位到章节 + 字符偏移（进度滑条拖动）
    func chapterAndOffset(forPercent percent: Double) -> (chapter: Int, offset: Int)? {
        let offsets = cumulativeOffsets()
        let total = offsets.last ?? 0
        guard total > 0, !chapters.isEmpty else { return nil }
        let target = max(0, min(Int(Double(total) * percent), total - 1))

        for index in 0..<chapters.count {
            let start = offsets[index]
            let end = offsets[index + 1]
            if target >= start, target < end {
                let chapterLength = max(1, chapters[index].characterCount)
                let offset = max(0, min(target - start, chapterLength - 1))
                return (index, offset)
            }
        }
        return (chapters.count - 1, 0)
    }

    // MARK: - 排版

    func updatePageSize(_ size: CGSize) {
        guard size.width > 10, size.height > 10 else { return }
        guard size != pageSize else { return }
        pageSize = size
        layoutSignature = ""
        pageRanges.removeAll()
    }

    private var currentLayoutSignature: String {
        [
            "\(Int(settings.fontSize))",
            String(format: "%.1f", settings.lineSpacing),
            String(format: "%.1f", settings.paragraphSpacing),
            "\(Int(settings.horizontalMargin))",
            "\(Int(settings.verticalMargin))",
            settings.firstLineIndent ? "i" : "n",
            settings.fontFamily,
            "\(Int(pageSize.width))x\(Int(pageSize.height))",
        ].joined(separator: "|")
    }

    /// 排版字符串（不含颜色）
    func attributedString(chapter index: Int) -> NSAttributedString? {
        guard chapters.indices.contains(index) else { return nil }
        if let cached = attributedCache.object(forKey: NSNumber(value: index)) {
            return cached
        }

        let chapter = chapters[index]
        let attributed: NSAttributedString
        if chapter.isHTML {
            attributed = attributedFromHTML(chapter.content)
        } else {
            attributed = attributedFromPlainText(chapter.content)
        }

        attributedCache.setObject(attributed, forKey: NSNumber(value: index))
        return attributed
    }

    private func attributedFromPlainText(_ content: String) -> NSAttributedString {
        let font = settings.uiFont(ofSize: CGFloat(settings.fontSize))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = CGFloat(settings.lineSpacing)
        paragraph.paragraphSpacing = CGFloat(settings.paragraphSpacing)
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byWordWrapping
        if settings.firstLineIndent {
            paragraph.firstLineHeadIndent = CGFloat(settings.fontSize) * 2
            paragraph.headIndent = 0
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
        ]

        let output = NSMutableAttributedString()
        let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmed
            if trimmed.isEmpty {
                output.append(NSAttributedString(string: "\n", attributes: attributes))
            } else {
                output.append(NSAttributedString(string: trimmed + "\n", attributes: attributes))
            }
        }
        return output
    }

    private func attributedFromHTML(_ html: String) -> NSAttributedString {
        let inlined = inlineImages(in: html)
        let wrapped = "<html><head><meta charset='utf-8'></head><body>" + inlined + "</body></html>"
        guard let data = wrapped.data(using: .utf8) else { return NSAttributedString() }

        var documentAttributes: NSDictionary?
        let converted: NSMutableAttributedString
        do {
            converted = try NSMutableAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: &documentAttributes
            )
        } catch {
            let plain = EpubParser.stripTags(html)
            return attributedFromPlainText(plain)
        }

        applyTypography(to: converted)
        return converted
    }

    /// 把磁盘上的图片替换成 data URI，保证 HTML 导入器一定能加载
    private func inlineImages(in html: String) -> String {
        guard let directory = imagesDirectory,
              let regex = try? NSRegularExpression(
                  pattern: "(?i)(src|xlink:href)\\s*=\\s*\"([^\"]*)\""
              ) else { return html }

        let mutable = NSMutableString(string: html)
        let matches = regex
            .matches(in: html, range: NSRange(html.startIndex..., in: html))
            .reversed()

        for match in matches {
            guard let valueRange = Range(match.range(at: 2), in: html) else { continue }
            let value = String(html[valueRange])
            if value.lowercased().hasPrefix("data:") { continue }
            let sanitized = (value.removingPercentEncoding ?? value)
                .replacingOccurrences(of: "/", with: "_")
            let url = directory.appendingPathComponent(sanitized)
            guard let data = try? Data(contentsOf: url), data.count < 4_000_000 else { continue }
            let mime = Self.mimeType(forExtension: url.pathExtension.lowercased())
            mutable.replaceCharacters(
                in: match.range(at: 2),
                with: "data:\(mime);base64," + data.base64EncodedString()
            )
        }
        return mutable as String
    }

    private static func mimeType(forExtension ext: String) -> String {
        switch ext {
        case "png": return "image/png"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "bmp": return "image/bmp"
        case "svg": return "image/svg+xml"
        default: return "image/jpeg"
        }
    }

    private func applyTypography(to attributed: NSMutableAttributedString) {
        let base = CGFloat(settings.fontSize)
        let reference: CGFloat = 12
        let fullRange = NSRange(location: 0, length: attributed.length)

        attributed.enumerateAttribute(.font, in: fullRange, options: []) { value, range, _ in
            guard let original = value as? UIFont else { return }
            let scaled = max(base * 0.7, min(base * 2.4, original.pointSize / reference * base))
            var font = settings.uiFont(ofSize: scaled)
            let traits = original.fontDescriptor.symbolicTraits
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                font = UIFont(descriptor: descriptor, size: scaled)
            }
            attributed.addAttribute(.font, value: font, range: range)
        }

        // 抹掉 HTML 自带颜色，让主题接管
        attributed.enumerateAttribute(.foregroundColor, in: fullRange, options: []) { value, range, _ in
            if value != nil {
                attributed.removeAttribute(.foregroundColor, range: range)
            }
        }

        attributed.enumerateAttribute(.paragraphStyle, in: fullRange, options: []) { value, range, _ in
            let existing = (value as? NSParagraphStyle) ?? NSParagraphStyle.default
            let paragraph = NSMutableParagraphStyle()
            paragraph.setParagraphStyle(existing)
            paragraph.lineSpacing = CGFloat(settings.lineSpacing)
            paragraph.paragraphSpacing = CGFloat(settings.paragraphSpacing)
            paragraph.alignment = .justified
            if settings.firstLineIndent {
                let bodyIndent = CGFloat(settings.fontSize) * 2
                let isBody = (existing.minimumLineHeight == 0)
                paragraph.firstLineHeadIndent = isBody ? bodyIndent : existing.firstLineHeadIndent
            }
            attributed.addAttribute(.paragraphStyle, value: paragraph, range: range)
        }
    }

    // MARK: - 分页

    func pageCount(chapter index: Int) -> Int {
        ranges(forChapter: index).count
    }

    func ranges(forChapter index: Int) -> [NSRange] {
        guard chapters.indices.contains(index) else { return [] }

        let signature = currentLayoutSignature
        if signature != layoutSignature {
            layoutSignature = signature
            pageRanges.removeAll()
        }
        if let cached = pageRanges[index] {
            return cached
        }

        guard let text = attributedString(chapter: index) else { return [] }
        let computed = PaginationEngine.pageRanges(
            text: text,
            pageSize: pageSize,
            insets: settings.textInsets
        )
        pageRanges[index] = computed
        return computed
    }

    func pageContaining(characterOffset: Int, inChapter index: Int) -> Int {
        PaginationEngine.pageContaining(characterOffset: characterOffset, ranges: ranges(forChapter: index))
    }

    func characterOffset(pageIndex: Int, inChapter index: Int) -> Int {
        PaginationEngine.characterOffset(pageIndex: pageIndex, ranges: ranges(forChapter: index))
    }

    /// 跳转到某章的某个字符位置（目录 / 搜索 / 书签共用）
    func location(chapter: Int, characterOffset: Int) -> ReaderLocation {
        let page = pageContaining(characterOffset: characterOffset, inChapter: chapter)
        return ReaderLocation(chapter: chapter, page: page)
    }

    // MARK: - 章节辅助

    func chapterTitle(at index: Int) -> String {
        guard chapters.indices.contains(index) else { return "" }
        return chapters[index].title
    }

    func nextLocation(from location: ReaderLocation) -> ReaderLocation? {
        if location.page + 1 < pageCount(chapter: location.chapter) {
            return ReaderLocation(chapter: location.chapter, page: location.page + 1)
        }
        var chapter = location.chapter + 1
        while chapter < chapters.count {
            if pageCount(chapter: chapter) > 0 {
                return ReaderLocation(chapter: chapter, page: 0)
            }
            chapter += 1
        }
        return nil
    }

    func previousLocation(from location: ReaderLocation) -> ReaderLocation? {
        if location.page > 0 {
            return ReaderLocation(chapter: location.chapter, page: location.page - 1)
        }
        var chapter = location.chapter - 1
        while chapter >= 0 {
            let count = pageCount(chapter: chapter)
            if count > 0 {
                return ReaderLocation(chapter: chapter, page: count - 1)
            }
            chapter -= 1
        }
        return nil
    }

    /// 排版参数变化后调用：清空分页缓存，让页面在下次渲染时重算
    func invalidateLayout() {
        pageRanges.removeAll()
    }

    /// 当前页起止字符
    func pageCharacterRange(at location: ReaderLocation) -> NSRange? {
        let ranges = ranges(forChapter: location.chapter)
        guard ranges.indices.contains(location.page) else { return nil }
        return ranges[location.page]
    }

    /// 用于朗读的纯文本（当前页起）
    func plainText(from location: ReaderLocation, maxCharacters: Int = 6000) -> String? {
        guard let chapter = chapters[safe: location.chapter] else { return nil }
        if chapter.isHTML {
            let plain = EpubParser.stripTags(chapter.content)
            let ranges = ranges(forChapter: location.chapter)
            guard ranges.indices.contains(location.page) else { return plain }
            let start = min(ranges[location.page].location, plain.count)
            let end = min(plain.count, start + maxCharacters)
            let startIdx = plain.index(plain.startIndex, offsetBy: start)
            let endIdx = plain.index(plain.startIndex, offsetBy: end)
            return String(plain[startIdx..<endIdx])
        }
        return String(chapter.content.prefix(maxCharacters))
    }
}

// MARK: - 安全下标

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
