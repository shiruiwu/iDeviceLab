import SwiftUI

@main
struct iDeviceLabApp: App {
    @StateObject private var store = ProfileStore()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}
