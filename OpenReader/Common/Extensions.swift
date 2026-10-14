import SwiftUI
import UIKit

// MARK: - 触觉反馈

enum Haptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }
}

// MARK: - 字符串

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 去掉首尾空白 + 把内部连续空行压缩成单个换行，用于章节标题展示
    var condensedWhitespace: String {
        replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression, range: startIndex..<endIndex).trimmed
    }

    func truncating(to length: Int) -> String {
        count <= length ? self : String(prefix(length)) + "…"
    }

    /// 估算显示宽度（中文按 2 计），仅用于粗排
    var displayWidth: Int {
        reduce(0) { partial, character in
            let wide = character.unicodeScalars.first.map { $0.value > 0x2E7F } ?? false
            return partial + (wide ? 2 : 1)
        }
    }
}

// MARK: - 日期

extension Date {
    var shortString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: self)
    }

    var timeString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }
}

// MARK: - 字节格式化

enum ByteFormatter {
    static func string(from bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - 视图辅助

extension View {
    /// 隐藏键盘的统一入口
    @MainActor
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func cardBackground(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

// MARK: - 通知名

extension Notification.Name {
    static let openReaderFileImported = Notification.Name("OpenReader.fileImported")
}
