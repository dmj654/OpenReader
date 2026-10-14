import Combine
import SwiftUI
import UIKit

enum PageAnimation: String, Codable, CaseIterable, Identifiable {
    case slide
    case curl

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .slide: return "平移"
        case .curl: return "仿真翻页"
        }
    }

    var uiTransitionStyle: UIPageViewController.TransitionStyle {
        switch self {
        case .slide: return .scroll
        case .curl: return .pageCurl
        }
    }
}

/// 阅读器排版与行为设置，全部即时持久化。
@MainActor
final class ReaderSettingsStore: ObservableObject {
    static let shared = ReaderSettingsStore()

    @Published var themeIndex: Int = 1 { didSet { save() } }
    @Published var followSystemDarkMode: Bool = false { didSet { save() } }
    @Published var fontSize: Double = 20 { didSet { save() } }
    @Published var lineSpacing: Double = 6 { didSet { save() } }
    @Published var paragraphSpacing: Double = 10 { didSet { save() } }
    @Published var horizontalMargin: Double = 24 { didSet { save() } }
    @Published var verticalMargin: Double = 40 { didSet { save() } }
    @Published var firstLineIndent: Bool = true { didSet { save() } }
    @Published var fontFamily: String = ReaderSettingsStore.systemFontKey { didSet { save() } }
    @Published var pageAnimation: PageAnimation = .slide { didSet { save() } }
    @Published var keepScreenOn: Bool = false { didSet { save() } }
    @Published var speechRate: Double = 0.5 { didSet { save() } }
    @Published var speechPitch: Double = 1.0 { didSet { save() } }
    @Published var tappableTurnPage: Bool = true { didSet { save() } }

    static let systemFontKey = "system"

    static let fontOptions: [(key: String, label: String)] = [
        (systemFontKey, "系统默认"),
        ("PingFang SC", "苹方"),
        ("Songti SC", "宋体"),
        ("Kaiti SC", "楷体"),
        ("Yuanti SC", "圆体"),
    ]

    // MARK: - 计算属性

    var theme: ReaderTheme {
        let index = min(max(themeIndex, 0), ReaderTheme.presets.count - 1)
        return ReaderTheme.presets[index]
    }

    func resolvedTheme(for scheme: ColorScheme) -> ReaderTheme {
        followSystemDarkMode ? ReaderTheme.matchingSystemColorScheme(scheme) : theme
    }

    func uiFont(ofSize size: CGFloat) -> UIFont {
        guard fontFamily != Self.systemFontKey,
              let font = UIFont(name: fontFamily, size: size) else {
            return UIFont.systemFont(ofSize: size)
        }
        return font
    }

    var textInsets: UIEdgeInsets {
        UIEdgeInsets(top: verticalMargin, left: horizontalMargin, bottom: verticalMargin, right: horizontalMargin)
    }

    // MARK: - 持久化

    private struct Snapshot: Codable {
        var themeIndex: Int
        var followSystemDarkMode: Bool
        var fontSize: Double
        var lineSpacing: Double
        var paragraphSpacing: Double
        var horizontalMargin: Double
        var verticalMargin: Double
        var firstLineIndent: Bool
        var fontFamily: String
        var pageAnimation: PageAnimation
        var keepScreenOn: Bool
        var speechRate: Double
        var speechPitch: Double
        var tappableTurnPage: Bool
    }

    private let defaultsKey = "OpenReader.readerSettings.v1"

    private init() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        themeIndex = snapshot.themeIndex
        followSystemDarkMode = snapshot.followSystemDarkMode
        fontSize = snapshot.fontSize
        lineSpacing = snapshot.lineSpacing
        paragraphSpacing = snapshot.paragraphSpacing
        horizontalMargin = snapshot.horizontalMargin
        verticalMargin = snapshot.verticalMargin
        firstLineIndent = snapshot.firstLineIndent
        fontFamily = snapshot.fontFamily
        pageAnimation = snapshot.pageAnimation
        keepScreenOn = snapshot.keepScreenOn
        speechRate = snapshot.speechRate
        speechPitch = snapshot.speechPitch
        tappableTurnPage = snapshot.tappableTurnPage
    }

    private func save() {
        let snapshot = Snapshot(
            themeIndex: themeIndex,
            followSystemDarkMode: followSystemDarkMode,
            fontSize: fontSize,
            lineSpacing: lineSpacing,
            paragraphSpacing: paragraphSpacing,
            horizontalMargin: horizontalMargin,
            verticalMargin: verticalMargin,
            firstLineIndent: firstLineIndent,
            fontFamily: fontFamily,
            pageAnimation: pageAnimation,
            keepScreenOn: keepScreenOn,
            speechRate: speechRate,
            speechPitch: speechPitch,
            tappableTurnPage: tappableTurnPage
        )
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
