import Foundation

/// TXT 章节切分：基于标题行正则 + 启发式门控。
enum ChapterSplitter {
    private static let titleRegexes: [NSRegularExpression] = {
        let patterns = [
            // 第x章 / 第x节 / 第x卷 / 第x回 / 第x篇（允许中英数字与标点）
            "^第\\s*[0-9零一二三四五六七八九十百千万两〇零]+\\s*[章节節回卷篇部集]\\s*[、．.::：\\-—－~～]?\\s*\\S{0,32}$",
            "^卷[0-9一二三四五六七八九十]{1,6}\\s*\\S{0,32}$",
            "^(?:Chapter|CHAPTER|chapter)\\s*(?:[0-9]{1,4}|[IVXLCivxlc]{1,7})\\b.{0,32}$",
            "^(?:序章|序言|序|楔子|引子|引言|前言|后记|后序|尾声|终章|大结局|番外)\\s*\\S{0,24}$",
            "^[0-9]{1,4}[、．.]\\s*\\S{1,32}$",
        ]
        return patterns.compactMap { try? NSRegularExpression(pattern: $0, options: [.anchorsMatchLines]) }
    }()

    /// 门控字符：标题行几乎都以这些字符开头，避免对全文每行跑 5 个正则
    private static let gates: Set<Character> = [
        "第", "卷", "章", "节", "回", "篇", "序", "楔", "引", "前", "后", "终", "番", "大",
        "C", "c", "N", "（", "(", "【", "[",
    ]

    static func split(_ text: String) -> [(title: String, content: String)] {
        let lines = text.components(separatedBy: CharacterSet.newlines)
        guard !lines.isEmpty else { return [("", "")] }

        var titleIndices: [Int] = []
        titleIndices.reserveCapacity(256)
        for (index, line) in lines.enumerated() where isTitleLine(line) {
            titleIndices.append(index)
        }

        guard !titleIndices.isEmpty else {
            return [("", text)]
        }

        // 章节数异常多（>5000）通常是误判，退化为整本一章
        guard titleIndices.count < 5000 else {
            return [("", text)]
        }

        var chapters: [(title: String, content: String)] = []
        chapters.reserveCapacity(titleIndices.count + 1)

        if titleIndices[0] > 0 {
            let preamble = lines[0..<titleIndices[0]].joined(separator: "\n")
            if preamble.trimmed.count > 0 {
                chapters.append(("", preamble))
            }
        }

        for (position, start) in titleIndices.enumerated() {
            let end = position + 1 < titleIndices.count ? titleIndices[position + 1] : lines.count
            let title = lines[start].trimmed
            var body = ""
            if start + 1 < end {
                body = lines[(start + 1)..<end].joined(separator: "\n")
            }
            chapters.append((title, body))
        }

        return chapters
    }

    static func isTitleLine(_ line: String) -> Bool {
        let trimmed = line.trimmed
        guard !trimmed.isEmpty, trimmed.count <= 44 else { return false }
        guard let first = trimmed.first else { return false }
        guard gates.contains(first) || first.isNumber else { return false }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        return titleRegexes.contains { $0.firstMatch(in: trimmed, options: [], range: range) != nil }
    }
}
