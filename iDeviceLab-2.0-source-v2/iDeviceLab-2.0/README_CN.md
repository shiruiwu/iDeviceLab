# iDevice Lab 2.0（测试配置管理版）

面向 iOS 16+ 的测试环境配置管理器，工程以 iPhone 12 / iOS 16.2 为主要测试目标，支持 Windows 10 用户通过 GitHub Actions 云端构建。

## 当前功能

- 多套配置新增、切换、删除
- 配置自动保存到 App 沙盒 `UserDefaults`
- 设备型号、测试系统版本、语言、地区、时区、网络类型可手动选择
- 电量、内存标签、测试 UUID、经纬度可编辑
- 全部参数一键随机，以及单项参数随机
- 配置 JSON 导入、生成、系统分享/保存
- 导入时检查配置版本、数量、空配置，并修正重复 ID 和越界坐标/数值
- GitHub Actions 使用 macOS runner 生成未签名 IPA 构建产物

## 重要能力边界

本项目保存的是测试配置数据。它不会修改真实 IMEI、序列号、硬件 UDID，也不会让任意第三方 App 自动读取到这些模拟值。设备型号、系统版本、网络、定位、电量、内存等字段在本版本中是配置记录/测试输入，不是系统级伪装。

TrollStore 不等于越狱，也不会自动赋予普通 App 任意修改 iOS 系统或其他 App 运行环境的能力。对第三方 IPA 的独立数据容器、Bundle ID、扩展和权限兼容性，需要逐个验证；本项目目前不承诺任意 App 通用克隆。

## Windows 10 + GitHub Actions

1. 将解压后的 `iDeviceLab-2.0` 文件夹内的全部内容上传到自己的 GitHub 仓库根目录（包括 `.github` 隐藏目录）。
2. 打开仓库的 **Actions** 页面。
3. 运行 **Build iDevice Lab IPA** 工作流，或向 `main` / `master` 分支推送提交。
4. 工作流成功后，在运行详情页的 Artifacts 区域下载 `iDeviceLab-unsigned-ipa`。
5. 将 IPA 传到 iPhone，再使用 TrollStore 尝试安装；如安装失败，请保留完整错误信息以便排查。

注意：当前对话环境没有 macOS / Xcode iOS SDK，因此源码已做 Swift 语法解析，但尚未完成真实 Xcode 编译和 iPhone 安装验证。未签名 IPA 也不代表已经通过 TrollStore 安装测试。

## 本地开发

需要 macOS、Xcode、XcodeGen：

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project iDeviceLab.xcodeproj -scheme iDeviceLab -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
```
