import Foundation
import UIKit

/// 网络书源引擎：搜索 / 详情 / 目录 / 正文。
/// 支持的规则语法见 `HTMLRule`（Legado 规则子集）。
enum BookSourceEngine {
    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    enum SourceError: LocalizedError {
        case invalidURL
        case emptyRule
        case requestFailed(Int)
        case emptyResult

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "书源里的地址无法解析"
            case .emptyRule: return "书源缺少必要的规则"
            case .requestFailed(let code): return "请求失败（HTTP \(code)）"
            case .emptyResult: return "没有解析到任何结果"
            }
        }
    }

    // MARK: - 网络请求

    static func fetchText(_ url: URL) async throws -> String {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml,*/*;q=0.8", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SourceError.requestFailed(http.statusCode)
        }
        return EpubParser.decodeHTML(data)
    }

    static func buildURL(_ template: String, keyword: String = "", page: Int = 1) -> URL? {
        let encodedKey = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? keyword
        var url = template
            .replacingOccurrences(of: "{{key}}", with: encodedKey)
            .replacingOccurrences(of: "{{page}}", with: "\(page)")
            .replacingOccurrences(of: "{key}", with: encodedKey)
            .replacingOccurrences(of: "{page}", with: "\(page)")
            .trimmingCharacters(in: .whitespaces)
        // Legado 允许 searchUrl 带 ",{"charset":"gbk"}" 之类的后缀
        if let range = url.range(of: ",{") {
            url = String(url[..<range.lowerBound])
        }
        if url.hasPrefix("//") {
            url = "https:" + url
        }
        return URL(string: url)
    }

    static func absoluteURL(_ value: String, relativeTo base: URL?) -> String {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return "" }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        guard let base else { return trimmed }
        if trimmed.hasPrefix("//") {
            return (base.scheme ?? "https") + ":" + trimmed
        }
        if let resolved = URL(string: trimmed, relativeTo: base) {
            return resolved.absoluteString
        }
        return trimmed
    }

    // MARK: - 搜索

    static func search(keyword: String, source: BookSource, page: Int = 1) async throws -> [SearchBookResult] {
        guard !source.searchURL.isEmpty else { throw SourceError.emptyRule }
        guard let url = buildURL(source.searchURL, keyword: keyword, page: page) else {
            throw SourceError.invalidURL
        }

        let html = try await fetchText(url)
        let document = HTMLParser.parse(html)
        let baseURL = url

        let listRule = source.ruleSearch.bookList
        let items = HTMLRule.nodes(listRule, in: document)
        guard !items.isEmpty else { return [] }

        var results: [SearchBookResult] = []
        var seen = Set<String>()

        for item in items.prefix(30) {
            let name = clean(HTMLRule.string(source.ruleSearch.name, in: item))
            guard !name.isEmpty else { continue }
            let author = cleanAuthor(HTMLRule.string(source.ruleSearch.author, in: item))
            let rawURL = HTMLRule.string(source.ruleSearch.bookURL, in: item)
            let bookURL = rawURL.isEmpty ? "" : absoluteURL(rawURL, relativeTo: baseURL)
            guard !bookURL.isEmpty else { continue }

            let result = SearchBookResult(
                sourceId: source.id,
                sourceName: source.sourceName.isEmpty ? source.sourceURL : source.sourceName,
                name: name,
                author: author,
                coverURL: absoluteURL(HTMLRule.string(source.ruleSearch.coverURL, in: item), relativeTo: baseURL),
                intro: clean(HTMLRule.string(source.ruleSearch.intro, in: item)).truncating(to: 120),
                bookURL: bookURL
            )
            if seen.insert(result.bookURL).inserted {
                results.append(result)
            }
            if results.count >= 20 { break }
        }
        return results
    }

    /// 并发搜索多个书源
    static func searchAll(
        keyword: String,
        sources: [BookSource],
        progress: @escaping @MainActor (String) -> Void
    ) async -> [SearchBookResult] {
        await withTaskGroup(of: [SearchBookResult].self) { group in
            for source in sources.prefix(12) {
                group.addTask { @MainActor in
                    progress(source.sourceName)
                    return (try? await search(keyword: keyword, source: source)) ?? []
                }
            }
            var merged: [SearchBookResult] = []
            var seenByName = Set<String>()
            for await results in group {
                for result in results {
                    let key = result.name + "|" + result.author
                    if seenByName.insert(key).inserted {
                        merged.append(result)
                    }
                }
            }
            return merged
        }
    }

    // MARK: - 详情

    static func fetchBookInfo(source: BookSource, bookURL: String) async throws -> Book {
        guard let url = URL(string: bookURL) else { throw SourceError.invalidURL }
        let html = try await fetchText(url)
        let document = HTMLParser.parse(html)

        let rules = source.ruleBookInfo
        let title = clean(HTMLRule.string(rules.name, in: document))
        let author = cleanAuthor(HTMLRule.string(rules.author, in: document))
        let intro = clean(HTMLRule.string(rules.intro, in: document))
        let coverURL = absoluteURL(HTMLRule.string(rules.coverURL, in: document), relativeTo: url)

        var book = Book()
        book.title = title.isEmpty ? url.deletingPathExtension().lastPathComponent : title
        book.author = author
        book.intro = intro
        book.format = .online
        book.sourceId = source.id
        book.remoteURL = bookURL

        if !coverURL.isEmpty, let coverData = try? await fetchImage(URL(string: coverURL)) {
            book.coverFileName = BookImporter.saveCover(UIImage(data: coverData) ?? UIImage(), for: book.id)
        }
        if book.coverFileName == nil {
            book.coverFileName = BookImporter.saveCover(
                CoverGenerator.generate(title: book.title, author: book.author),
                for: book.id
            )
        }
        return book
    }

    // MARK: - 目录

    static func fetchTOC(source: BookSource, bookURL: String) async throws -> [Chapter] {
        guard let url = URL(string: bookURL) else { throw SourceError.invalidURL }
        let html = try await fetchText(url)
        let document = HTMLParser.parse(html)

        let listRule = source.ruleToc.chapterList
        var items = listRule.isEmpty ? [] : HTMLRule.nodes(listRule, in: document)

        // 兜底：没有目录规则时，把页面里的所有链接当章节
        if items.isEmpty {
            items = document.allAnchors()
        }
        guard !items.isEmpty else { throw SourceError.emptyResult }

        var chapters: [Chapter] = []
        for item in items.prefix(5000) {
            let name = clean(HTMLRule.string(source.ruleToc.chapterName, in: item))
            let rawURL = HTMLRule.string(source.ruleToc.chapterURL, in: item)
            let chapterURL = rawURL.isEmpty ? (item.attributes["href"] ?? "") : rawURL
            guard !chapterURL.isEmpty else { continue }

            let absolute = absoluteURL(chapterURL, relativeTo: url)
            let title = name.isEmpty ? "未命名章节" : name
            chapters.append(
                Chapter(title: title, content: "", isHTML: false, characterCount: 0, url: absolute)
            )
        }
        guard !chapters.isEmpty else { throw SourceError.emptyResult }
        return chapters
    }

    // MARK: - 正文

    static func fetchContent(source: BookSource, chapterURL: String) async throws -> String {
        guard let url = URL(string: chapterURL) else { throw SourceError.invalidURL }
        guard !source.ruleContent.content.isEmpty else { throw SourceError.emptyRule }

        let html = try await fetchText(url)
        let document = HTMLParser.parse(html)

        var content = HTMLRule.string(source.ruleContent.content, in: document)
        if content.isEmpty {
            content = document.firstDescendant { $0.tag == "body" }?.allText ?? ""
        }
        let text = htmlToPlainText(content)
        guard !text.isEmpty else { throw SourceError.emptyResult }
        return text
    }

    // MARK: - 书源导入

    static func parseSources(from data: Data) -> [BookSource] {
        let decoder = JSONDecoder()

        if let array = try? decoder.decode([LegadoSource].self, from: data) {
            return array.compactMap(\.asBookSource)
        }
        if let single = try? decoder.decode(LegadoSource.self, from: data) {
            return [single].compactMap(\.asBookSource)
        }
        return []
    }

    private struct LegadoSource: Decodable {
        var bookSourceName: String?
        var bookSourceUrl: String?
        var bookSourceGroup: String?
        var enabled: Bool?
        var searchUrl: String?
        var ruleSearch: RuleSet?
        var ruleBookInfo: RuleSet?
        var ruleToc: RuleSet?
        var ruleContent: RuleSet?

        struct RuleSet: Decodable {
            var bookList: String?
            var name: String?
            var author: String?
            var coverUrl: String?
            var intro: String?
            var bookUrl: String?
            var chapterList: String?
            var chapterName: String?
            var chapterUrl: String?
            var content: String?
        }

        var asBookSource: BookSource? {
            guard let url = bookSourceUrl, !url.isEmpty else { return nil }
            var source = BookSource()
            source.sourceURL = url
            source.sourceName = bookSourceName ?? url
            source.sourceGroup = bookSourceGroup ?? ""
            source.enabled = enabled ?? true
            source.searchURL = searchUrl ?? ""

            source.ruleSearch = BookSource.SourceRuleSet(
                bookList: ruleSearch?.bookList ?? "",
                name: ruleSearch?.name ?? "",
                author: ruleSearch?.author ?? "",
                coverURL: ruleSearch?.coverUrl ?? "",
                intro: ruleSearch?.intro ?? "",
                bookURL: ruleSearch?.bookUrl ?? "",
                chapterList: "",
                chapterName: "",
                chapterURL: "",
                content: ""
            )
            source.ruleBookInfo = BookSource.SourceRuleSet(
                bookList: "",
                name: ruleBookInfo?.name ?? "",
                author: ruleBookInfo?.author ?? "",
                coverURL: ruleBookInfo?.coverUrl ?? "",
                intro: ruleBookInfo?.intro ?? "",
                bookURL: ruleBookInfo?.bookUrl ?? "",
                chapterList: "",
                chapterName: "",
                chapterURL: "",
                content: ""
            )
            source.ruleToc = BookSource.TOCRule(
                chapterList: ruleToc?.chapterList ?? "",
                chapterName: ruleToc?.chapterName ?? "",
                chapterURL: ruleToc?.chapterUrl ?? ""
            )
            source.ruleContent = BookSource.ContentRule(
                content: ruleContent?.content ?? ""
            )
            return source
        }
    }

    // MARK: - 工具

    static func fetchImage(_ url: URL?) async throws -> Data? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(defaultUserAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return data.isEmpty ? nil : data
    }

    /// HTML 片段 → 适合分段的纯文本
    static func htmlToPlainText(_ html: String) -> String {
        var text = html
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</p>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)<p[^>]*>", with: "", options: .regularExpression)
        text = EpubParser.removePattern(from: text, pattern: "<script[\\s\\S]*?</script>")
        text = EpubParser.removePattern(from: text, pattern: "<style[\\s\\S]*?</style>")
        text = EpubParser.removePattern(from: text, pattern: "<[^>]+>")
        text = HTMLEntities.decode(text)
        text = text
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        // 压缩多余空行，但保留段落
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmed
            lines.append(trimmed)
        }
        var output: [String] = []
        var previousEmpty = true
        for line in lines {
            if line.isEmpty {
                if !previousEmpty {
                    output.append("")
                    previousEmpty = true
                }
            } else {
                output.append(line)
                previousEmpty = false
            }
        }
        while output.last?.isEmpty == true { output.removeLast() }
        return output.joined(separator: "\n")
    }

    private static func clean(_ text: String) -> String {
        HTMLEntities.decode(text.replacingOccurrences(of: "\u{00A0}", with: " "))
            .condensedWhitespace
    }

    private static func cleanAuthor(_ text: String) -> String {
        let cleaned = clean(text)
        if cleaned.hasPrefix("作者") {
            return cleaned.replacingOccurrences(of: "作者[::]", with: "", options: .regularExpression).trimmed
        }
        return cleaned
    }
}
