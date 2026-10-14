import Foundation

// MARK: - HTML 节点

/// 轻量 HTML DOM 节点，供书源规则求值使用。
final class HTMLNode {
    let tag: String
    var attributes: [String: String]
    private(set) var children: [HTMLNode] = []
    weak var parent: HTMLNode?
    var text: String = ""

    init(tag: String, attributes: [String: String] = [:], parent: HTMLNode? = nil) {
        self.tag = tag
        self.attributes = attributes
        self.parent = parent
    }

    func append(_ child: HTMLNode) {
        children.append(child)
        child.parent = self
    }

    var isTextNode: Bool { tag == "#text" }

    /// 递归拼接全部文本
    var allText: String {
        if isTextNode { return text }
        return children.map(\.allText).joined()
    }

    /// 仅直接文本（不含子节点）
    var ownText: String {
        children.filter(\.isTextNode).map(\.text).joined()
    }

    var innerHTML: String {
        children.map(\.outerHTML).joined()
    }

    var outerHTML: String {
        if isTextNode { return text }
        var rendered = ""
        for (key, value) in attributes {
            rendered += " \(key)=\"\(value.replacingOccurrences(of: "\"", with: "&quot;"))\""
        }
        return "<\(tag)\(rendered)>" + innerHTML + "</\(tag)>"
    }

    var classes: [String] {
        (attributes["class"] ?? "")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
    }

    func descendants(matching predicate: (HTMLNode) -> Bool) -> [HTMLNode] {
        var result: [HTMLNode] = []
        for child in children {
            if predicate(child) { result.append(child) }
            result.append(contentsOf: child.descendants(matching: predicate))
        }
        return result
    }

    func firstDescendant(matching predicate: (HTMLNode) -> Bool) -> HTMLNode? {
        for child in children {
            if predicate(child) { return child }
            if let found = child.firstDescendant(matching: predicate) { return found }
        }
        return nil
    }

    func allAnchors() -> [HTMLNode] {
        descendants { $0.tag == "a" }
    }
}

// MARK: - HTML 解析器

enum HTMLParser {
    private static let voidTags: Set<String> = [
        "br", "hr", "img", "meta", "link", "input", "area", "base",
        "col", "embed", "source", "track", "wbr", "param",
    ]

    static func parse(_ html: String) -> HTMLNode {
        let root = HTMLNode(tag: "#document")
        var stack: [HTMLNode] = [root]
        var textBuffer = ""
        var index = html.startIndex

        var current: HTMLNode { stack[stack.count - 1] }

        func flushText() {
            guard !textBuffer.isEmpty else { return }
            let node = HTMLNode(tag: "#text", parent: current)
            node.text = textBuffer
            current.append(node)
            textBuffer = ""
        }

        while index < html.endIndex {
            let character = html[index]

            if character == "<" {
                let next = html.index(after: index)
                guard next < html.endIndex else { break }
                let following = html[next]

                if following == "/" {
                    flushText()
                    guard let close = html.range(of: ">", range: next..<html.endIndex) else { break }
                    let tagName = String(html[html.index(after: next)..<close.lowerBound])
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    if let position = stack.lastIndex(where: { $0.tag == tagName }), position > 0 {
                        stack.removeSubrange(position...)
                    }
                    index = close.upperBound
                    continue
                }

                if following == "!" {
                    flushText()
                    if html[next...].hasPrefix("<!--"),
                       let end = html.range(of: "-->", range: index..<html.endIndex) {
                        index = end.upperBound
                    } else if let end = html.range(of: ">", range: index..<html.endIndex) {
                        index = end.upperBound
                    } else {
                        break
                    }
                    continue
                }

                if following.isLetter {
                    flushText()
                    guard let close = html.range(of: ">", range: index..<html.endIndex) else { break }
                    let body = String(html[html.index(after: index)..<close.lowerBound])
                    let parsed = parseTagBody(body)
                    let name = parsed.name.lowercased()
                    let node = HTMLNode(tag: name, attributes: parsed.attributes, parent: current)
                    current.append(node)
                    index = close.upperBound

                    if name == "script" || name == "style" {
                        let closer = "</\(name)"
                        if let end = html.range(of: closer, range: index..<html.endIndex) {
                            node.text = String(html[index..<end.lowerBound])
                            if let gt = html.range(of: ">", range: end.lowerBound..<html.endIndex) {
                                index = gt.upperBound
                            } else {
                                index = html.endIndex
                            }
                        } else {
                            index = html.endIndex
                        }
                    } else if !parsed.selfClosing && !voidTags.contains(name) {
                        stack.append(node)
                    }
                    continue
                }
            }

            textBuffer.append(character)
            index = html.index(after: index)
        }

        flushText()
        return root
    }

