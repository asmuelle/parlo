import DesignSystem
import SwiftUI

@main
struct ParloApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .tint(ParloPalette.terracotta.color)
        }
    }
}
