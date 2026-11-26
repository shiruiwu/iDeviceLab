# Alpha11 本地配置接入说明

## 当前接入方式

- Alpha11 打包时已将可选的 Apple 云端响应过滤模块从 Theos 编译目标中排除，并将注入过滤范围收窄到 SpringBoard 与设置 App；云端守护进程不再作为本地管理器运行的依赖。

- Alpha11 的主配置文件路径：`/var/mobile/Library/Preferences/com.modhw.ios.devices.plist`。
- Alpha11 在动态库初始化时调用 `initPrefFile()` 读取该文件；旧路径 `/tmp/devices.plist` 仅作为原项目兼容回退。
- iDeviceLab Rootless Core 作为本机诊断服务运行，监听回环地址 `127.0.0.1:18080`，不会连接云端。
- `GET /config/status` 检查主配置文件是否存在、是否可解析、Alpha11 加载器要求的 `UniqueDeviceID` 字段是否存在且为字符串、字段数量、字段名和修改时间；不会返回任何字段值。
- 管理器可导入 plist 文件，但只向 Core 提交 8 个允许字段：`HWModelStr`、`ProductVersion`、`BuildVersion`、`HardwarePlatform`、`ModelNumber`、`RegionInfo`、`RegionCode`、`ProductType`。
- `POST /config/update` 要求现有 plist 已存在且结构有效，保留原文件其他字段，仅更新上述白名单字段，并通过原子写入保存；序列号、IMEI、UDID、MAC、IDFA、IDFV 等字段不会被导入覆盖。
- 管理器的「Alpha11 本地配置文件」区域展示上述诊断结果。

## 重要区别

本地 plist 诊断成功，只能证明文件存在且格式可解析；不能证明某个 Hook 已加载、某个进程已读取配置，或第三方 App 已采用相应值。Alpha11 在动态库构造阶段加载配置，配置文件变化后需要重新启动目标进程才能重新读取；具体进程是否加载该 tweak，还取决于 MobileSubstrate 过滤规则和系统注入状态。

当前版本没有把 iDeviceLab 的测试 Profile JSON 当成 Alpha11 的设备配置文件，也没有把两个不同 schema 强行互转。App 绑定仍是管理器内的管理元数据，不能据此声称分 App Hook 已生效。导入配置只更新白名单中的非唯一测试字段，不等于修改身份字段或证明运行时 Hook 已生效。

## 安全与维护

- 诊断接口只返回字段名，不返回序列号、IMEI、UDID、MAC、IDFA、IDFV 等字段的具体内容。
- `/config/status` 返回文件状态及本地回滚备份状态，不返回字段值；`/config/update` 仅对固定白名单字段执行类型/长度/格式检查，先自动备份，再原子更新现有 plist；`POST /config/restore` 仅恢复 Core 自己创建的本地备份。
- 不会新建空白身份配置，也不会修改或返回设备唯一标识字段的值。
- 不应将空白示例 plist 误认为已配置或已启用。
- 导入前应在设备本地另行备份原文件；更新后重新检查文件可解析，再重启目标进程并逐项进行兼容性验证。

## 实机快速诊断

仓库提供只读脚本 `scripts/device-smoke-test.sh`。将脚本传到越狱 iPhone 后，通过 SSH 执行：

```sh
sh device-smoke-test.sh
```

脚本会检查设备信息、DEB 安装状态、Rootless 文件路径、Alpha11 plist 语法、Core HTTP 状态、LaunchDaemon 状态和最近日志；不会改写配置、删除数据或重启服务。完整输出可用于定位安装和启动问题。

## 交付验证清单

- [ ] GitHub Actions 中 iDeviceLab IPA 构建成功并生成 IPA Artifact。
- [ ] GitHub Actions 中 Rootless Core DEB 构建成功并生成 DEB Artifact。
- [ ] Alpha11 Rootless tweak DEB 构建成功并生成 DEB Artifact。
- [ ] iPhone 12 / iOS 16.2 上安装管理器并成功启动。
- [ ] 越狱环境中安装 Rootless Core，LaunchDaemon 正常运行。
- [ ] 管理器能连接本机 Core，系统信息和已安装 App 清单可读取。
- [ ] 管理器能正确报告 Alpha11 plist 缺失、格式错误和格式正常三种状态。
- [ ] 用测试 plist 验证 8 个允许字段能更新；混入唯一标识字段时确认它们被忽略且原值不变。
- [ ] 验证更新前自动生成本地备份，恢复操作能还原更新前文件字节。
- [ ] Alpha11 tweak 能加载，日志无崩溃；分别验证 SpringBoard 与设置 App 的加载情况。
- [ ] 完成配置备份/恢复、回滚、缓存清理的实机回归。
- [ ] 记录设备型号、iOS 版本、越狱方案、包版本和验证结果。

只有全部适用项目完成并保留实测记录，才标记为正式交付。CI 成功不等同于设备端验证成功。
