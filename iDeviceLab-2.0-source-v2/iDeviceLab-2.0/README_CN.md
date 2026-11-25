# iDevice Lab 2.0（测试配置管理版）

面向 iOS 16+ 的测试环境配置管理器，工程以 iPhone 12 / iOS 16.2 为主要测试目标，支持 Windows 10 用户通过 GitHub Actions 云端构建。

## 当前功能

- 新增“备份与维护”页面：完整导出/导入配置档案、分 App 绑定关系与当前选择
- 还原前自动保存回滚快照，支持撤销最近一次还原
- 扫描并清理 iDeviceLab 自身沙盒内的 Caches 与 tmp 文件
- 清理前显示预计空间，清理后重新扫描；不删除其他 App 容器或系统数据

- 多套配置新增、切换、删除
- 配置自动保存到 App 沙盒 `UserDefaults`
- 设备型号、测试系统版本、语言、地区、时区、网络类型可手动选择
- 电量、内存标签、测试 UUID、经纬度可编辑
- 全部参数一键随机，以及单项参数随机
- 配置 JSON 导入、生成、系统分享/保存
- 导入时检查配置版本、数量、空配置，并修正重复 ID 和越界坐标/数值
- GitHub Actions 使用 macOS runner 编译、临时签名校验并打包 TrollStore IPA；同时构建 Rootless Core DEB

## Alpha11 本地配置诊断

- Rootless Core 通过本机回环接口检查 Alpha11 实际读取的 `/var/mobile/Library/Preferences/com.modhw.ios.devices.plist`。
- 管理器显示文件是否存在、是否可解析、字段数量和字段名；不回传配置中的唯一标识具体值。
- 这是只读诊断，不会把测试 Profile JSON 写成 Alpha11 plist，也不代表任何 Hook 已经生效。
- 详细接口说明和完整验收表见仓库根目录 `ALPHA11_LOCAL_CONFIG.md`。

## 重要能力边界

备份文件仅覆盖 iDeviceLab 自己管理的配置与绑定元数据，不是整机备份，也不包含其他 App 私有数据。缓存清理仅作用于本应用沙盒内的 Caches/tmp。越狱侧跨 App 数据维护必须通过独立授权、容器路径校验、清理预览和逐项确认实现；当前尚未宣称已实现通用跨 App 数据清理。

本项目保存的是测试配置数据。它不会修改真实 IMEI、序列号、硬件 UDID，也不会让任意第三方 App 自动读取到这些模拟值。设备型号、系统版本、网络、定位、电量、内存等字段在本版本中是配置记录/测试输入，不是系统级伪装。

TrollStore 不等于越狱，也不会自动赋予普通 App 任意修改 iOS 系统或其他 App 运行环境的能力。对第三方 IPA 的独立数据容器、Bundle ID、扩展和权限兼容性，需要逐个验证；本项目目前不承诺任意 App 通用克隆。

## Windows 10 + GitHub Actions

1. 将解压后的 `iDeviceLab-2.0` 文件夹内的全部内容上传到自己的 GitHub 仓库根目录（包括 `.github` 隐藏目录）。
2. 打开仓库的 **Actions** 页面。
3. 运行 **Build iDevice Lab IPA** 工作流，或向 `main` / `master` 分支推送提交。
4. 工作流成功后，在运行详情页的 Artifacts 区域下载 `iDeviceLab-trollstore-ipa` 和 `iDeviceLab-rootless-deb`。Alpha11 tweak 使用单独的 Theos 工作流，下载 `mod-hw-alpha11-rootless-deb`。
5. 将 IPA 传到 iPhone，再使用 TrollStore 尝试安装；如安装失败，请保留完整错误信息以便排查。

注意：CI 编译通过不等于 iPhone 实机安装、启动和 Hook 验证通过。IPA 经过 CI 临时签名与完整性检查，也仍需在 TrollStore 中完成实际安装验证。

## 本地开发

需要 macOS、Xcode、XcodeGen：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project iDeviceLab.xcodeproj -scheme iDeviceLab -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```


## Device Manager Pro 集成分支

当前整合开发分支：`device-manager-pro-full`。备份中心已覆盖配置档案、分 App 绑定和当前选择，并提供还原前快照；维护页提供 iDeviceLab 自身缓存/tmp 的扫描与确认清理。该分支仍需 GitHub Actions 编译、设备安装和实际越狱环境验证后才能标记为正式可交付版本。
