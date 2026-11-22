import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ProfileManagerView()
                .tabItem {
                    Label("配置管理", systemImage: "slider.horizontal.3")
                }

            IPAEditorView()
                .tabItem {
                    Label("IPA 多开", systemImage: "square.stack.3d.up")
                }
        }
    }
}
