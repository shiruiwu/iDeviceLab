import SwiftUI
import UIKit

struct ModificationPreviewView: View {
    let summary: IPAModificationSummary
    let originalIcon: UIImage?
    let replacementIcon: UIImage?
    let isExporting: Bool
    let onExport: () -> Void
    let onClose: () -> Void

    private var warnings: [String] {
        var messages = summary.warnings
        let signature = "修改 IPA 会使原签名失效，安装前请重新签名。"

        if !messages.contains(signature) {
            messages.append(signature)
        }

        return messages
    }

    var body: some View {
        IPASheet(title: "检查更改", centeredTitle: true) {
            actionRow

            ModificationReviewContent(
                summary: summary,
                originalIcon: originalIcon,
                replacementIcon: replacementIcon
            )

            ForEach(warnings, id: \.self) { message in
                IPAInfoBanner(message: message, color: .orange)
            }
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Text("取消")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .ipaidGlassButton(.red)

            Button(action: onExport) {
                HStack(spacing: 8) {
                    if isExporting {
                        ProgressView()
                            .accentColor(.green)
                    }

                    Text(isExporting ? "正在导出…" : "确认")
                        .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .ipaidGlassButton(.green)
            .disabled(isExporting || summary.isEmpty)
        }
    }
}
