import Foundation

// MARK: - 解析错误

enum BookParseError: LocalizedError {
    case unreadable
    case unsupportedFormat
    case corruptedArchive
    case missingOPF
    case noContent

    var errorDescription: String? {
        switch self {
        case .unreadable: return "文件无法读取"
        case .unsupportedFormat: return "暂不支持的格式"
        case .corruptedArchive: return "文件已损坏（ZIP 结构无法解析）"
        case .missingOPF: return "EPUB 缺少元数据描述文件"
        case .noContent: return "没有解析到任何章节内容"
        }
    }
}

// MARK: - 解析结果

struct EpubParseResult {
    var title: String = ""
    var author: String = ""
    var intro: String = ""
    var language: String = "zh"
    var coverData: Data?
    var chapters: [Chapter] = []
}

// MARK: - EPUB 解析器

enum EpubParser {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp"]

    static func parse(at url: URL, imagesDirectory: URL) throws -> EpubParseResult {
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)

        guard let archive = ZipArchive(url: url) else { throw BookParseError.corruptedArchive }

        // 1. container.xml → OPF 路径
        guard let containerData = archive.data(forFile: "META-INF/container.xml") else {
            throw BookParseError.missingOPF
        }
        let containerDelegate = ContainerXMLDelegate()
        let containerParser = XMLParser(data: containerData)
        containerParser.delegate = containerDelegate
        containerParser.parse()

        guard let opfPath = containerDelegate.opfPath, archive.contains(opfPath) else {
            throw BookParseError.missingOPF
        }

        // 2. OPF 元数据 + manifest + spine
        guard let opfData = archive.data(forFile: opfPath) else { throw BookParseError.missingOPF }
        let opfDelegate = OPFParserDelegate()
        let opfParser = XMLParser(data: opfData)
        opfParser.delegate = opfDelegate
        opfParser.parse()

        var result = EpubParseResult()
        result.title = opfDelegate.title
        result.author = opfDelegate.creator
        result.intro = opfDelegate.descriptionText
        result.language = opfDelegate.language.isEmpty ? "zh" : opfDelegate.language

        let opfDirectory = (opfPath as NSString).deletingLastPathComponent

        // 3. 抽出所有图片，供渲染期内联为 data URI
        var imageMap: [String: String] = [:]
        for name in archive.entryNames where imageExtensions.contains(name.pathExtension.lowercased()) {
            guard let data = archive.data(forFile: name) else { continue }
            let sanitized = name.replacingOccurrences(of: "/", with: "_")
            let target = imagesDirectory.appendingPathComponent(sanitized)
            try? data.write(to: target)
            imageMap[name] = sanitized
        }

        // 4. 封面
        result.coverData = coverData(
            from: archive,
            opfDelegate: opfDelegate,
            opfDirectory: opfDirectory,
            imageMap: imageMap
        )

        // 5. 目录（NCX）
        var tocMap: [String: String] = [:]
        if let ncxItem = ncxItem(in: opfDelegate, opfDirectory: opfDirectory),
           let ncxData = archive.data(forFile: ncxItem.href) {
            let ncxDelegate = NCXParserDelegate()
            let ncxParser = XMLParser(data: ncxData)
            ncxParser.delegate = ncxDelegate
            ncxParser.parse()
            let ncxDirectory = (ncxItem.href as NSString).deletingLastPathComponent
            for entry in ncxDelegate.toc {
                let resolved = resolvePath(entry.href, relativeTo: ncxDirectory)
                let key = resolved.split(separator: "#").first.map(String.init) ?? resolved
                if tocMap[key] == nil || tocMap[key]!.isEmpty {
                    tocMap[key] = entry.title
                }
            }
        }

        // 6. 逐个 spine 条目生成章节
        for idref in opfDelegate.spineIDRefs {
            guard let item = opfDelegate.manifest[idref] else { continue }
            let mediaType = item.mediaType.lowercased()
            let ext = item.href.pathExtension.lowercased()
            let isDocument = mediaType.contains("html") || ["xhtml", "html", "htm"].contains(ext)
            guard isDocument else { continue }

            let zipPath = resolvePath(item.href, relativeTo: opfDirectory)
            guard let data = archive.data(forFile: zipPath) else { continue }

            let html = normalizeHTML(data, chapterDirectory: (zipPath as NSString).deletingLastPathComponent, imageMap: imageMap)
            guard !html.isEmpty else { continue }

            let title = tocMap[zipPath] ?? extractTitle(from: html) ?? fallbackTitle(from: item.href)
            let plainLength = stripTags(html).count
            guard plainLength > 0 || html.contains("<img") else { continue }

            result.chapters.append(
                Chapter(
                    title: title,
                    content: html,
                    isHTML: true,
                    characterCount: plainLength,
                    url: nil
                )
            )
            if result.chapters.count >= 5000 { break }
        }