    private static func parseTagBody(_ body: String) -> (name: String, attributes: [String: String], selfClosing: Bool) {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        var attributes: [String: String] = [:]
        var selfClosing = false

        guard let nameRegex = try? NSRegularExpression(pattern: "^([A-Za-z][A-Za-z0-9:_.-]*)") else {
            return (trimmed, attributes, false)
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        var name = ""
        if let match = nameRegex.firstMatch(in: trimmed, options: [], range: range),
           let group = Range(match.range(at: 1), in: trimmed) {
            name = String(trimmed[group])
        }

        guard let attrRegex = try? NSRegularExpression(
            pattern: "([A-Za-z_:][-A-Za-z0-9_:.]*)\\s*(?:=\\s*(?:\"([^\"]*)\"|'([^']*)'|([^\\s\"'>]+)))?"
        ) else {
            return (name, attributes, trimmed.hasSuffix("/"))
        }

        let matches = attrRegex.matches(in: trimmed, options: [], range: range)
        for match in matches {
            guard let keyRange = Range(match.range(at: 1), in: trimmed) else { continue }
            let key = String(trimmed[keyRange]).lowercased()
            var value = ""
            for groupIndex in [2, 3, 4] where match.range(at: groupIndex).location != NSNotFound {
                if let valueRange = Range(match.range(at: groupIndex), in: trimmed) {
                    value = String(trimmed[valueRange])
                    break
                }
            }
            attributes[key] = value
        }

        if name.isEmpty { name = trimmed }
        return (name, attributes, trimmed.hasSuffix("/"))
    }
}

// MARK: - 规则求值（Legado 语法子集）

/// 支持：`class.x` / `id.x` / `tag.div` / `.x` / `#x` / 裸标签名 / `children`
/// 终结符：`text` / `ownText` / `html` / `href` / `src` / `title` 等任意属性名
/// 索引：`tag.li[0]`、`tag.li[last]`
/// 正则后处理：`规则##正则##替换`
/// 多备选：`规则A||规则B`
enum HTMLRule {
    private static let terminalKeys: Set<String> = [
        "text", "owntext", "all", "textnodes", "html", "innerhtml", "outerhtml",
        "href", "src", "title", "content", "alt", "value", "textcontent",
        "data-src", "data-original", "data-lazy-src", "data-url", "content_src",
    ]

    // MARK: 节点选择

    static func nodes(_ rule: String, in root: HTMLNode) -> [HTMLNode] {
        let trimmed = rule.trimmed
        guard !trimmed.isEmpty else { return [root] }

        for alternative in trimmed.components(separatedBy: "||") {
            let branch = alternative.trimmed
            guard !branch.isEmpty else { continue }
            let found = walkNodes(branch, from: root)
            if !found.isEmpty { return found }
        }
        return []
    }

    private static func walkNodes(_ rule: String, from root: HTMLNode) -> [HTMLNode] {
        var current: [HTMLNode] = [root]
        let steps = rule.components(separatedBy: "@").map(\.trimmed).filter { !$0.isEmpty }

        for step in steps {
            if terminalKeys.contains(step.lowercased()) { break }
            current = applySelector(step, to: current)
            if current.isEmpty { return [] }
        }
        return current
    }

    private static func applySelector(_ step: String, to nodes: [HTMLNode]) -> [HTMLNode] {
        let (base, indexSpec) = splitIndex(step)
        guard !base.isEmpty else { return nodes }

        var result: [HTMLNode] = []
        let lowered = base.lowercased()

        if lowered == "children" || lowered == "child" {
            for node in nodes {
                result.append(contentsOf: node.children.filter { !$0.isTextNode })
            }
        } else if let predicate = predicate(for: base) {
            for node in nodes {
                result.append(contentsOf: node.descendants(matching: predicate))
            }
        }

        if let indexSpec {
            if indexSpec == "last" {
                return result.isEmpty ? [] : [result[result.count - 1]]
            }
            if let index = Int(indexSpec) {
                if index < 0 {
                    let resolved = result.count + index
                    return result.indices.contains(resolved) ? [result[resolved]] : []
                }
                return result.indices.contains(index) ? [result[index]] : []
            }
            return []
        }
        return result
    }

    private static func predicate(for base: String) -> ((HTMLNode) -> Bool)? {
        let lowered = base.lowercased()

        if lowered.hasPrefix("class.") {
            let value = String(base.dropFirst("class.".count))
            return { $0.classes.contains(value) }
        }
        if lowered.hasPrefix("id.") {
            let value = String(base.dropFirst("id.".count))
            return { $0.attributes["id"] == value }
        }
        if lowered.hasPrefix("tag.") {
            let value = String(base.dropFirst("tag.".count)).lowercased()
            return { $0.tag == value }
        }
        if lowered.hasPrefix("text.") {
            let value = String(base.dropFirst("text.".count))
            return { $0.allText.contains(value) }
        }
        if base.hasPrefix(".") {
            let value = String(base.dropFirst())
            return { $0.classes.contains(value) }
        }
        if base.hasPrefix("#") {
            let value = String(base.dropFirst())
            return { $0.attributes["id"] == value }
        }
        return { $0.tag == lowered }
    }

