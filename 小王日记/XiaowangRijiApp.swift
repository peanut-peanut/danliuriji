import SwiftUI

@main
struct XiaowangRijiApp: App {
    @StateObject private var store = DiaryStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .tint(.orange)
        }
    }
}
