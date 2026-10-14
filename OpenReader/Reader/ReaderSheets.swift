import SwiftUI

// MARK: - 目录

struct ChapterListSheet: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var descending = false

    private var theme: ReaderTheme { viewModel.resolvedTheme }

    private var filtered: [(index: Int, chapter: Chapter)] {
        let enumerated = viewModel.engine.chapters.enumerated().map { (index: $0.offset, chapter: $0.element) }
        let keyword = query.trimmed
        let matched = keyword.isEmpty ? enumerated : enumerated.filter { $0.chapter.title.contains(keyword) }
        return descending ? Array(matched.reversed()) : matched
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.index) { item in
                Button {
                    viewModel.jump(toChapter: item.index)
                    dismiss()
                } label: {
                    HStack {
                        Text(item.chapter.title.isEmpty ? "第 \(item.index + 1) 章" : item.chapter.title)
                            .font(.subheadline)
                            .foregroundStyle(item.index == viewModel.location.chapter ? Color.accentColor : .primary)
                            .lineLimit(1)
                        Spacer()
                        Text("\(item.chapter.characterCount) 字")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜索章节")
            .navigationTitle("目录 · \(viewModel.engine.chapters.count) 章")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(descending ? "正序" : "倒序") { descending.toggle() }
                        .font(.subheadline)
                }
            }
        }
        .presentationDetents([.large, .medium])
        .preferredColorScheme(theme.isDark ? .dark : .light)
    }
}

// MARK: - 阅读设置

struct ReaderSettingsSheet: View {
    @ObservedObject var viewModel: ReaderViewModel
    @ObservedObject private var settings = ReaderSettingsStore.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    themeSection
                    typographySection
                    layoutSection
                    behaviorSection
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("阅读设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var themeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("背景主题")
            HStack(spacing: 12) {
                ForEach(Array(ReaderTheme.presets.enumerated()), id: \.element.id) { index, theme in
                    Button {
                        settings.themeIndex = index
                        settings.followSystemDarkMode = false
                        Haptics.selection()
                    } label: {
                        VStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(theme.backgroundColor)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(
                                            settings.themeIndex == index ? Color.accentColor : Color.secondary.opacity(0.35),
                                            lineWidth: settings.themeIndex == index ? 2.5 : 1
                                        )
                                )
                                .frame(height: 44)
                                .overlay(
                                    Text("文")
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(theme.textColor)
                                )
                            Text(theme.name)
                                .font(.caption2)
                                .foregroundStyle(settings.themeIndex == index ? Color.accentColor : .secondary)
                        }
                    }
                    .accessibilityLabel("主题 \(theme.name)")
                }
            }
        }
        .cardBackground()
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
    }

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("字体与排版")

            VStack(alignment: .leading, spacing: 6) {
                valueRow("字号", String(format: "%.0f pt", settings.fontSize))
                Slider(value: $settings.fontSize, in: 12...36, step: 1)
                    .accessibilityLabel("字号")
            }

            VStack(alignment: .leading, spacing: 6) {
                valueRow("行距", String(format: "%.0f", settings.lineSpacing))
                Slider(value: $settings.lineSpacing, in: 0...16, step: 1)
                    .accessibilityLabel("行距")
            }

            VStack(alignment: .leading, spacing: 6) {
                valueRow("段距", String(format: "%.0f", settings.paragraphSpacing))
                Slider(value: $settings.paragraphSpacing, in: 0...32, step: 2)
                    .accessibilityLabel("段距")
            }

            Picker("字体", selection: $settings.fontFamily) {
                ForEach(ReaderSettingsStore.fontOptions, id: \.key) { option in
                    Text(option.label).tag(option.key)
                }
            }
            .pickerStyle(.menu)

            Toggle("首行缩进两格", isOn: $settings.firstLineIndent)
                .font(.subheadline)
        }
        .cardBackground()
        .padding(16)
    }

    private var layoutSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("版面")

            VStack(alignment: .leading, spacing: 6) {
                valueRow("左右边距", String(format: "%.0f pt", settings.horizontalMargin))
                Slider(value: $settings.horizontalMargin, in: 8...56, step: 2)
                    .accessibilityLabel("左右边距")
            }

            VStack(alignment: .leading, spacing: 6) {
                valueRow("上下边距", String(format: "%.0f pt", settings.verticalMargin))
                Slider(value: $settings.verticalMargin, in: 8...96, step: 2)
                    .accessibilityLabel("上下边距")
            }

            Picker("翻页动画", selection: $settings.pageAnimation) {
                ForEach(PageAnimation.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
        }
        .cardBackground()
        .padding(16)
    }

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("行为")

            Toggle("点击左右翻页", isOn: $settings.tappableTurnPage)
                .font(.subheadline)

            Toggle("阅读时保持屏幕常亮", isOn: $settings.keepScreenOn)
                .font(.subheadline)

            Toggle("跟随系统深色模式", isOn: $settings.followSystemDarkMode)
                .font(.subheadline)

            VStack(alignment: .leading, spacing: 6) {
                valueRow("朗读语速", String(format: "%.0f%%", settings.speechRate * 100))
                Slider(value: $settings.speechRate, in: 0...1, step: 0.05)
                    .accessibilityLabel("朗读语速")
            }

            VStack(alignment: .leading, spacing: 6) {
                valueRow("朗读音调", String(format: "%.1f", settings.speechPitch))
                Slider(value: $settings.speechPitch, in: 0.5...2.0, step: 0.1)
                    .accessibilityLabel("朗读音调")
            }
        }
        .cardBackground()
        .padding(16)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func valueRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.subheadline)
            Spacer()
            Text(value).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 书签

