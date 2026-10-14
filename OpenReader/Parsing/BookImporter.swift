import SwiftUI
import UIKit

/// 把一个外部文件变成书架里的一本书。
enum BookImporter {
    static func importBook(at sourceURL: URL) async throws -> Book {
        let bookId = UUID()
        let ext = sourceURL.pathExtension.lowercased()

        let format: BookFormat
        switch ext {
        case "txt", "text": format = .txt
        case "epub": format = .epub
        default: throw BookParseError.unsupportedFormat
        }

        // 1. 复制到 Books/
        let fileName = bookId.uuidString + "." + ext
        let destination = FileStore.booksDirectory.appendingPathComponent(fileName)

        let copied: Bool
        if sourceURL.startAccessingSecurityScopedResource() {
            defer { sourceURL.stopAccessingSecurityScopedResource() }
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                copied = true
            } catch {
                copied = false
            }
        } else {
            do {
                try FileManager.default.copyItem(at: sourceURL, to: destination)
                copied = true
            } catch {
                copied = false
            }
        }
        guard copied else { throw BookParseError.unreadable }

        // 2. 解析
        var title = sourceURL.deletingPathExtension().lastPathComponent
        var author = ""
        var intro = ""
        var language = "zh"
        var chapters: [Chapter] = []
        var encodingName = "UTF-8"
        var coverData: Data?

        switch format {
        case .txt:
            let parsed = try parseTXT(at: destination)
            encodingName = parsed.encodingName
            chapters = parsed.chapters
            if let first = parsed.chapters.first(where: { !$0.title.isEmpty }) {
                title = first.title
            }
        case .epub:
            let parsed = try EpubParser.parse(at: destination, imagesDirectory: FileStore.imagesDirectory(for: bookId))
            if !parsed.title.isEmpty { title = parsed.title }
            author = parsed.author
            intro = parsed.intro
            language = parsed.language
            chapters = parsed.chapters
            coverData = parsed.coverData
        case .online:
            throw BookParseError.unsupportedFormat
        }

        let characterCount = chapters.reduce(0) { $0 + $1.characterCount }

        // 3. 封面
        var coverFileName: String?
        if let data = coverData, let image = UIImage(data: data) {
            coverFileName = saveCover(image, for: bookId)
        }
        if coverFileName == nil {
            let generated = CoverGenerator.generate(title: title, author: author)
            coverFileName = saveCover(generated, for: bookId)
        }

        // 4. 章节缓存落盘，阅读时秒开
        persistChapters(chapters, for: bookId)

        return Book(
            id: bookId,
            title: title,
            author: author,
            intro: intro,
            format: format,
            fileName: fileName,
            sourceName: sourceURL.lastPathComponent,
            coverFileName: coverFileName,
            encodingName: encodingName,
            chapterCount: chapters.count,
            characterCount: characterCount,
            addedAt: Date(),
            lastReadAt: nil,
            isPinned: false,
            group: "默认",
            sourceId: nil,
            remoteURL: nil,
            language: language
        )
    }

    /// 把解析出的章节缓存写入磁盘
    static func persistChapters(_ chapters: [Chapter], for bookId: UUID) {
        try? FileStore.writeJSON(chapters, to: FileStore.chaptersFile(for: bookId))
    }

    // MARK: - TXT

    private static func parseTXT(at url: URL) throws -> (chapters: [Chapter], encodingName: String) {
        guard let data = try? Data(contentsOf: url, options: [.mappedIfSafe]), !data.isEmpty else {
            throw BookParseError.unreadable
        }
        let detected = EncodingDetector.detect(in: data)
        guard let text = String(data: data, encoding: detected.encoding), !text.isEmpty else {
            throw BookParseError.unreadable
        }

        let cleaned = text
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let sections = ChapterSplitter.split(cleaned)
        let chapters = sections.map { section in
            Chapter.plain(
                title: section.title.isEmpty ? "正文" : section.title,
                content: section.content
            )
        }
        return (chapters, detected.name)
    }

    // MARK: - 封面

    @discardableResult
    static func saveCover(_ image: UIImage, for bookId: UUID) -> String? {
        guard let data = image.jpegData(compressionQuality: 0.85) else { return nil }
        let name = bookId.uuidString + ".jpg"
        let url = FileStore.coversDirectory.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return name
        } catch {
            return nil
        }
    }
}

// MARK: - 默认封面绘制

enum CoverGenerator {
    static func generate(title: String, author: String) -> UIImage {
        let size = CGSize(width: 600, height: 800)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)

        let baseColor = UIColor(Palette.coverBackground(for: title))

        return renderer.image { context in
            let cg = context.cgContext
            baseColor.setFill()
            cg.fill(CGRect(origin: .zero, size: size))

            // 顶部装饰色块
            UIColor.white.withAlphaComponent(0.12).setFill()
            cg.fill(CGRect(x: 0, y: 0, width: size.width, height: 6))

            // 边框
            let border = CGRect(x: 36, y: 44, width: size.width - 72, height: size.height - 88)
            UIColor.white.withAlphaComponent(0.35).setStroke()
            cg.setLineWidth(2)
            cg.stroke(border)

            // 标题
            let displayTitle = title.condensedWhitespace
            let titleLines = wrap(title: displayTitle, maxLines: 6)
            let titleFont = UIFont.systemFont(ofSize: 64, weight: .semibold)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineSpacing = 14

            let titleColor = UIColor.white
            var y = size.height * 0.34 - CGFloat(titleLines.count) * 44
            for line in titleLines {
                line.draw(
                    with: CGRect(x: 60, y: y, width: size.width - 120, height: 84),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: [
                        .font: titleFont,
                        .foregroundColor: titleColor,
                        .paragraphStyle: paragraph,
                    ],
                    context: nil
                )
                y += 84
            }

            // 作者
            if !author.isEmpty {
                let authorFont = UIFont.systemFont(ofSize: 30, weight: .regular)
                author.draw(
                    with: CGRect(x: 60, y: size.height - 150, width: size.width - 120, height: 40),
                    options: [.usesLineFragmentOrigin],
                    attributes: [
                        .font: authorFont,
                        .foregroundColor: UIColor.white.withAlphaComponent(0.85),
                        .paragraphStyle: paragraph,
                    ],
                    context: nil
                )
            }
        }
    }

    private static func wrap(title: String, maxLines: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for character in title {
            current.append(character)
            if current.count >= 6 {
                lines.append(current)
                current = ""
                if lines.count == maxLines - 1 { break }
            }
        }
        if !current.isEmpty { lines.append(current) }
        if lines.isEmpty { lines.append("未命名") }
        if lines.count > maxLines { lines = Array(lines.prefix(maxLines)) }
        return lines
    }
}
