import SwiftUI
import UIKit

/// 阅读主界面：翻页容器 + 可隐藏菜单 + 各功能面板。
struct ReaderScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @ObservedObject private var settings = ReaderSettingsStore.shared
    @StateObject private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss

    init(book: Book, library: LibraryStore) {
        _viewModel = StateObject(wrappedValue: ReaderViewModel(book: book, library: library))
    }

    private var theme: ReaderTheme {
        viewModel.resolvedTheme
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                theme.backgroundColor.ignoresSafeArea()

                if viewModel.pageSize == size, size.width > 0 {
                    ReaderPagerView(viewModel: viewModel)
                        .id(pagerIdentity(for: size))
                }

                if viewModel.isLoading {
                    ProgressView()
                        .tint(theme.textColor)
                }

                if viewModel.menuVisible {
                    menuOverlay
                }

                if let toast = viewModel.toastMessage {
                    toastView(toast)
                }
            }
            .onAppear {
                viewModel.updatePageSize(size)
            }
            .onChange(of: size) { newSize in
                viewModel.updatePageSize(newSize)
            }
        }
        .onAppear {
            viewModel.startReadingSession()
            if settings.keepScreenOn {
                UIApplication.shared.isIdleTimerDisabled = true
            }
        }
        .onDisappear {
            viewModel.endReadingSession()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $viewModel.activeSheet) { sheet in
            sheetContent(for: sheet)
        }
        .alert(
            "加载失败",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func pagerIdentity(for size: CGSize) -> String {
        "\(settings.pageAnimation.rawValue)|\(Int(size.width))x\(Int(size.height))|\(viewModel.chaptersRevision)"
    }

    // MARK: - 菜单

    private var menuOverlay: some View {
        ZStack {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture { viewModel.menuVisible = false }

            VStack(spacing: 0) {
                topBar
                Spacer()
                bottomPanel
            }
        }
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: viewModel.menuVisible)
    }

    private var barBackground: some View {
        theme.backgroundColor.opacity(0.96)
    }

    private var topBar: some View {
        HStack(spacing: 20) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.textColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("返回书架")

            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.currentChapterTitle.isEmpty ? viewModel.book.title : viewModel.currentChapterTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(theme.textColor)
                    .lineLimit(1)
                Text(viewModel.locationDescription)
                    .font(.caption2)
                    .foregroundStyle(theme.secondaryColor)
            }

            Spacer()

            Button {
                viewModel.activeSheet = .bookmarks
            } label: {
                Image(systemName: "bookmark")
                    .font(.system(size: 17))
                    .foregroundStyle(theme.textColor)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("书签列表")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(barBackground)
    }

    private var bottomPanel: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Button("上一章") {
                    let index = max(0, viewModel.location.chapter - 1)
                    if index != viewModel.location.chapter { viewModel.jump(toChapter: index) }
                }
                .font(.caption)
                .foregroundStyle(theme.textColor)

                Slider(
                    value: Binding(
                        get: { viewModel.sliderValue },
                        set: { viewModel.sliderValue = $0 }
                    ),
                    in: 0...1
                ) { editing in
                    if !editing {
                        viewModel.commitSlider()
                        Haptics.light()
                    }
                }
                .tint(theme.textColor)
                .accessibilityLabel("阅读进度")
                .accessibilityValue("\(Int(viewModel.sliderValue * 100))%")

                Button("下一章") {
                    let total = viewModel.engine.chapters.count
                    let index = min(max(0, total - 1), viewModel.location.chapter + 1)
                    if index != viewModel.location.chapter { viewModel.jump(toChapter: index) }
                }
                .font(.caption)
                .foregroundStyle(theme.textColor)
            }

            HStack {
                toolButton("list.bullet", "目录") { viewModel.activeSheet = .chapterList }
                toolButton("textformat.size", "设置") { viewModel.activeSheet = .settings }
                toolButton("bookmark", "加书签") { viewModel.toggleBookmark() }
                toolButton("magnifyingglass", "搜索") { viewModel.activeSheet = .search }
                toolButton(
                    viewModel.isSpeaking ? "pause.circle" : "speaker.wave.2",
                    viewModel.isSpeaking ? "暂停朗读" : "开始朗读"
                ) {
                    viewModel.toggleSpeech()
                }
                toolButton(
                    settings.theme.isDark ? "sun.max" : "moon",
                    settings.theme.isDark ? "日间模式" : "夜间模式"
                ) {
                    viewModel.toggleNightMode()
                }
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .background(barBackground)
    }

    private func toolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 19))
                Text(label)
                    .font(.caption2)
            }
            .foregroundStyle(theme.textColor)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func toastView(_ message: String) -> some View {
        VStack {
            Spacer()
            Text(message)
                .font(.footnote)
                .foregroundStyle(theme.textColor)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(theme.backgroundColor.opacity(0.95))
                        .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                )
                .padding(.bottom, 96)
        }
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: - 面板

    @ViewBuilder
    private func sheetContent(for sheet: ReaderViewModel.ActiveSheet) -> some View {
        switch sheet {
        case .chapterList:
            ChapterListSheet(viewModel: viewModel)
        case .settings:
            ReaderSettingsSheet(viewModel: viewModel)
        case .bookmarks:
            BookmarkSheet(viewModel: viewModel)
        case .search:
            InBookSearchSheet(viewModel: viewModel)
        }
    }
}
