# mod_hw_for_ios

## 简介 | Overview
### English
`mod_hw_for_ios` is a jailbreak-oriented dynamic library that hooks into `MobileGestalt`, `IOKit`, `sysctl`, and selected CoreTelephony entry points in order to rewrite hardware identifiers (serial number, IMEI/MEID, MAC addresses, IDFA/IDFV, and more) at runtime. It is primarily intended for research and debugging around device fingerprint synchronization, and ships with auxiliary Frida scripts plus response filters that expose the data exchanged with iCloud/Apple services.
### 中文
`mod_hw_for_ios` 是一个面向越狱 iOS 设备的动态库项目，通过 hook `MobileGestalt`、`IOKit`、`sysctl` 以及 CoreTelephony 的关键接口，动态改写系统对硬件标识（序列号、IMEI/MEID、MAC、IDFA/IDFV 等）的读取结果。项目主要用于研究/调试设备指纹同步流程，同时附带了一组 Frida 脚本和网络响应过滤逻辑，方便在 iCloud/Apple 服务链路中观察数据。

## 当前 Alpha11 交付边界 | Alpha11 Delivery Scope

- The Theos target includes the original hook source files and uses the Rootless package scheme. Source inclusion and successful cloud compilation do not establish that every hook works on a specific iOS release.
- The TrollStore manager currently provides plist import, syntax/structure inspection, and byte-preserving export. It is not yet a full device manager and does not directly write to jailbreak system paths.
- The existing export function is a configuration-file backup. The Rootless tools package also provides explicit-bundle-ID app-container backup with a SHA-256 manifest; it now includes a guarded app-container restore with a pre-restore snapshot and rollback path; neither backup nor restore includes Keychain/App Groups, shared containers, system databases, or server-side state.
- The older iDeviceLab Core/profile code is a separate legacy component. Its saved profiles are not automatically applied to the Alpha11 tweak configuration.
- Device installation, injection, configuration application, process filtering, and runtime behavior must be verified on the target device. A successful IPA/DEB build is only a build/package result.

See [Alpha11 delivery audit](release-notes/ALPHA11_DELIVERY_AUDIT.md) for the source inventory, current gaps, and integration test requirements.

## 功能亮点 | Feature Highlights
### English
- `src/mobile_gestalt/mobile_gestalt.m` centralizes hooks for `MGCopyAnswer`/`MGCopyMultipleAnswers`, `IORegistryEntry*`, `sysctl`, and identifier APIs such as `ASIdentifierManager` and `UIDevice`, injecting values sourced from `/var/mobile/Library/Preferences/com.modhw.ios.devices.plist` (with `/tmp/devices.plist` retained as a legacy fallback).
- CoreTelephony `CTMobileEquipmentInfo` setters are overridden to cache and return deterministic IMEI/MEID data, keeping radio stack and UI in sync.
- `src/captain_hook/hook.mm` leverages CaptainHook to sanitize `LakituResponse` and `EscrowGenericResponse`, which simplifies inspecting or mutating cloud backup metadata.
- Scripts such as `frida/cloudd.js` attach to `akd`, `cloudd`, and other daemons to log selector invocations with stack traces.
- The `txt` folder hosts MobileSubstrate `plist` templates, restart scripts, and sample device profiles, while the `Makefile` automates build, codesign, deployment, and daemon restarts.

## 目录结构 | Repository Layout
### English
- `src/mobile_gestalt/`: Core hooks and fingerprint injection logic, plus the `mg_copy_answer_table.h` key mapping.
- `src/cydia_substrate_hook/`: Thin wrappers over Cydia Substrate exposing the `HOOK_FUNCTION/HOOK_MESSAGE` macros.
- `src/captain_hook/`: Network response hooks implemented with CaptainHook.
- `src/code_obfuscator/`: String obfuscation helpers such as the generated `test.auto_gen.h`.
- `src/third_party/`: Bundled dependencies (choose, mongoose, IOKit headers, UIDevice extensions, etc.).
- `frida/`: Debug / instrumentation scripts.
- `bin/` and `adiMachineProvisioning/`: Built dylibs and companion plists for quick deployment.
- `txt/`: Runtime configuration (`devices.plist`, `mod_hw_for_ios.plist`, restart script).
- `ref/`: Reference plists and archives.
### 中文
- `src/mobile_gestalt/`：核心 hook 与设备指纹注入逻辑，含 `mg_copy_answer_table.h` 的字段映射表。
- `src/cydia_substrate_hook/`：对 Cydia Substrate 的轻量封装，提供 `HOOK_FUNCTION/HOOK_MESSAGE` 宏。
- `src/captain_hook/`：网络层 hook、CaptainHook 模板代码。
- `src/code_obfuscator/`：字符串混淆辅助头，生成于 `test.auto_gen.h`。
- `src/third_party/`：包含 choose、mongoose、IOKit headers 以及 UIDevice 扩展等第三方源文件。
- `frida/`：调试脚本。
- `bin/` 与 `adiMachineProvisioning/`：已构建样本（dylib 与 `plist`）。
- `txt/`：部署所需的 `devices.plist`、`mod_hw_for_ios.plist` 与 `killall.sh`。
- `ref/`：对照用的 `plist`/参考资源。

