import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            ProfileManagerView()
                .tabItem {
                    Label("配置管理", systemImage: "slider.horizontal.3")
                }

            MaintenanceView()
                .tabItem {
                    Label("备份维护", systemImage: "archivebox")
                }

            IPAEditorView()
                .tabItem {
                    Label("IPA 多开", systemImage: "square.stack.3d.up")
                }

            RootlessCoreView()
                .tabItem {
                    Label("越狱核心", systemImage: "terminal")
                }

            CompatibilityView()
                .tabItem {
                    Label("设备诊断", systemImage: "stethoscope")
                }
        }
    }
}