    private static func splitIndex(_ step: String) -> (base: String, index: String?) {
        guard let open = step.lastIndex(of: "["), step.hasSuffix("]") else {
            return (step.trimmed, nil)
        }
        let base = String(step[..<open]).trimmed
        let index = String(step[step.index(after: open)..<step.index(before: step.endIndex)]).trimmed
        return (base, index.isEmpty ? nil : index)
    }

    // MARK: 字符串求值

    static func string(_ rule: String, in node: HTMLNode) -> String {
        let trimmed = rule.trimmed
        guard !trimmed.isEmpty else { return "" }

        for alternative in trimmed.components(separatedBy: "||") {
            let branch = alternative.trimmed
            guard !branch.isEmpty else { continue }
            let value = evaluateSingle(branch, in: node)
            if !value.isEmpty { return value }
        }
        return ""
    }

    private static func evaluateSingle(_ rule: String, in node: HTMLNode) -> String {
        var working = rule
        var postProcess: (pattern: String, replacement: String)?

        if let range = working.range(of: "##") {
            let tail = String(working[range.upperBound...])
            let parts = tail.components(separatedBy: "##")
            if !parts[0].isEmpty {
                postProcess = (parts[0], parts.count > 1 ? parts[1] : "")
            }
            working = String(working[..<range.lowerBound])
        }

        let steps = working.components(separatedBy: "@").map(\.trimmed).filter { !$0.isEmpty }
        var current: [HTMLNode] = [node]
        var result = ""

        for step in steps {
            let lowered = step.lowercased()
            if terminalKeys.contains(lowered) {
                result = terminalValue(lowered, from: current)
                current = []
                break
            }
            current = applySelector(step, to: current)
            if current.isEmpty { break }
        }

        if result.isEmpty, let first = current.first {
            result = first.allText.condensedWhitespace
        }

        if let postProcess {
            result = applyRegex(postProcess.pattern, replacement: postProcess.replacement, to: result)
        }
        return result
    }

    private static func terminalValue(_ key: String, from nodes: [HTMLNode]) -> String {
        guard let first = nodes.first else { return "" }
        switch key {
        case "text", "textcontent", "all":
            return first.allText.condensedWhitespace
        case "owntext":
            return first.ownText.condensedWhitespace
        case "textnodes":
            return first.descendants { $0.isTextNode }.map(\.text).joined(separator: " ").condensedWhitespace
        case "html", "innerhtml":
            return first.innerHTML
        case "outerhtml":
            return first.outerHTML
        default:
            return first.attributes[key] ?? first.attributes[key.replacingOccurrences(of: "_", with: "-")] ?? ""
        }
    }

    private static func applyRegex(_ pattern: String, replacement: String, to text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        // ICU 模板里 $n 是捕获组引用，字面 $ 需要转义
        let template = replacement.replacingOccurrences(of: "$", with: "\\$")
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }
}

// MARK: - 实体解码

enum HTMLEntities {
    private static let named: [String: String] = [
        "nbsp": "\u{00A0}", "amp": "&", "lt": "<", "gt": ">", "quot": "\"",
        "apos": "'", "copy": "©", "reg": "®", "trade": "™",
        "mdash": "—", "ndash": "–", "hellip": "…", "middot": "·",
        "ldquo": "“", "rdquo": "”", "lsquo": "‘", "rsquo": "’",
        "laquo": "«", "raquo": "»", "times": "×", "divide": "÷",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (name, value) in named {
            result = result.replacingOccurrences(of: "&\(name);", with: value)
        }
        // 数字实体
        if let regex = try? NSRegularExpression(pattern: "&#x([0-9A-Fa-f]+);") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range) { match in
                guard let range = Range(match.range(at: 1), in: result),
                      let scalar = UInt32(result[range], radix: 16),
                      let unicode = Unicode.Scalar(scalar) else { return "" }
                return String(Character(unicode))
            }
        }
        // 十进制实体
        if let regex = try? NSRegularExpression(pattern: "&#(\\d+);") {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(in: result, options: [], range: range) { match in
                guard let range = Range(match.range(at: 1), in: result),
                      let scalar = UInt32(result[range]),
                      let unicode = Unicode.Scalar(scalar) else { return "" }
                return String(Character(unicode))
            }
        }
        return result
    }
}

private extension NSRegularExpression {
    func stringByReplacingMatches(
        in string: String,
        options: NSRegularExpression.MatchingOptions = [],
        range: NSRange,
        using block: (NSTextCheckingResult) -> String
    ) -> String {
        let matches = self.matches(in: string, options: options, range: range)
        guard !matches.isEmpty else { return string }

        var output = ""
        var cursor = range.location

        for match in matches {
            if match.range.location > cursor {
                let gapLength = match.range.location - cursor
                if let gap = Range(NSRange(location: cursor, length: gapLength), in: string) {
                    output += String(string[gap])
                }
            }
            output += block(match)
            cursor = match.range.location + match.range.length
        }

        let tailLength = range.location + range.length - cursor
        if tailLength > 0,
           let tail = Range(NSRange(location: cursor, length: tailLength), in: string) {
            output += String(string[tail])
        }
        return output
    }
}
