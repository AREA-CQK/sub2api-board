import SwiftUI
import WidgetKit

@main
struct Sub2APIBoardApp: App {
    @StateObject private var model = BoardViewModel()

    init() {
        WidgetCenter.shared.reloadAllTimelines()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1040, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)

        Settings {
            SettingsView()
                .environmentObject(model)
                .frame(width: 520, height: 430)
        }
    }
}