struct BookmarkSheet: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var library: LibraryStore

    private var bookmarks: [Bookmark] {
        library.bookmarks(for: viewModel.book.id)
    }

    var body: some View {
        NavigationStack {
            Group {
                if bookmarks.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("书签与划线")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .medium])
    }

    private var list: some View {
        List {
            ForEach(bookmarks) { bookmark in
                Button {
                    viewModel.jump(toCharacterOffset: bookmark.characterOffset, inChapter: bookmark.chapterIndex)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(bookmark.text.isEmpty ? "第 \(bookmark.chapterIndex + 1) 章" : bookmark.text)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                        HStack(spacing: 8) {
                            Image(systemName: bookmark.kind == .bookmark ? "bookmark.fill" : "highlighter")
                                .font(.caption2)
                            Text("第 \(bookmark.chapterIndex + 1) 章 · \(bookmark.createdAt.shortString)")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let target = bookmarks[index]
                    library.removeBookmark(target)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bookmark")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("还没有书签")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("阅读时点击底部「加书签」即可记录当前进度")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 书内搜索

struct InBookSearchSheet: View {
    @ObservedObject var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var fieldFocused: Bool

    @State private var keyword = ""
    @State private var results: [SearchHit] = []
    @State private var isSearching = false

    struct SearchHit: Identifiable {
        var id: Int
        var chapterIndex: Int
        var chapterTitle: String
        var snippet: String
        var offset: Int
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    emptyState
                } else {
                    resultList
                }
            }
            .navigationTitle("书内搜索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .medium])
        .searchable(text: $keyword, prompt: "输入关键词")
        .onSubmit(of: .search) { runSearch() }
    }

    private var resultList: some View {
        List(results) { hit in
            Button {
                viewModel.jump(toCharacterOffset: hit.offset, inChapter: hit.chapterIndex)
                dismiss()
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hit.chapterTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(highlighted(hit.snippet))
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .lineLimit(3)
                }
                .contentShape(Rectangle())
            }
            .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        }
        .listStyle(.insetGrouped)
    }

    private func highlighted(_ text: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: keyword) {
            attributed[range].backgroundColor = .yellow.opacity(0.45)
        }
        return attributed
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("在整本书中查找关键词")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func runSearch() {
        let query = keyword.trimmed
        guard !query.isEmpty else { return }
        fieldFocused = false
        isSearching = true

        Task { @MainActor in
            let chapters = viewModel.engine.chapters
            var hits: [SearchHit] = []
            for (index, chapter) in chapters.enumerated() {
                let plain = chapter.isHTML ? EpubParser.stripTags(chapter.content) : chapter.content
                var searchRange = plain.startIndex..<plain.endIndex
                var guardCounter = 0
                while guardCounter < 40 {
                    guardCounter += 1
                    guard let found = plain.range(of: query, options: .caseInsensitive, range: searchRange) else { break }
                    let offset = plain.distance(from: plain.startIndex, to: found.lowerBound)
                    let snippetStart = plain.index(found.lowerBound, offsetBy: -30, limitedBy: plain.startIndex) ?? plain.startIndex
                    let snippetEnd = plain.index(found.upperBound, offsetBy: 60, limitedBy: plain.endIndex) ?? plain.endIndex
                    let snippet = String(plain[snippetStart..<snippetEnd]).condensedWhitespace
                    hits.append(
                        SearchHit(
                            id: index * 1000 + hits.count,
                            chapterIndex: index,
                            chapterTitle: chapter.title.isEmpty ? "第 \(index + 1) 章" : chapter.title,
                            snippet: snippet.truncating(to: 120),
                            offset: offset
                        )
                    )
                    searchRange = found.upperBound..<plain.endIndex
                    if hits.count >= 120 { break }
                }
                if hits.count >= 120 { break }
            }
            results = hits
            isSearching = false
        }
    }
}