## 构建与部署 | Build & Deployment
### English
**Prerequisites**: macOS with Xcode/iOS SDK and Theos for the Rootless tweak package. The CI workflows build artifacts; installation and runtime verification are separate steps.

1. Build the Rootless package with Theos using `make clean package FINALPACKAGE=1`.
2. Build the TrollStore manager using `bash scripts/build-trollstore-ipa.sh`.
3. Validate the configuration plist with `plutil -lint` before transferring it.
4. Use the install helper only on a device you administer. It creates a previous-file backup and validates the copied plist; it does not restart processes.
5. Verify package installation, tweak injection, configuration loading, and logs on the target iOS device.

### 中文
**依赖**：构建 Rootless 插件需要 macOS、iOS SDK 和 Theos；构建 TrollStore 管理器需要 Xcode。CI 产物构建成功与设备安装、运行验证是不同阶段。

1. 使用 Theos 执行 `make clean package FINALPACKAGE=1` 构建 Rootless DEB。
2. 使用 `bash scripts/build-trollstore-ipa.sh` 构建 TrollStore 管理器 IPA。
3. 传输配置前先执行 `plutil -lint` 检查 plist 格式。
4. 安装脚本仅用于你有管理权限的设备，会备份旧配置并校验新文件，不会自动重启进程。
5. 在目标 iOS 设备上分别验证安装、注入、配置读取和运行日志。

## 运行机制 | Runtime Behavior
- The tweak loads its configured plist during initialization and contains hooks in the source tree. Actual hook coverage depends on target process, OS version, substrate environment, and runtime testing.
- The manager is sandboxed and currently handles user-selected files. Import/export does not itself grant access to privileged jailbreak directories. Rootless backup commands are separate privileged tools and require an explicit bundle identifier.
- Alpha11 now packages a separate read-only Rootless Core on `127.0.0.1:18081`; the manager can test its `/status` endpoint. It does not yet consume legacy profiles or apply per-app configuration to the tweak.

## 调试与扩展 | Debugging & Extension
- Use `scripts/diagnose-config.sh` to check candidate configuration paths and plist structure. Use `mod-hw-app-backup <bundle.identifier>` to back up one app data container and `mod-hw-app-backup-verify <archive-name.tar.gz>` to verify it. To clear the app's local data container, run `mod-hw-app-clean <bundle.identifier> --confirm`; it creates and verifies a backup plus a rollback snapshot before clearing the container (while retaining the MCM metadata marker). Restore only after the app is fully closed: `mod-hw-app-restore <bundle.identifier> <archive-name.tar.gz> --confirm`. Restore rejects archives with unsafe paths, symlinks, hardlinks, or special files, requires the original container ID to match, and preserves a rollback snapshot. Neither operation touches Keychain/App Groups/shared/system/server data, and the cleanup command is not equivalent to uninstall/reinstall or a factory reset.
- Use the CI workflows to validate source syntax and build package artifacts.
- Record target-device test results separately; do not infer runtime success from build logs.

## 致谢与许可 | Credits & License
Third-party code such as choose, mongoose, and the UIDevice extensions remains under their respective licenses (see `src/third_party/choose/LICENSE`, etc.). This project is intended for security research and education only—do not deploy it on devices or in environments where you lack explicit permission.


## On-device verification

After installing the Alpha11 tweak, read-only Core DEB, and diagnostics tools DEB, run `mod-hw-selftest` as root. It checks the Rootless paths, launchd service, installed helper commands, and (when `curl` is available) the Core loopback status response. The manager's “检测连接” button provides the same status check if `curl` is unavailable. This is a smoke test, not a complete validation of every hook or a deep-clean guarantee.
