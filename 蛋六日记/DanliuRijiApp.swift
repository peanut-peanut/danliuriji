import SwiftUI

@main
struct DanliuRijiApp: App {
    @StateObject private var store = DiaryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(.orange)
        }
    }
}
