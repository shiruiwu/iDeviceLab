# iDeviceLab 2.0

iOS 本地测试配置管理器与只读 Rootless Core（系统诊断、已安装 App 清单、Alpha11 plist 状态诊断），主要实机目标为 iPhone 12 / iOS 16.2。

## 工程组成

- `iDeviceLab-2.0-source-v2/iDeviceLab-2.0`：TrollStore IPA 管理器与 Rootless Core。
- `mod_hw_for_ios_V2_alpha11`：原作者 Alpha11 Theos tweak 源码与 Rootless 打包工程。
- `device-manager-pro-full`：集成开发分支。

## 文档

- [中文功能说明与构建方式](iDeviceLab-2.0-source-v2/iDeviceLab-2.0/README_CN.md)
- [Alpha11 本地 plist 接入说明、接口和交付验证清单](ALPHA11_LOCAL_CONFIG.md)

## 构建产物

打开 [GitHub Actions](https://github.com/shiruiwu/iDeviceLab/actions)，选择对应成功的工作流运行，在 Artifacts 中下载：

- `iDeviceLab-trollstore-ipa)：iDeviceLab 管理器 IPA。
- `iDeviceLab-rootless-deb)：iDeviceLab Rootless Core DEB。
- `mod-hw-alpha11-rootless-deb)：Alpha11 Rootless tweak DEB。
- Alpha11 Manager IPA（如该 workflow run 同时上传该 Artifact）：仅作为原项目附带管理器。

## 验收状态

CI 构建成功只表示对应构建任务通过，不等于已在真实设备安装、启动或验证 Hook。只有 iPhone 12 / iOS 16.2 实机完成文档中的安装、服务连接、plist 诊断、备份恢复和维护回归，才可标记为正式交付。
