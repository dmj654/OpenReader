import SwiftUI
import UIKit
import UniformTypeIdentifiers

// MARK: - 书源列表

struct BookSourceListScreen: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var showImportSheet = false
    @State private var showSearch = false

    var body: some View {
        NavigationStack {
            Group {
                if library.sources.isEmpty {
                    emptyState
                } else {
                    sourceList
                }
            }
            .background(Palette.shelfBackground)
            .navigationTitle("书源")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Palette.accent, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .navigationDestination(isPresented: $showSearch) {
                NetworkSearchScreen()
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("用书源搜书")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImportSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入书源")
                }
            }
        }
        .sheet(isPresented: $showImportSheet) {
            SourceImportSheet()
        }
    }

    private var sourceList: some View {
        List {
            Section {
                ForEach(library.sources) { source in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.sourceName)
                                .font(.subheadline.weight(.medium))
                                .lineLimit(1)
                            Text(source.sourceURL)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { source.enabled },
                            set: { _ in library.toggleSource(source) }
                        ))
                        .labelsHidden()
                        .accessibilityLabel("启用 \(source.sourceName)")
                    }
                    .contentShape(Rectangle())
                }
                .onDelete { indexSet in
                    let sources = library.sources
                    for index in indexSet where sources.indices.contains(index) {
                        library.removeSource(sources[index])
                    }
                }
            } header: {
                Text("已导入 \(library.sources.count) 个书源，其中 \(library.enabledSources.count) 个已启用")
            } footer: {
                Text("书源来自社区，质量参差不齐。搜索时会同时请求前 12 个启用的书源，建议只保留几个好用的。")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("还没有书源")
                .font(.title3.weight(.medium))
            Text("书源是描述「从哪个网站抓取搜索结果、目录和正文」的一组规则，兼容开源阅读（Legado）格式的 JSON。\n\n点击右上角 + 粘贴书源 JSON，或从文件导入。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button {
                showImportSheet = true
            } label: {
                Label("导入书源 JSON", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 书源导入

struct SourceImportSheet: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @State private var jsonText = ""
    @State private var showFileImporter = false
    @State private var statusMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                Text("粘贴书源 JSON（支持数组或单个对象）")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextEditor(text: $jsonText)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 200)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.secondary.opacity(0.25))
                    )

                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    showFileImporter = true
                } label: {
                    Label("从文件导入", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)

                Spacer()
            }
            .padding(20)
            .navigationTitle("导入书源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("导入") { importJSON() }
                        .disabled(jsonText.trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.json, .text, .plainText, .data],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                do {
                    if url.startAccessingSecurityScopedResource() {
                        defer { url.stopAccessingSecurityScopedResource() }
                        jsonText = String(data: try Data(contentsOf: url), encoding: .utf8) ?? ""
                    }
                } catch {
                    statusMessage = "读取文件失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func importJSON() {
        let data = Data(jsonText.trimmed.utf8)
        let sources = BookSourceEngine.parseSources(from: data)
        if sources.isEmpty {
            statusMessage = "没有解析到有效的书源，请确认 JSON 格式。"
            Haptics.warning()
        } else {
            library.replaceSources(sources)
            statusMessage = "已导入 / 更新 \(sources.count) 个书源。"
            Haptics.success()
            jsonText = ""
        }
    }
}

// MARK: - 网络搜书

struct NetworkSearchScreen: View {
    @EnvironmentObject private var library: LibraryStore

    @State private var keyword = ""
    @State private var results: [SearchBookResult] = []
    @State private var isSearching = false
    @State private var statusText = ""
    @State private var loadingBook: SearchBookResult?
    @State private var activeBook: Book?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if !statusText.isEmpty {
                Section {
                    Label(statusText, systemImage: isSearching ? "antenna.radiowaves.left.and.right" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if results.isEmpty && !isSearching {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 32))
                            .foregroundStyle(.secondary)
                        Text(library.enabledSources.isEmpty ? "请先导入并启用书源" : "输入书名或作者开始搜索")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                }
            }

            Section("搜索结果 · \(results.count)") {
                ForEach(results) { result in
                    Button {
                        openResult(result)
                    } label: {
                        HStack(spacing: 12) {
                            RemoteCover(url: result.coverURL, title: result.name)
                                .frame(width: 46, height: 64)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(result.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(result.author.isEmpty ? result.sourceName : "\(result.author) · \(result.sourceName)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                if !result.intro.isEmpty {
                                    Text(result.intro)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if loadingBook?.id == result.id {
                                ProgressView()
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(loadingBook != nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("网络搜书")
        .searchable(text: $keyword, prompt: "书名 / 作者")
        .onSubmit(of: .search) { startSearch() }
        .fullScreenCover(item: $activeBook) { book in
            ReaderScreen(book: book, library: library)
        }
        .alert(
            "打开失败",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("好的", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func startSearch() {
        let query = keyword.trimmed
        guard !query.isEmpty else { return }
        let sources = library.enabledSources
        guard !sources.isEmpty else {
            statusText = "没有可用的书源，请先在「书源」页导入。"
            return
        }

        isSearching = true
        results = []
        statusText = "正在搜索 \(min(sources.count, 12)) 个书源…"

        Task { @MainActor in
            let found = await BookSourceEngine.searchAll(keyword: query, sources: sources) { name in
                statusText = "正在搜索：\(name)"
            }
            results = found.sorted { $0.name.count < $1.name.count }
            isSearching = false
            statusText = found.isEmpty ? "没有搜到结果，试试换个书源或关键词。" : "共找到 \(found.count) 个结果"
        }
    }

    private func openResult(_ result: SearchBookResult) {
        guard let source = library.source(withId: result.sourceId) else { return }
        loadingBook = result

        Task { @MainActor in
            defer { loadingBook = nil }
            do {
                var book = try await BookSourceEngine.fetchBookInfo(source: source, bookURL: result.bookURL)
                let chapters = try await BookSourceEngine.fetchTOC(source: source, bookURL: result.bookURL)
                BookImporter.persistChapters(chapters, for: book.id)
                book.chapterCount = chapters.count
                library.upsert(book)
                Haptics.success()
                activeBook = book
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - 远程封面

struct RemoteCover: View {
    let url: String
    let title: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Palette.coverBackground(for: title))
                    .overlay(
                        Text(title.truncating(to: 6))
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(4)
                    )
            }
        }
        .task(id: url) {
            guard !url.isEmpty, let remote = URL(string: url) else { return }
            let key = url as NSString
            if let cached = CoverCache.cache.object(forKey: key) {
                image = cached
                return
            }
            guard let data = try? await BookSourceEngine.fetchImage(remote),
                  let loaded = UIImage(data: data) else { return }
            CoverCache.cache.setObject(loaded, forKey: key)
            image = loaded
        }
    }
}
