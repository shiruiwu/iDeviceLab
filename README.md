# iDeviceLab / mod_hw_for_ios V2

当前 Alpha11 主工程位于 `mod_hw_for_ios_V2_alpha11/`，面向 iPhone 12 / iOS 16.2 的 Dopamine Rootless 环境。

## 项目组成

- `mod_hw_for_ios_V2_alpha11/src/`：原作者 Hook 源码及所需第三方依赖
- `mod_hw_for_ios_V2_alpha11/core/`：本地 Core 与维护权限助手
- `mod_hw_for_ios_V2_alpha11/manager/`：TrollStore 中文管理器
- `mod_hw_for_ios_V2_alpha11/scripts/`：构建、诊断、备份、还原和清理脚本
- `mod_hw_for_ios_V2_alpha11/layout/`：Rootless 插件配置与示例文件
- `mod_hw_for_ios_V2_alpha11/release-notes/`：构建记录与交付审查

`iDeviceLab-2.0-source-v2/` 保留为早期管理器源码与参考实现；Alpha11 当前构建工作流以 `mod_hw_for_ios_V2_alpha11/` 为准。

## 构建与交付

GitHub Actions 工作流位于 `.github/workflows/`。构建产物包括 Rootless DEB 和 TrollStore IPA。构建通过不等于真机验收通过；最终状态以 iPhone 12 / iOS 16.2 的实际安装、启动、连接、Hook 与维护操作结果为准。

## 分支

- `mod-hw-alpha11`：当前 Alpha11 开发与构建分支
- `main`：仓库默认分支
- `device-manager-pro-full`：集成开发历史分支

## 清理约定

仓库不保留 macOS Finder 的 `.DS_Store` 文件或临时 CI 触发说明；项目源码、第三方依赖、许可证、配置模板和构建脚本均保留。
