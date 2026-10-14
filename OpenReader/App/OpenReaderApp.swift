import SwiftUI

@main
struct OpenReaderApp: App {
    @StateObject private var library = LibraryStore()
    @StateObject private var importer = ImportCoordinator()
    @StateObject private var settings = ReaderSettingsStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
                .environmentObject(importer)
                .environmentObject(settings)
                .tint(Palette.accent)
                .preferredColorScheme(preferredScheme)
                .task {
                    // 启动时扫描 Import 投递箱
                    await importer.scanInbox(into: library)
                }
                .onOpenURL { url in
                    // 其他 App「用其他应用打开」
                    Task { await importer.importURLs([url], into: library) }
                }
        }
    }

    private var preferredScheme: ColorScheme? {
        guard !settings.followSystemDarkMode else { return nil }
        return settings.theme.isDark ? .dark : .light
    }
}
