import SwiftUI
import UniformTypeIdentifiers

// MARK: - 路由

enum ReaderRoute: Hashable {
    case reader(UUID)
    case detail(UUID)
}

// MARK: - 根视图

struct RootView: View {
    var body: some View {
        TabView {
            BookshelfScreen()
                .tabItem { Label("书架", systemImage: "books.vertical.fill") }
            BookSourceListScreen()
                .tabItem { Label("书源", systemImage: "dot.radiowaves.left.and.right") }
            SettingsScreen()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(Palette.accent)
    }
}

// MARK: - 书架

struct BookshelfScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var importer: ImportCoordinator

    @State private var query = ""
    @State private var isGrid = true
    @State private var showImporter = false
    @State private var showSearch = false
    @State private var groupFilter: String?
    @State private var pendingDelete: Book?
    @State private var detailBook: Book?

    private static let supportedTypes: [UTType] = [.plainText, .text, .epub, .data]

    private var filteredBooks: [Book] {
        var result = library.books
        if let group = groupFilter {
            result = result.filter { $0.group == group }
        }
        let keyword = query.trimmed
        if !keyword.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(keyword) ||
                    $0.author.localizedCaseInsensitiveContains(keyword)
            }
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if library.books.isEmpty {
                    emptyState
                } else if isGrid {
                    gridView
                } else {
                    listView
                }
            }
            .background(Palette.shelfBackground)
            .navigationTitle("书架")
            .searchable(text: $query, prompt: "搜索书名或作者")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(isGrid ? "列表视图" : "网格视图") { isGrid.toggle() }
                        Button {
                            showSearch = true
                        } label: {
                            Label("用书源搜书", systemImage: "magnifyingglass")
                        }
                        Picker("分组", selection: Binding(
                            get: { groupFilter ?? "全部" },
                            set: { groupFilter = $0 == "全部" ? nil : $0 }
                        )) {
                            Text("全部分组").tag("全部")
                            ForEach(library.groups, id: \.self) { group in
                                Text(group).tag(group)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("筛选")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("导入书籍")
                }
            }
            .navigationDestination(for: ReaderRoute.self) { route in
                destination(for: route)
            }
            .navigationDestination(isPresented: Binding(
                get: { detailBook != nil },
                set: { if !$0 { detailBook = nil } }
            )) {
                if let detailBook {
                    BookDetailScreen(book: detailBook)
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: Self.supportedTypes,
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    Task { await importer.importURLs(urls, into: library) }
                }
            }
            .alert(
                "导入完成",
                isPresented: $importer.showOutcome,
                actions: { Button("好的", role: .cancel) {} },
                message: { Text(importOutcomeText) }
            )
            .confirmationDialog(
                "删除《\(pendingDelete?.title ?? "")》？",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("删除书籍与阅读记录", role: .destructive) {
                    if let book = pendingDelete { library.remove(book) }
                    pendingDelete = nil
                }
                Button("取消", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("此操作不可恢复。")
            }
        }
    }

    @ViewBuilder
    private func destination(for route: ReaderRoute) -> some View {
        switch route {
        case .reader(let id):
            if let book = library.book(withId: id) {
                ReaderScreen(book: book, library: library)
            }
        case .detail(let id):
            if let book = library.book(withId: id) {
                BookDetailScreen(book: book)
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "books.vertical")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            Text("书架还是空的")
                .font(.title3.weight(.medium))
            Text("两种方式添加书籍：\n1. 点右上角 + 从「文件」App 选择 TXT / EPUB\n2. 把文件拖进「文件」App 里的 OpenReader/Import 目录")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button {
                showImporter = true
            } label: {
                Label("导入本地书籍", systemImage: "square.and.arrow.down")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 网格

    private var gridView: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 104, maximum: 140), spacing: 16)],
                spacing: 20
            ) {
                ForEach(filteredBooks) { book in
                    NavigationLink(value: ReaderRoute.reader(book.id)) {
                        BookCell(book: book, progress: library.progress(for: book.id))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { bookMenu(book) }
                }
            }
            .padding(16)
        }
        .refreshable {
            await importer.scanInbox(into: library)
        }
    }

    // MARK: - 列表

    private var listView: some View {
        List {
            ForEach(filteredBooks) { book in
                NavigationLink(value: ReaderRoute.reader(book.id)) {
                    BookRow(book: book, progress: library.progress(for: book.id))
                }
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDelete = book
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button {
                        library.setPinned(book, pinned: !book.isPinned)
                    } label: {
                        Label(book.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                    }
                    .tint(.orange)
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await importer.scanInbox(into: library)
        }
    }

    // MARK: - 右键菜单

    @ViewBuilder
    private func bookMenu(_ book: Book) -> some View {
        Button {
            library.setPinned(book, pinned: !book.isPinned)
        } label: {
            Label(book.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
        }
        Button {
            detailBook = book
        } label: {
            Label("书籍详情", systemImage: "info.circle")
        }
        Menu("移动到分组") {
            ForEach(library.groups, id: \.self) { group in
                Button(group) { library.move(book, toGroup: group) }
            }
        }
        Divider()
        Button(role: .destructive) {
            pendingDelete = book
        } label: {
            Label("删除", systemImage: "trash")
        }
    }

    private var importOutcomeText: String {
        let outcome = importer.lastOutcome
        var lines: [String] = []
        if !outcome.imported.isEmpty {
            lines.append("成功导入 \(outcome.imported.count) 本：\n" + outcome.imported.map { "· \($0.title)" }.joined(separator: "\n"))
        }
        for failure in outcome.failed {
            lines.append("失败：\(failure.name) — \(failure.reason)")
        }
        return lines.isEmpty ? "没有可识别的文件" : lines.joined(separator: "\n\n")
    }
}

// MARK: - 网格单元

struct BookCell: View {
    let book: Book
    let progress: ReadingProgress?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(book: book)
                .aspectRatio(0.72, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if book.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.white)
                            .padding(5)
                            .background(Circle().fill(.orange.opacity(0.9)))
                            .padding(5)
                    }
                }
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)

            Text(book.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(progressText)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("《\(book.title)》 \(progressText)")
    }

    private var progressText: String {
        guard let progress else { return book.format.displayName + " · 未读" }
        return String(format: "%.0f%%", progress.percent * 100)
    }
}

