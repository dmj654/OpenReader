import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var importer: ImportCoordinator
    @ObservedObject private var settings = ReaderSettingsStore.shared

    @State private var storageSize: Int64 = 0
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                readingSection
                storageSection
                helpSection
                aboutSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .toolbarBackground(Palette.accent, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { storageSize = FileStore.occupiedBytes() }
        }
    }

    // MARK: - 阅读

    private var readingSection: some View {
        Section("阅读偏好") {
            Toggle("跟随系统深色模式", isOn: $settings.followSystemDarkMode)
            Toggle("阅读时保持屏幕常亮", isOn: $settings.keepScreenOn)
            Toggle("点击屏幕左右翻页", isOn: $settings.tappableTurnPage)
            Picker("翻页动画", selection: $settings.pageAnimation) {
                ForEach(PageAnimation.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
        }
    }

    // MARK: - 存储

    private var storageSection: some View {
        Section("存储") {
            LabeledContent("书籍总数", value: "\(library.books.count)")
            LabeledContent("已用空间", value: ByteFormatter.string(from: storageSize))
            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("清空解析缓存", systemImage: "trash")
            }
        }
        .confirmationDialog("清空解析缓存？", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("清空缓存（不影响书籍文件）", role: .destructive) {
                FileStore.clearCaches()
                storageSize = FileStore.occupiedBytes()
                Haptics.success()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("下次打开书籍时会重新解析，TXT/EPUB 原文件不受影响。")
        }
    }

    // MARK: - 帮助

    private var helpSection: some View {
        Section("如何添加书籍") {
            VStack(alignment: .leading, spacing: 10) {
                helpRow(
                    index: "1",
                    icon: "plus.circle.fill",
                    title: "书架右上角 +",
                    detail: "从「文件」App 选择 TXT 或 EPUB 文件，支持多选。"
                )
                helpRow(
                    index: "2",
                    icon: "folder.fill",
                    title: "拖进 Import 目录",
                    detail: "「文件」App → OpenReader → Import，把书拖进去，回到书架下拉刷新。"
                )
                helpRow(
                    index: "3",
                    icon: "square.and.arrow.down.fill",
                    title: "用其他 App 打开",
                    detail: "在微信 / 浏览器里选择「用其他应用打开」→ OpenReader。"
                )
            }
            .padding(.vertical, 6)
        }
    }

    private func helpRow(index: String, icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle().fill(Palette.accent.opacity(0.15))
                Text(index).font(.caption.weight(.bold)).foregroundStyle(Palette.accent)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: appVersion)
            LabeledContent("支持格式", value: "TXT · EPUB")
            NavigationLink("开源阅读 · iOS 版") {
                AboutScreen()
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

struct AboutScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "text.book.closed")
                    .font(.system(size: 56))
                    .foregroundStyle(Palette.accent)
                Text("开源阅读")
                    .font(.title2.weight(.semibold))
                Text("一款纯本地的 iOS 阅读器，参考开源项目「阅读」（Legado）的产品形态。\n\n不上传任何数据、不内置任何广告、不请求多余权限。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(5)
                VStack(alignment: .leading, spacing: 10) {
                    feature("本地 TXT / EPUB 阅读，自动识别 GBK 等编码")
                    feature("智能章节切分与 CoreText 精确分页")
                    feature("六套主题、字体行距边距全自定义")
                    feature("书签、划线、书内全文搜索")
                    feature("系统语音朗读，支持后台播放")
                    feature("网络书源（Legado 规则子集），可导入书源 JSON")
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardBackground()
            }
            .padding(24)
        }
        .background(Palette.shelfBackground)
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func feature(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(Palette.accent)
                .padding(.top, 2)
            Text(text)
                .font(.subheadline)
        }
    }
}
