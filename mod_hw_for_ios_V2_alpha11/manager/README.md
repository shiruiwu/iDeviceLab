# mod_hw Manager — read-only iOS companion utility

SwiftUI companion-app source for inspecting a user-selected property-list file and exporting an unchanged backup.

## Current build

V2 diagnostics build 8. The app is intentionally read-only: it lists top-level field names and value types, does not show field values, and does not edit device identity or account-related values.

## Build

Open `ModHWManager.xcodeproj` in Xcode 15 or later. Select an iOS 16.0+ target and a signing team, then build. The Linux development environment used for this source pass does not contain Xcode or Apple's iOS SDK, so a real IPA build must be performed by the repository's macOS GitHub Actions workflow.

## Use

1. Export or copy the plist you want to inspect into the iOS Files app.
2. Open the manager and select **导入 plist**.
3. Review whether the file parses, its root object type, field names, and value types. Values are not displayed.
4. Use **导出原始备份** to export the exact original file bytes without rewriting the plist.

The app does not claim direct access to jailbreak-only paths. A standard iOS app sandbox cannot directly read or write `/var/mobile/Library/Preferences` or `/tmp`; use a file manager to select a copy manually.

## Diagnostics script

`scripts/diagnose-config.sh` is a read-only shell diagnostic for the two configuration candidate paths present in the upstream source. It reports only file existence, readability, plist syntax, and root-object structure. It does not display configuration values, inspect device identifiers, modify files, or restart processes.

Run on the jailbroken device:

```sh
sh /path/to/diagnose-config.sh
```

## Build an IPA

On macOS with Xcode 15 or later, run:

```sh
bash scripts/build-trollstore-ipa.sh
```

The script creates an unsigned TrollStore-compatible IPA. Install it through TrollStore. This Linux environment can only run source syntax and static checks; it cannot produce a genuine iOS IPA.


## 本机 Core 连接检测

管理器现在提供“越狱 Core 连接（只读检测）”按钮，向 `http://127.0.0.1:18081/status` 发起 GET 请求，超时为 3 秒，并校验 HTTP 状态码及 JSON 中的 `ok`、`service`、`version` 字段。它不会调用配置创建、选择或写入接口。

该功能只验证本机 Core 是否响应。当前 Alpha11 IPA 不会自动安装旧版 Core；若设备没有安装并启动 `com.idevelab.core`，界面应显示连接失败。此检测尚需在 iPhone 12 / iOS 16.2 真机确认。


管理器还可以通过 Core 的只读 `/apps` 接口读取已安装 App 的名称、Bundle ID 和版本，供后续按 Bundle ID 进行备份、还原和本地数据维护时选择目标。当前只是 App 清单，不代表 per-app Hook 配置已经生效；Alpha11 tweak 仍未读取每 App 独立配置。
