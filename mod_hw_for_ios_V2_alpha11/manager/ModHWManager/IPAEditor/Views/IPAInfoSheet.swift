import SwiftUI
import UIKit

struct IPAInfoSheet: View {
    let info: IPABundleInfo
    let fileName: String
    let iconImage: UIImage?
    let onClose: () -> Void

    @State private var showTechnicalDetails = false

    var body: some View {
        IPASheet(title: "IPA 信息", onClose: onClose) {
            overviewCard
            applicationCard
            technicalCard
        }
    }

    private var overviewCard: some View {
        HStack(spacing: 14) {
            IPAIconThumbnail(image: iconImage, size: 62)

            VStack(alignment: .leading, spacing: 4) {
                Text(info.displayName.isEmpty ? "未命名应用" : info.displayName)
                    .font(.headline)

                Text(info.bundleIdentifier)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(fileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .cardStyle()
    }

    private var applicationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            IPACardHeader(icon: "app.badge", title: "应用")

            IPAMetadataRow(label: "版本", value: value(info.marketingVersion))
            IPASubtleDivider()
            IPAMetadataRow(label: "构建版本", value: value(info.buildNumber))
            IPASubtleDivider()
            IPAMetadataRow(label: "最低 iOS 版本", value: value(info.minimumOSVersion))
            IPASubtleDivider()
            IPAMetadataRow(
                label: "文件大小",
                value: IPAFormatting.fileSize(info.fileSize)
            )
            IPASubtleDivider()
            IPAMetadataRow(label: "扩展组件", value: "\(info.extensions.count)")
        }
        .cardStyle()
    }

    private var technicalCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showTechnicalDetails.toggle()
                }
            } label: {
                IPACardHeader(
                    icon: "cpu",
                    title: "技术详情",
                    isExpanded: showTechnicalDetails
                )
            }
            .buttonStyle(.plain)

            if showTechnicalDetails {
                IPASubtleDivider()
                    .padding(.top, 12)

                IPAMetadataRow(
                    label: "可执行文件",
                    value: value(info.executable),
                    monospaced: true
                )
                IPASubtleDivider()
                IPAMetadataRow(
                    label: "架构",
                    value: info.architectures.isEmpty
                        ? "未知"
                        : info.architectures.joined(separator: ", "),
                    monospaced: true
                )
                IPASubtleDivider()
                IPAMetadataRow(
                    label: "设备",
                    value: info.deviceFamilies.isEmpty ? "未知" : info.deviceFamilyLabel
                )

                if !info.targetSDK.isEmpty {
                    IPASubtleDivider()
                    IPAMetadataRow(
                        label: "编译所用 SDK",
                        value: info.targetSDK,
                        monospaced: true
                    )
                }

                IPASubtleDivider()
                IPAMetadataRow(
                    label: "应用包路径",
                    value: info.appRoot,
                    monospaced: true
                )
            }
        }
        .cardStyle()
    }

    private func value(_ text: String) -> String {
        text.isEmpty ? "未知" : text
    }
}