        guard !result.chapters.isEmpty else { throw BookParseError.noContent }
        return result
    }

    // MARK: - 封面

    private static func coverData(
        from archive: ZipArchive,
        opfDelegate: OPFParserDelegate,
        opfDirectory: String,
        imageMap: [String: String]
    ) -> Data? {
        var candidatePath: String?

        if let metaID = opfDelegate.coverMetaID, let item = opfDelegate.manifest[metaID] {
            candidatePath = resolvePath(item.href, relativeTo: opfDirectory)
        }
        if candidatePath == nil {
            if let item = opfDelegate.manifest.values.first(where: { $0.properties.contains("cover-image") }) {
                candidatePath = resolvePath(item.href, relativeTo: opfDirectory)
            }
        }
        if candidatePath == nil {
            candidatePath = archive.entryNames.first {
                imageExtensions.contains($0.pathExtension.lowercased()) &&
                    $0.lowercased().contains("cover")
            }
        }
        guard let path = candidatePath else { return nil }
        return archive.data(forFile: path)
    }

    private static func ncxItem(in opf: OPFParserDelegate, opfDirectory: String) -> OPFParserDelegate.ManifestItem? {
        if let tocID = opf.tocID, let item = opf.manifest[tocID] { return item }
        return opf.manifest.values.first { $0.mediaType.lowercased().contains("dtbncx") }
    }

    // MARK: - HTML 规范化

    /// 抽出 body、去掉脚本样式，并把图片引用重写到本地文件。
    static func normalizeHTML(_ data: Data, chapterDirectory: String, imageMap: [String: String]) -> String {
        let html = decodeHTML(data)
        guard !html.isEmpty else { return "" }

        var body = html
        if let match = firstGroup(in: html, pattern: "<body[^>]*>([\\s\\S]*?)</body>") {
            body = match
        }
        body = removePattern(from: body, pattern: "<script[\\s\\S]*?</script>")
        body = removePattern(from: body, pattern: "<style[\\s\\S]*?</style>")
        body = removePattern(from: body, pattern: "<!--[\\s\\S]*?-->")

        return rewriteImageReferences(in: body, chapterDirectory: chapterDirectory, imageMap: imageMap)
    }

    static func decodeHTML(_ data: Data) -> String {
        let head = String(data: data.prefix(2048), encoding: .utf8) ?? ""
        var charsetName: String?
        if let match = firstGroup(in: head, pattern: "(?i)charset\\s*=\\s*[\"']?([A-Za-z0-9_\\-]+)") {
            charsetName = match
        }
        if let name = charsetName {
            let encoding = ianaEncoding(for: name)
            if encoding.rawValue != 0, let text = String(data: data, encoding: encoding) {
                return text
            }
        }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: EncodingDetector.gb18030) ?? ""
    }

    static func ianaEncoding(for name: String) -> String.Encoding {
        let key = name
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\"", with: "")
            .lowercased()
        switch key {
        case "gbk", "gb2312", "gb18030", "csgb2312", "gb_2312":
            return EncodingDetector.gb18030
        case "big5", "big5-hkscs", "csbig5":
            return EncodingDetector.big5
        case "shift_jis", "shift-jis", "sjis", "csshiftjis":
            return .shiftJIS
        case "utf-16", "utf16":
            return .utf16
        case "utf-16le":
            return .utf16LittleEndian
        case "utf-16be":
            return .utf16BigEndian
        case "iso-8859-1", "latin1":
            return .isoLatin1
        default:
            return .utf8
        }
    }

    static func rewriteImageReferences(in html: String, chapterDirectory: String, imageMap: [String: String]) -> String {
        guard !imageMap.isEmpty else { return html }
        guard let regex = try? NSRegularExpression(
            pattern: "(?i)(src|xlink:href)\\s*=\\s*(?:\"([^\"]*)\"|'([^']*)')"
        ) else { return html }

        let mutable = NSMutableString(string: html)
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).reversed()

        for match in matches {
            guard let group = [2, 3].first(where: { match.range(at: $0).location != NSNotFound }),
                  let rawRange = Range(match.range(at: group), in: html) else { continue }

            let raw = String(html[rawRange])
            guard !raw.isEmpty else { continue }
            if raw.lowercased().hasPrefix("data:") || raw.lowercased().hasPrefix("http") { continue }

            let cleaned = raw.removingPercentEncoding ?? raw
            let resolved = resolvePath(cleaned, relativeTo: chapterDirectory)
            guard imageMap[resolved] != nil else { continue }
            mutable.replaceCharacters(in: match.range(at: group), with: resolved)
        }
        return mutable as String
    }

    static func stripTags(_ html: String) -> String {
        var text = removePattern(from: html, pattern: "<[\\s\\S]*?>")
        text = text
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
        return text
    }

    // MARK: - 工具

    static func resolvePath(_ href: String, relativeTo baseDirectory: String) -> String {
        let cleaned = (href as NSString).removingPercentEncoding ?? href
        let combined = baseDirectory.isEmpty ? cleaned : baseDirectory + "/" + cleaned
        var components: [String] = []
        for part in combined.split(separator: "/") {
            switch part {
            case "..": if !components.isEmpty { components.removeLast() }
            case ".": break
            default: components.append(String(part))
            }
        }
        return components.joined(separator: "/")
    }

    static func firstGroup(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[groupRange])
    }

    static func removePattern(from text: String, pattern: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, with: "")
    }

    private static func extractTitle(from html: String) -> String? {
        guard let title = firstGroup(in: html, pattern: "<title[^>]*>([\\s\\S]*?)</title>") else { return nil }
        let cleaned = stripTags(title).condensedWhitespace
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func fallbackTitle(from href: String) -> String {
        let name = (href as NSString).lastPathComponent
        return (name as NSString).deletingPathExtension
    }
}

