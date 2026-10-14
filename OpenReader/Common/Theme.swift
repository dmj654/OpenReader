import SwiftUI
import UIKit

/// 阅读页主题（颜色以十六进制存储，便于持久化与跨 UIKit/SwiftUI 使用）
struct ReaderTheme: Identifiable, Codable, Hashable {
    var id: String { name }
    var name: String
    var backgroundHex: UInt32
    var textHex: UInt32
    var secondaryHex: UInt32
    var isDark: Bool

    var backgroundColor: Color {
        Color(red: c(backgroundHex).0, green: c(backgroundHex).1, blue: c(backgroundHex).2)
    }

    var textColor: Color {
        Color(red: c(textHex).0, green: c(textHex).1, blue: c(textHex).2)
    }

    var secondaryColor: Color {
        Color(red: c(secondaryHex).0, green: c(secondaryHex).1, blue: c(secondaryHex).2)
    }

    var uiBackground: UIColor { Self.uiColor(fromHex: backgroundHex) }
    var uiText: UIColor { Self.uiColor(fromHex: textHex) }
    var uiSecondary: UIColor { Self.uiColor(fromHex: secondaryHex) }

    private static func uiColor(fromHex hex: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255.0,
            green: CGFloat((hex >> 8) & 0xFF) / 255.0,
            blue: CGFloat(hex & 0xFF) / 255.0,
            alpha: 1
        )
    }

    private func c(_ hex: UInt32) -> (Double, Double, Double) {
        (
            Double((hex >> 16) & 0xFF) / 255.0,
            Double((hex >> 8) & 0xFF) / 255.0,
            Double(hex & 0xFF) / 255.0
        )
    }

    static let presets: [ReaderTheme] = [
        ReaderTheme(name: "纸白", backgroundHex: 0xFFFFFF, textHex: 0x1C1C1E, secondaryHex: 0x8E8E93, isDark: false),
        ReaderTheme(name: "米黄", backgroundHex: 0xF6EFDD, textHex: 0x3B2F20, secondaryHex: 0x9A8B72, isDark: false),
        ReaderTheme(name: "羊皮", backgroundHex: 0xEADBC0, textHex: 0x4A3620, secondaryHex: 0x9C8360, isDark: false),
        ReaderTheme(name: "护眼", backgroundHex: 0xC7EDCC, textHex: 0x23411F, secondaryHex: 0x6B8F63, isDark: false),
        ReaderTheme(name: "深灰", backgroundHex: 0x2B2B2B, textHex: 0xC9C9C9, secondaryHex: 0x7C7C7C, isDark: true),
        ReaderTheme(name: "夜间", backgroundHex: 0x121212, textHex: 0x9E9E9E, secondaryHex: 0x5C5C5C, isDark: true),
    ]

    static let `default` = presets[1]

    static func matchingSystemColorScheme(_ scheme: ColorScheme) -> ReaderTheme {
        scheme == .dark ? presets[5] : presets[1]
    }
}

/// App 界面色板（区别于阅读页主题）
enum Palette {
    /// 开源阅读（Legado）经典绿 #009688
    static let accent = Color(red: 0.0, green: 0.588, blue: 0.533)
    static let shelfBackground = Color(uiColor: .systemBackground)

    static func coverBackground(for seed: String) -> Color {
        let palette: [Color] = [
            Color(red: 0.24, green: 0.40, blue: 0.58),
            Color(red: 0.55, green: 0.36, blue: 0.28),
            Color(red: 0.24, green: 0.50, blue: 0.44),
            Color(red: 0.48, green: 0.32, blue: 0.52),
            Color(red: 0.60, green: 0.44, blue: 0.22),
            Color(red: 0.30, green: 0.34, blue: 0.62),
            Color(red: 0.36, green: 0.52, blue: 0.30),
            Color(red: 0.52, green: 0.28, blue: 0.36),
        ]
        var hash = 5381
        for byte in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ Int(byte)
            hash &= 0x7FFFFFFF
        }
        return palette[abs(hash) % palette.count]
    }
}
