import Foundation

// MARK: - 书籍格式

enum BookFormat: String, Codable, CaseIterable {
    case txt
    case epub
    case online

    var displayName: String {
        switch self {
        case .txt: return "TXT"
        case .epub: return "EPUB"
        case .online: return "在线"
        }
    }

    var symbolName: String {
        switch self {
        case .txt: return "doc.plaintext"
        case .epub: return "book.closed"
        case .online: return "globe.asia.australia"
        }
    }
}

// MARK: - 书籍

struct Book: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var title: String = ""
    var author: String = ""
    var intro: String = ""
    var format: BookFormat = .txt
    /// Books/ 目录下的源文件名
    var fileName: String = ""
    /// 导入时的原始文件名（去重用）
    var sourceName: String = ""
    /// Covers/ 目录下的封面文件名
    var coverFileName: String?
    var encodingName: String = "UTF-8"
    var chapterCount: Int = 0
    var characterCount: Int = 0
    var addedAt: Date = Date()
    var lastReadAt: Date?
    var isPinned: Bool = false
    var group: String = "默认"
    var sourceId: UUID?
    /// 在线书籍的详情页地址
    var remoteURL: String?
    var language: String = "zh"

    var isLocal: Bool { sourceId == nil }

    /// 后加字段用 decodeIfPresent，避免老版本 library.json 解码失败导致书架被清空
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        author = try container.decodeIfPresent(String.self, forKey: .author) ?? ""
        intro = try container.decodeIfPresent(String.self, forKey: .intro) ?? ""
        format = try container.decodeIfPresent(BookFormat.self, forKey: .format) ?? .txt
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName) ?? ""
        sourceName = try container.decodeIfPresent(String.self, forKey: .sourceName) ?? ""
        coverFileName = try container.decodeIfPresent(String.self, forKey: .coverFileName)
        encodingName = try container.decodeIfPresent(String.self, forKey: .encodingName) ?? "UTF-8"
        chapterCount = try container.decodeIfPresent(Int.self, forKey: .chapterCount) ?? 0
        characterCount = try container.decodeIfPresent(Int.self, forKey: .characterCount) ?? 0
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        lastReadAt = try container.decodeIfPresent(Date.self, forKey: .lastReadAt)
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        group = try container.decodeIfPresent(String.self, forKey: .group) ?? "默认"
        sourceId = try container.decodeIfPresent(UUID.self, forKey: .sourceId)
        remoteURL = try container.decodeIfPresent(String.self, forKey: .remoteURL)
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? "zh"
    }

    init(
        id: UUID = UUID(),
        title: String = "",
        author: String = "",
        intro: String = "",
        format: BookFormat = .txt,
        fileName: String = "",
        sourceName: String = "",
        coverFileName: String? = nil,
        encodingName: String = "UTF-8",
        chapterCount: Int = 0,
        characterCount: Int = 0,
        addedAt: Date = Date(),
        lastReadAt: Date? = nil,
        isPinned: Bool = false,
        group: String = "默认",
        sourceId: UUID? = nil,
        remoteURL: String? = nil,
        language: String = "zh"
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.intro = intro
        self.format = format
        self.fileName = fileName
        self.sourceName = sourceName
        self.coverFileName = coverFileName
        self.encodingName = encodingName
        self.chapterCount = chapterCount
        self.characterCount = characterCount
        self.addedAt = addedAt
        self.lastReadAt = lastReadAt
        self.isPinned = isPinned
        self.group = group
        self.sourceId = sourceId
        self.remoteURL = remoteURL
        self.language = language
    }
}

// MARK: - 章节

struct Chapter: Codable, Hashable {
    var title: String
    /// 纯文本（TXT）或规范化 HTML（EPUB / 在线）
    var content: String
    var isHTML: Bool
    var characterCount: Int
    /// 在线章节的地址
    var url: String?

    static func plain(title: String, content: String) -> Chapter {
        Chapter(
            title: title,
            content: content,
            isHTML: false,
            characterCount: content.count,
            url: nil
        )
    }
}

// MARK: - 阅读进度

struct ReadingProgress: Codable, Hashable {
    var chapterIndex: Int = 0
    var pageIndex: Int = 0
    var characterOffset: Int = 0
    var percent: Double = 0
    var updatedAt: Date = Date()
    var totalReadingSeconds: Double = 0
}

// MARK: - 书签 / 划线

struct Bookmark: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var bookId: UUID
    var chapterIndex: Int
    var characterOffset: Int
    var text: String
    var note: String = ""
    var kind: Kind = .bookmark
    var createdAt: Date = Date()

    enum Kind: String, Codable {
        case bookmark
        case highlight
    }
}

// MARK: - 书源（Legado 兼容子集）

struct BookSource: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    /// Legado: bookSourceUrl，同时作为唯一标识
    var sourceURL: String = ""
    var sourceName: String = ""
    var sourceGroup: String = ""
    var enabled: Bool = true
    var searchURL: String = ""
    var ruleSearch: SourceRuleSet = SourceRuleSet()
    var ruleBookInfo: SourceRuleSet = SourceRuleSet()
    var ruleToc: TOCRule = TOCRule()
    var ruleContent: ContentRule = ContentRule()
    var lastUsedAt: Date?

    struct SourceRuleSet: Codable, Hashable {
        var bookList: String = ""
        var name: String = ""
        var author: String = ""
        var coverURL: String = ""
        var intro: String = ""
        var bookURL: String = ""
        var chapterList: String = ""
        var chapterName: String = ""
        var chapterURL: String = ""
        var content: String = ""
    }

    struct TOCRule: Codable, Hashable {
        var chapterList: String = ""
        var chapterName: String = ""
        var chapterURL: String = ""
    }

    struct ContentRule: Codable, Hashable {
        var content: String = ""
    }
}

// MARK: - 书源搜索结果

struct SearchBookResult: Identifiable, Hashable {
    var id: String { "\(sourceId)-\(bookURL)" }
    var sourceId: UUID
    var sourceName: String
    var name: String
    var author: String
    var coverURL: String
    var intro: String
    var bookURL: String
}

// MARK: - 导入结果

struct ImportOutcome {
    var imported: [Book] = []
    var failed: [(name: String, reason: String)] = []
}
