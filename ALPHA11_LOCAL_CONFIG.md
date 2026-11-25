# Alpha11 本地配置接入说明

## 当前接入方式

- Alpha11 的主配置文件路径：`/var/mobile/Library/Preferences/com.modhw.ios.devices.plist`。
- Alpha11 在动态库初始化时调用 `initPrefFile()` 读取该文件；旧路径 `/tmp/devices.plist` 仅作为原项目兼容回退。
- iDeviceLab Rootless Core 作为本机诊断服务运行，监听回环地址 `127.0.0.1:18080`，不会连接云端。
- `GET /config/status` 检查主配置文件是否存在、是否可解析、字段数量、字段名和修改时间；不会返回配置值。
- 管理器的「Alpha11 本地配置文件」区域展示上述诊断结果。

## 重要区别

本地 plist 诊断成功，只能证明文件存在且格式可解析；不能证明某个 Hook 已加载、某个进程已读取配置，或第三方 App 已采用相应值。Alpha11 在动态库构造阶段加载配置，配置文件变化后需要重新启动目标进程才能重新读取；具体进程是否加载该 tweak，还取决于 MobileSubstrate 过滤规则和系统注入状态。

当前版本没有把 iDeviceLab 的测试 Profile JSON 当成 Alpha11 的设备配置文件，也没有把两个不同 schema 强行互转。App 绑定仍是管理器内的管理元数据，不能据此声称分 App Hook 已生效。

## 安全与维护

- 诊断接口只返回字段名，不返回序列号、IMEI、UDID、MAC、IDFA、IDFV 等字段的具体内容。
- 诊断接口为只读，不会覆盖现有 plist，避免因字段类型或版本差异破坏原配置。
- 不应将空白示例 plist 误认为已配置或已启用。
- 修改配置前应在设备本地另行备份原文件；更新插件后先检查文件可解析，再逐项进行兼容性验证。

## 交付验证清单

- [ ] GitHub Actions 中 iDeviceLab IPA 构建成功并生成 IPA Artifact。
- [ ] GitHub Actions 中 Rootless Core DEB 构建成功并生成 DEB Artifact。
- [ ] Alpha11 Rootless tweak DEB 构建成功并生成 DEB Artifact。
- [ ] iPhone 12 / iOS 16.2 上安装管理器并成功启动。
- [ ] 越狱环境中安装 Rootless Core，LaunchDaemon 正常运行。
- [ ] 管理器能连接本机 Core，系统信息和已安装 App 清单可读取。
- [ ] 管理器能正确报告 Alpha11 plist 缺失、格式错误和格式正常三种状态。
- [ ] Alpha11 tweak 能加载，日志无崩溃；分别验证目标进程加载情况。
- [ ] 完成配置备份/恢复、回滚、缓存清理的实机回归。
- [ ] 记录设备型号、iOS 版本、越狱方案、包版本和验证结果。

只有全部适用项目完成并保留实测记录，才标记为正式交付。CI 成功不等同于设备端验证成功。
