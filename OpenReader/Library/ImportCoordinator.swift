import SwiftUI
import UniformTypeIdentifiers

/// 负责把外部文件变成书架里的书，并管理「Import 投递箱」扫描。
@MainActor
final class ImportCoordinator: ObservableObject {
    @Published var isImporting = false
    @Published var showOutcome = false
    private(set) var lastOutcome = ImportOutcome()

    static let supportedExtensions: Set<String> = ["txt", "text", "epub"]

    func importURLs(_ urls: [URL], into library: LibraryStore) async {
        guard !urls.isEmpty else { return }
        isImporting = true
        defer { isImporting = false }

        var outcome = ImportOutcome()

        for url in urls {
            let ext = url.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else {
                outcome.failed.append((url.lastPathComponent, "仅支持 TXT / EPUB"))
                continue
            }

            // 同一来源文件只导入一次
            let sourceName = url.lastPathComponent
            if library.books.contains(where: { !$0.sourceName.isEmpty && $0.sourceName == sourceName }) {
                continue
            }

            do {
                let book = try await BookImporter.importBook(at: url)
                library.upsert(book)
                outcome.imported.append(book)
            } catch {
                outcome.failed.append((url.lastPathComponent, error.localizedDescription))
            }
        }

        lastOutcome = outcome
        if !outcome.imported.isEmpty {
            Haptics.success()
            showOutcome = true
        } else if !outcome.failed.isEmpty {
            Haptics.warning()
            showOutcome = true
        }
    }

    /// 扫描 Documents/Import 投递箱（用户可直接把文件拖进去）
    func scanInbox(into library: LibraryStore) async {
        let inbox = FileStore.importInbox
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let candidates = items.filter {
            Self.supportedExtensions.contains($0.pathExtension.lowercased())
        }
        guard !candidates.isEmpty else { return }

        await importURLs(candidates, into: library)
    }
}
