import Foundation

/// 集中管理 App 的磁盘路径。
///
/// 目录结构（Application Support，对用户不可见，避免污染“文件”App）：
/// ```
/// OpenReader/
///   library.json      书架索引
///   sources.json      书源
///   bookmarks.json    书签与划线
///   progress.json     阅读进度
///   Books/            原始文件
///   Cache/            解析后的章节缓存
///   Covers/           封面
/// ```
/// 同时在 Documents/Import 提供一个“投递箱”，用户可直接从“文件”App 拖书进去。
enum FileStore {
    static let fileManager = FileManager.default

    static var applicationSupport: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("OpenReader", isDirectory: true)
        ensure(url)
        return url
    }

    static var documents: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    /// 用户可见的导入投递箱：Documents/Import
    static var importInbox: URL {
        let url = documents.appendingPathComponent("Import", isDirectory: true)
        ensure(url)
        return url
    }

    static var libraryFile: URL { applicationSupport.appendingPathComponent("library.json") }
    static var sourcesFile: URL { applicationSupport.appendingPathComponent("sources.json") }
    static var bookmarksFile: URL { applicationSupport.appendingPathComponent("bookmarks.json") }
    static var progressFile: URL { applicationSupport.appendingPathComponent("progress.json") }

    static var booksDirectory: URL { subdirectory("Books") }
    static var cacheDirectory: URL { subdirectory("Cache") }
    static var coversDirectory: URL { subdirectory("Covers") }

    /// 某本书的章节缓存文件
    static func chaptersFile(for bookId: UUID) -> URL {
        cacheDirectory.appendingPathComponent(bookId.uuidString + ".chapters.json")
    }

    /// 某本书解出的图片目录（EPUB）
    static func imagesDirectory(for bookId: UUID) -> URL {
        subdirectory("Cache/Images/\(bookId.uuidString)")
    }

    static func bookURL(for book: Book) -> URL {
        booksDirectory.appendingPathComponent(book.fileName)
    }

    static func coverURL(for book: Book) -> URL? {
        guard let name = book.coverFileName else { return nil }
        let url = coversDirectory.appendingPathComponent(name)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    static func removeBookArtifacts(for bookId: UUID) {
        let targets = [
            chaptersFile(for: bookId),
            imagesDirectory(for: bookId),
        ]
        for url in targets {
            try? fileManager.removeItem(at: url)
        }
    }

    static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(type, from: data)
        } catch {
            NSLog("OpenReader: 读取 %@ 失败 - %@", url.lastPathComponent, error.localizedDescription)
            return nil
        }
    }

    static func occupiedBytes() -> Int64 {
        var total: Int64 = 0
        for url in [booksDirectory, cacheDirectory, coversDirectory] {
            guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { continue }
            for case let file as URL in enumerator {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    total += Int64(size)
                }
            }
        }
        return total
    }

    static func clearCaches() {
        if let items = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for item in items { try? fileManager.removeItem(at: item) }
        }
    }

    // MARK: - Private

    private static func subdirectory(_ name: String) -> URL {
        ensure(applicationSupport.appendingPathComponent(name, isDirectory: true))
        return applicationSupport.appendingPathComponent(name, isDirectory: true)
    }

    private static func ensure(_ url: URL) {
        if !fileManager.fileExists(atPath: url.path) {
            try? fileManager.createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
        }
    }
}
