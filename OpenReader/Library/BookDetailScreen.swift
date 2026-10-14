import SwiftUI

struct BookDetailScreen: View {
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let book: Book

    @State private var showDeleteConfirm = false

    private var progress: ReadingProgress? {
        library.progress(for: book.id)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statsGrid
                if !book.intro.isEmpty { introSection }
                actionSection
            }
            .padding(20)
        }
        .background(Palette.shelfBackground)
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 18) {
            CoverView(book: book)
                .frame(width: 110, height: 152)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)

            VStack(alignment: .leading, spacing: 10) {
                Text(book.title)
                    .font(.title3.weight(.semibold))
                    .lineLimit(3)
                if !book.author.isEmpty {
                    Label(book.author, systemImage: "person")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    tag(book.format.displayName)
                    tag(book.group)
                    if book.isPinned { tag("已置顶") }
                }
                Text(book.lastReadDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .cardBackground()
        .padding(16)
    }

    private var statsGrid: some View {
        HStack(spacing: 12) {
            statCard("章节", "\(book.chapterCount)")
            statCard("字数", compactCount(book.characterCount))
            statCard("阅读", readingDuration)
            statCard("进度", progressText)
        }
    }

    private var introSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("简介")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(book.intro)
                .font(.subheadline)
                .lineSpacing(5)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardBackground()
        .padding(16)
    }

    private var actionSection: some View {
        VStack(spacing: 12) {
            NavigationLink(value: ReaderRoute.reader(book.id)) {
                Label(progress == nil ? "开始阅读" : "继续阅读", systemImage: "book.fill")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)

            HStack(spacing: 12) {
                Button {
                    library.setPinned(book, pinned: !book.isPinned)
                } label: {
                    Label(book.isPinned ? "取消置顶" : "置顶", systemImage: "pin")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("删除", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
            }
        }
        .confirmationDialog(
            "删除《\(book.title)》？",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("删除书籍与阅读记录", role: .destructive) {
                library.remove(book)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作不可恢复。")
        }
    }

    // MARK: - 小组件

    private func tag(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(Color.secondary.opacity(0.14)))
            .foregroundStyle(.secondary)
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .cardBackground(cornerRadius: 12)
    }

    private var readingDuration: String {
        let seconds = progress?.totalReadingSeconds ?? 0
        if seconds < 60 { return "0 分钟" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟" }
        return String(format: "%.1f 小时", Double(minutes) / 60)
    }

    private var progressText: String {
        guard let progress else { return "—" }
        return String(format: "%.0f%%", progress.percent * 100)
    }

    private func compactCount(_ count: Int) -> String {
        if count >= 10_000 {
            return String(format: "%.1f 万", Double(count) / 10_000)
        }
        return "\(count)"
    }
}
