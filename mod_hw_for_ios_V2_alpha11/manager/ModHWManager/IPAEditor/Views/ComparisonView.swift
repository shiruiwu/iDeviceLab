import SwiftUI

struct ComparisonView: View {
    let primaryURL: URL
    let primaryName: String
    let onClose: () -> Void

    @State private var secondaryURL: URL?
    @State private var result: IPAComparisonResult?
    @State private var errorMessage: String?
    @State private var isComparing = false
    @State private var showPicker = false

    var body: some View {
        IPASheet(title: "比较 IPA", onClose: onClose) {
            fileCard

            if isComparing {
                IPALoadingRow(text: "正在比较…")
            }

            if let errorMessage {
                IPAInfoBanner(message: errorMessage, color: .red)
            }

            if let result {
                if !result.hasDifferences {
                    IPAInfoBanner(
                        message: "未发现差异。",
                        color: .blue,
                        icon: "checkmark.circle.fill"
                    )
                }

                metadataCard(result)
                filesCard(result)
            }
        }
        .sheet(isPresented: $showPicker) {
            DocumentPicker(
                onPick: { url in
                    showPicker = false
                    secondaryURL = url
                    compare(url)
                },
                onCancel: {
                    showPicker = false
                }
            )
        }
    }

    private var fileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            IPACardHeader(icon: "arrow.left.arrow.right", title: "文件")

            IPAMetadataRow(label: "原始版本", value: primaryName, monospaced: false)

            if let secondaryURL {
                IPASubtleDivider()
                IPAMetadataRow(label: "对比版本", value: secondaryURL.lastPathComponent)
            }

            Button {
                showPicker = true
            } label: {
                Label(
                    secondaryURL == nil ? "选择 IPA" : "选择其他 IPA",
                    systemImage: "folder"
                )
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
            }
            .ipaidGlassButton(.blue)
        }
        .cardStyle()
    }

    private func metadataCard(_ result: IPAComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IPACardHeader(icon: "app.badge", title: "元数据")

            ForEach(result.metadata) { item in
                IPASubtleDivider()

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Text(item.label)
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)

                        if item.isDifferent {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 5, height: 5)
                        }
                    }

                    HStack(alignment: .top, spacing: 8) {
                        Text(item.left)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(item.isDifferent ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                            .truncationMode(.middle)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                            .padding(.top, 3)

                        Text(item.right)
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundColor(item.isDifferent ? .primary : .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .cardStyle()
    }

    private func filesCard(_ result: IPAComparisonResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            IPACardHeader(icon: "doc.on.doc", title: "文件")

            IPAFileCountRow(label: "新增", count: result.addedFiles.count, color: .green)
            IPAFileCountRow(label: "已移除", count: result.removedFiles.count, color: .red)
            IPAFileCountRow(label: "已更改", count: result.changedFiles.count, color: .orange)

            if !result.addedFiles.isEmpty {
                IPASubtleDivider().padding(.vertical, 6)
                Text("新增")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                IPAPathList(paths: result.addedFiles, limit: 8)
                    .padding(.top, 4)
            }

            if !result.removedFiles.isEmpty {
                IPASubtleDivider().padding(.vertical, 6)
                Text("已移除")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                IPAPathList(paths: result.removedFiles, limit: 8)
                    .padding(.top, 4)
            }

            if !result.changedFiles.isEmpty {
                IPASubtleDivider().padding(.vertical, 6)
                Text("已更改")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(.secondary)
                IPAPathList(paths: result.changedFiles, limit: 8)
                    .padding(.top, 4)
            }
        }
        .cardStyle()
    }

    private func compare(_ url: URL) {
        errorMessage = nil
        result = nil
        isComparing = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let primary = try IPAArchive(url: primaryURL)
                let secondary = try IPAArchive(url: url)
                let comparison = IPAComparison.compare(
                    left: primary,
                    leftName: primaryName,
                    right: secondary,
                    rightName: url.lastPathComponent
                )

                DispatchQueue.main.async {
                    result = comparison
                    isComparing = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isComparing = false
                }
            }
        }
    }
}