// MARK: - 列表行

struct BookRow: View {
    let book: Book
    let progress: ReadingProgress?

    var body: some View {
        HStack(spacing: 14) {
            CoverView(book: book)
                .frame(width: 52, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 3, y: 2)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if book.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    Text(book.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                }
                Text(book.author.isEmpty ? book.lastReadDescription : book.author)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let progress {
                    ProgressView(value: progress.percent)
                        .tint(Palette.accent)
                        .frame(height: 3)
                }
            }

            Spacer(minLength: 0)

            Text(book.format.displayName)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 封面

enum CoverCache {
    static let cache = NSCache<NSString, UIImage>()
}

struct CoverView: View {
    let book: Book
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Palette.coverBackground(for: book.title))
                    .overlay(
                        VStack(spacing: 6) {
                            Text(book.title.truncating(to: 12))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                            if !book.author.isEmpty {
                                Text(book.author.truncating(to: 8))
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.8))
                            }
                        }
                        .padding(10)
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: book.coverFileName) {
            guard let name = book.coverFileName else { return }
            if let cached = CoverCache.cache.object(forKey: name as NSString) {
                image = cached
                return
            }
            let url = FileStore.coversDirectory.appendingPathComponent(name)
            guard let loaded = UIImage(contentsOfFile: url.path) else { return }
            CoverCache.cache.setObject(loaded, forKey: name as NSString)
            image = loaded
        }
    }
}