// MARK: - XML 委托

private extension String {
    var xmlLocalName: String {
        if let index = firstIndex(of: ":") {
            return String(self[index(after: index)...])
        }
        return self
    }
}

final class ContainerXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var opfPath: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        if elementName.xmlLocalName == "rootfile" {
            opfPath = attributes["full-path"] ?? opfPath
        }
    }
}

final class OPFParserDelegate: NSObject, XMLParserDelegate {
    struct ManifestItem {
        var id: String
        var href: String
        var mediaType: String
        var properties: String
    }

    private(set) var manifest: [String: ManifestItem] = [:]
    private(set) var spineIDRefs: [String] = []
    private(set) var tocID: String?
    private(set) var title = ""
    private(set) var creator = ""
    private(set) var descriptionText = ""
    private(set) var language = ""
    private(set) var coverMetaID: String?

    private var currentTarget: String?
    private var buffer = ""

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.xmlLocalName
        buffer = ""

        switch name {
        case "item":
            let id = attributes["id"] ?? ""
            let href = attributes["href"] ?? ""
            guard !id.isEmpty, !href.isEmpty else { return }
            manifest[id] = ManifestItem(
                id: id,
                href: href,
                mediaType: attributes["media-type"] ?? "",
                properties: attributes["properties"] ?? ""
            )
        case "itemref":
            if let idref = attributes["idref"] { spineIDRefs.append(idref) }
        case "spine":
            tocID = attributes["toc"]
        case "meta":
            if attributes["name"] == "cover" { coverMetaID = attributes["content"] }
        case "title", "creator", "description", "language":
            currentTarget = name
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if currentTarget != nil { buffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.xmlLocalName
        guard let target = currentTarget, name == target else { return }
        let text = buffer.trimmed
        switch target {
        case "title": title = text
        case "creator": creator = text
        case "description": descriptionText = text
        case "language": language = text
        default: break
        }
        currentTarget = nil
        buffer = ""
    }
}

final class NCXParserDelegate: NSObject, XMLParserDelegate {
    private(set) var toc: [(href: String, title: String)] = []

    private var insideNavLabel = false
    private var insideText = false
    private var textBuffer = ""
    private var pendingHref: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String]
    ) {
        let name = elementName.xmlLocalName
        if name == "content" { pendingHref = attributes["src"] }
        if name == "navLabel" { insideNavLabel = true }
        if name == "text", insideNavLabel { insideText = true; textBuffer = "" }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { textBuffer += string }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = elementName.xmlLocalName
        if name == "text" { insideText = false }
        if name == "navLabel" { insideNavLabel = false }
        if name == "navPoint" {
            if let href = pendingHref {
                toc.append((href, textBuffer.trimmed))
            }
            pendingHref = nil
            textBuffer = ""
        }
    }
}
