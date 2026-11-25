import SwiftUI
import UniformTypeIdentifiers
import CoreFoundation

@main
struct ModHWManagerApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

private struct PlistEntry: Identifiable {
    let key: String
    let typeName: String
    var id: String { key }
}

struct ContentView: View {
    @State private var importOpen = false
    @State private var exportOpen = false
    @State private var importedData: Data?
    @State private var fileName = "尚未导入配置"
    @State private var status = "导入 plist 后，可检查文件结构并导出原始备份。"
    @State private var entries: [PlistEntry] = []
    @State private var isValid = false
    @State private var rootType = "未知"

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("配置文件检查器", systemImage: "doc.text.magnifyingglass").font(.title2.bold())
                        Text("只读检查 plist 文件结构、字段名称与数据类型。不会修改设备身份字段，也不会向系统服务写入配置。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("导入 plist") { importOpen = true }
                        Spacer()
                        Button("导出原始备份") { exportOpen = true }
                            .disabled(importedData == nil).buttonStyle(.borderedProminent)
                    }
                }
                Section("文件状态") {
                    LabeledContent("文件", value: fileName)
                    LabeledContent("根对象", value: rootType)
                    LabeledContent("字段数量", value: entries.isEmpty ? "—" : "\(entries.count)")
                    HStack {
                        Text("格式检查")
                        Spacer()
                        if importedData == nil {
                            Text("等待导入").foregroundStyle(.secondary)
                        } else {
                            Label(isValid ? "有效" : "无效", systemImage: isValid ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(isValid ? .green : .red)
                        }
                    }
                }
                if !entries.isEmpty {
                    Section("字段清单（不显示字段值）") {
                        ForEach(entries) { entry in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.key).font(.body.monospaced())
                                Text(entry.typeName).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("运行说明") {
                    Text(status).font(.footnote).foregroundStyle(.secondary)
                    Text("本工具仅检查用户选取的文件。iOS 沙盒不会自动授予它读取越狱目录的权限；请通过文件管理器手动导入需要检查的 plist。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("mod_hw 管理器")
            .fileImporter(isPresented: $importOpen, allowedContentTypes: [.propertyList]) { result in
                importPlist(result)
            }
            .fileExporter(
                isPresented: $exportOpen,
                document: RawPlistDocument(data: importedData ?? Data()),
                contentType: .propertyList,
                defaultFilename: backupName
            ) { result in
                switch result {
                case .success(let url): status = "原始备份已导出：\(url.lastPathComponent)"
                case .failure(let error): status = "备份导出失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private var backupName: String {
        let base = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return base.isEmpty ? "plist-backup" : "\(base)-backup"
    }

    private func importPlist(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let hasAccess = url.startAccessingSecurityScopedResource()
            defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            var format = PropertyListSerialization.PropertyListFormat.xml
            let object = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
            importedData = data
            fileName = url.lastPathComponent
            if let dictionary = object as? [String: Any] {
                rootType = "Dictionary"
                entries = dictionary.keys.sorted().map { key in
                    PlistEntry(key: key, typeName: Self.typeName(dictionary[key]))
                }
                isValid = true
                status = "导入成功。已读取字段名称和类型；字段值未展示、未更改，导出时保留原始文件字节。"
            } else {
                rootType = String(describing: type(of: object))
                entries = []
                isValid = false
                status = "plist 可以解析，但根对象不是 Dictionary 结构。"
            }
        } catch {
            importedData = nil
            entries = []
            rootType = "无法解析"
            isValid = false
            fileName = "导入失败"
            status = "文件读取或 plist 解析失败：\(error.localizedDescription)"
        }
    }

    private static func typeName(_ value: Any?) -> String {
        guard let value else { return "缺失" }
        if value is String { return "String" }
        if value is Data { return "Data" }
        if value is Date { return "Date" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "Boolean" : "Number"
        }
        if value is [String: Any] { return "Dictionary" }
        if value is [Any] { return "Array" }
        return String(describing: type(of: value))
    }
}

struct RawPlistDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.propertyList] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let contents = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        _ = try PropertyListSerialization.propertyList(from: contents, options: [], format: nil)
        data = contents
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
