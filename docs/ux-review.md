# QuickRightClick 用户体验评估与优化方案

> 评估对象：QuickRightClick（macOS Finder 右键扩展 + SwiftUI 设置界面）
> 评估范围：响应速度、前端视觉设计、交互流程、整体可用性
> 版本：v1.0 ｜ 本次已落地 P0 / P1 全部整改项，P2 项列为后续建议

---

## 一、结论摘要

| 维度 | 优化前评分 | 优化后（预期） | 关键问题 |
|---|---|---|---|
| 响应速度 | 5.5 / 10 | 9 / 10 | 每次右键 2 次同步磁盘 IO；逐击键全量写盘；终端列表每次渲染重新扫描文件系统 |
| 视觉设计 | 4 / 10 | 8.5 / 10 | 界面暴露配置文件路径；间距 16/12/10 混用；无字体层级；状态信息 3 行堆叠 |
| 交互流程 | 5 / 10 | 8.5 / 10 | "新建文件项"按钮生成 `TXT2` 垃圾项；双击重命名发现性差；空列表无出路 |
| 整体可用性 | 6 / 10 | 9 / 10 | 缺 AirDrop 快捷入口；扩展未启用时无有效引导；卸载终端后下拉框空白 |

**核心判断**：本项目功能正确、架构清晰（沙盒扩展 + 无沙盒主程序分工合理），问题集中在
**"每次交互的固定开销"** 与 **"界面上不必要的噪音"** 两处——前者影响体感流畅度，后者影响专业感。

---

## 二、问题诊断

### P0 —— 直接影响可用性 / 必须修复

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| P0-1 | 右键菜单每次构建都同步读盘，点击时再读一次 | `FinderSyncExtension.menu(for:)` 与 `handleMenuItem(_:)` 各调一次 `ConfigurationStore.load()`（读取 + JSON 解析 + 模型构造） | 右键到菜单弹出的延迟随配置项增多线性上升；磁盘繁忙时菜单"卡一下" |
| P0-2 | 设置项逐击键全量写盘 + 同步脚本 | `SettingsModel.configuration.didSet → save()`，每次按键都 `ConfigurationStore.save()` + `MenuActionExecutor.syncScripts()`（遍历脚本目录） | 编辑标题 / 命令时输入发涩；磁盘写入次数 = 击键次数 |
| P0-3 | 防抖（若引入）与退出竞态 | 加固项：合并写盘必须配 `flushPendingSave()`，否则 300ms 窗口内退出会丢编辑 | 数据丢失风险 |
| P0-4 | "新建文件项"按钮生成无意义菜单项 | `addNewFileItem()` 自动挑未被占用的后缀：`txt` → `txt2` → `txt3`…，界面上出现"创建 TXT2"，实际创建 `新建文件.txt2` | 用户困惑（"这是干啥用的？"）、配置里堆积垃圾项、功能价值为负 |
| P0-5 | 缺少 AirDrop 快捷入口 | 右键菜单只有拷贝路径 / 终端 / 新建文件 | macOS 最高频的"分享给附近设备"场景缺位，用户须自己开 Finder 分享菜单 |

### P1 —— 明显影响效率 / 专业感

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| P1-1 | 终端应用列表每次渲染重新探测文件系统 | `terminalApplications` 是计算属性，Picker 每帧调用 `TerminalApplication.detect()`（6 次 `fileExists`） | 窗口滚动 / 状态变化时产生无谓 IO |
| P1-2 | 重命名只有"双击"入口，且靠一行小字提示 | `Text(...).onTapGesture(count: 2)` + "双击名称可重命名" caption2 | 发现性极差，绝大多数用户不会重命名 |
| P1-3 | 菜单项列表删空后没有任何出路 | 列表为空时只剩空白区域，`addNewFileItem` 是唯一"添加内置项"的入口（且它生成垃圾项） | 用户误删后只能手改配置文件 |
| P1-4 | 扩展未启用时引导不完整 | 状态文案"扩展未启用，右键菜单不会出现" + 两个平级小按钮 | 用户不知道要去"登录项与扩展 → 文件提供程序"，也不知道可以重新检测 |
| P1-5 | 状态信息三行堆叠、彼此竞争 | footer 同时渲染 `saveErrorMessage` / `shortcutMessage` / 扩展状态 | 视觉噪音；同一时刻只有一条信息真正需要被看到 |

### P2 —— 细节打磨 / 代码卫生

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| P2-1 | 界面暴露配置文件绝对路径 | header 中 `configPath` 显示 `~/Library/Application Support/.../config.json` | 对普通用户无意义，占一行高度，降低专业感 |
| P2-2 | 死代码残留在主程序里 | `isAccessibilityTrusted`、`requestAccessibilityPermission()`、`openAccessibilitySettings()`、`newFileSelection` 全项目零引用；`import ApplicationServices` 随之冗余 | 误导后续维护者以为存在辅助功能依赖 |
| P2-3 | 间距与字体层级不统一 | 区块 padding 混用 16/12/10；辅助文案 caption/caption2 随机使用 | 界面显脏，缺少节奏感 |
| P2-4 | 终端选择行与当前配置无关时仍然显示 | 没有任何"进入终端 / 运行命令"项时，"终端应用"仍在界面上 | 无效设置项占据视觉注意力 |
| P2-5 | 已卸载的终端应用导致下拉框空白 | `Picker` 的选项来自实时探测结果，配置值不在列表中时显示为空 | 看起来像配置丢了 |

---

## 三、优化优先级与整改建议

### P0 整改（本次已实施）

| # | 整改措施 | 实现位置 |
|---|---|---|
| P0-1 | **扩展侧配置进程内缓存**：以配置文件的「修改时间 + 大小」做失效校验（主程序一律原子替换整个文件，写盘后属性必然变化，因此缓存永不读到过期配置）；属性读不到时用 3s TTL 兜底。菜单构建与动作分发共用同一次读取 | `Extension/FinderSyncExtension.swift` → `ConfigurationCache` |
| P0-2 | **写盘防抖 300ms**：连续编辑合并为一次落盘，`syncScripts` 随落盘一起执行（其内部已按内容比对跳过未变脚本） | `App/SettingsModel.swift` → `scheduleSave()` |
| P0-3 | **退出前强制落盘**：`flushPendingSave()` 在窗口关闭（`.onDisappear`）与应用退出（`NSApplication.willTerminateNotification`）时调用 | `SettingsModel` + `SettingsView` + `QuickRightClickApp` |
| P0-4 | **删除"新建文件项"按钮**及 `addNewFileItem()`：不再产生 `TXT2` 这类占位项 | `App/SettingsView.swift`、`App/SettingsModel.swift` |
| P0-5 | **新增"AirDrop 共享"菜单项**：扩展沙盒无法直接发起 AirDrop，沿用已验证的委托链路 `quickrightclick://airdrop?path=…` → 主程序 `NSSharingService(.sendViaAirDrop)`；**未选中文件时不显示该项**；发送面板锚定到前台窗口 | `MenuConfiguration`、`MenuActionExecutor`、`QuickRightClickApp`、`FinderSyncExtension` |

### P1 整改（本次已实施）

| # | 整改措施 | 实现位置 |
|---|---|---|
| P1-1 | 终端列表改为启动时探测一次的存储属性 | `SettingsModel.terminalApplications` |
| P1-2 | 行内 **hover 浮现铅笔按钮**作为重命名入口（双击仍保留），并给出 tooltip | `SettingsView.MenuItemRow` |
| P1-3 | 列表空态提供 **"恢复默认菜单项"** 按钮 | `SettingsView` 空态 overlay + `SettingsModel.restoreDefaultItems()` |
| P1-4 | 状态行整行可点击 = 重新检测；"打开系统设置"保留为独立按钮并附 tooltip 指明位置 | `SettingsView.footer` |
| P1-5 | 状态信息**三选一互斥展示**：保存失败 > 快捷方式结果 > 扩展启用状态 | `SettingsView.currentStatus` |

### P2 整改（本次已实施 / 部分列为后续建议）

| # | 状态 | 说明 |
|---|---|---|
| P2-1 | 已实施 | 删除 `configPath` 与 header 中的路径文本 |
| P2-2 | 已实施 | 删除辅助功能权限相关全部符号与 `import ApplicationServices`；经全项目引用检查确认零残留 |
| P2-3 | 已实施 | 引入 `Metrics` 常量统一间距（水平 16 / 区块 12 / 紧凑 8）；字体固定为 headline / subheadline.weight(.medium) / caption 三级 |
| P2-4 | 已实施 | 仅当菜单中存在"进入终端"或"运行命令"时才显示"终端应用"行（含其分隔线） |
| P2-5 | 已实施 | 配置值不在探测结果中时，额外插入"已卸载的应用"占位选项，保证当前值始终可见 |
| P2-6 | **后续建议** | 菜单项类型改为可视下拉（当前新增项只能通过"添加命令"）；本次已用空态恢复按钮覆盖主要恢复路径 |
| P2-7 | **后续建议** | 配置结构版本机制已就位（`currentSchemaVersion`），后续新增内置项只需递增版本号并补迁移分支 |
| P2-8 | **后续建议** | 为菜单项提供 SF Symbol 选择器（当前只能手改 `symbolName`） |
| P2-9 | **后续建议** | iCloud Drive 下菜单不显示、菜单仅在主目录生效——属 FinderSync 系统限制，建议在设置界面以帮助文档说明，而非继续投入 |

---

## 四、预期效果

| 指标 | 优化前 | 优化后 | 说明 |
|---|---|---|---|
| 右键 → 菜单弹出 | 每次 2 次同步磁盘 IO（读取 + 解析） | 命中缓存 1 次 `stat`（微秒级） | 配置未变时不再解析 JSON |
| 编辑一个标题的磁盘写入次数 | 击键数（如 12 次） | 1 次（300ms 合并） | 输入不再因写盘 + 脚本同步发涩 |
| 终端下拉框渲染开销 | 每次渲染 6 次 `fileExists` | 0（启动探测一次） | 消除滚动时的无谓 IO |
| 界面信息量 | 路径文本 + 3 行状态 + 无效设置项 | 标题 / 开关 + 单行状态 + 按需设置项 | 视觉噪音显著下降 |
| 新增能力 | 无 AirDrop 入口 | 选中文件 → 右键 → AirDrop 共享 | 沙盒约束下复用已验证链路，零新增依赖 |
| 用户可恢复性 | 删空 / 改名后无从下手 | 空态恢复按钮 + hover 铅笔入口 | 交互闭环完整 |
| 单元测试 | 23 项 | 31 项（+8） | 新增 AirDrop URL 构造 / 解析、配置迁移、默认项断言 |

---

## 五、UX 设计改进方向（视觉规范）

**风格定位：原生精简（macOS Native Minimal）**——不引入自定义配色与自绘控件，靠"信息降噪 + 节奏统一"提升质感。

1. **间距体系**：水平 16、区块垂直 12、紧凑 8；全窗口共用 `Metrics` 常量，消灭 16/12/10 混用。
2. **字体层级**：标题 `headline`、区块标题 `subheadline.weight(.medium)`、辅助说明 `caption`；不再出现 `caption2` 与正文混用。
3. **颜色策略**：一律使用系统语义色（`.secondary` / `.tertiary` / `.green` / `.orange` / `.red`），状态色只用于状态反馈；菜单项图标沿用 `kind.defaultColor` 功能色体系，与右键菜单中的彩色图标一一对应（含新增的 AirDrop 青色）。
4. **信息降噪**：界面上不出现用户看不懂的内容——配置文件路径、内部标识符、无法操作的提示文案全部移出视图。
5. **可见性优先**：能点击的东西必须看起来可点击（铅笔按钮、状态行点击重检）；不可用的东西不出现在界面上（无选中项时不显示 AirDrop 项，无终端相关项时不显示终端选择）。
6. **状态收敛**：同一时刻只展示一条最高优先级状态，避免多行提示互相争夺注意力。

---

## 六、AirDrop 功能的操作入口与交互设计

**入口**
- 右键菜单新增内置项"AirDrop 共享"，默认位于"拷贝路径"之后（分享类操作紧跟拷贝，符合心理模型）。
- 图标：`square.and.arrow.up` 染 systemTeal，与右键菜单其余项风格一致。
- 设置界面中与其它菜单项同等对待：可开关、可重命名、可排序、可删除。

**交互规则**
1. 选中任意文件/文件夹时显示；**右键空白处不显示**（避免"共享这个目录"这种无意义操作）。
2. 多选时全部项目一次性交给 AirDrop（重复 `path` query item 承载，无自定义分隔符转义问题）。
3. 点击后主程序前台激活并弹出系统 AirDrop 面板，面板锚定设置窗口（窗口关闭时由系统定位）。
4. 链路上任一环节失败都记录 `NSLog`，不弹错误弹窗打断用户（与既有"进入终端/运行命令"一致）。

**为什么委托主程序**：FinderSync 扩展强制开启 App Sandbox，扩展内既读不到任意路径的文件内容，`NSSharingService` 在沙盒内也不可靠。项目已存在 `quickrightclick://run?id=…` 的委托链路且工作正常，AirDrop 复用它，是改动最小、风险最低的方案。

**老用户迁移**：磁盘上的旧配置没有 AirDrop 项。引入 `schemaVersion`（当前 = 2）：
- 加载旧配置（无该字段 → 0）时，把 AirDrop 项插到"拷贝路径"之后并即时落盘，用户无需任何操作即可用上新功能。
- 迁移只执行一次：用户之后主动删除 AirDrop 项不会再被加回来（有单元测试覆盖）。

---

## 七、本次改动清单

| 文件 | 改动 |
|---|---|
| `Shared/MenuConfiguration.swift` | 新增 `shareAirDrop`（颜色 systemTeal / 图标 `square.and.arrow.up`）；默认项提到 `defaultItems` 常量；引入 `currentSchemaVersion` 与 `migratedToCurrentSchema()`；`MenuConfiguration` 增加容错解码 |
| `Shared/MenuActionExecutor.swift` | 新增 AirDrop 分支与 `airDropURL(for:)` / `airDropTargets(from:)` / `airDropItems(for:)`；顺带消除一处 `var`→`let` 警告 |
| `App/QuickRightClickApp.swift` | URL 分发按 host 分支；新增 `AirDropSharer`（实现 `NSSharingServiceDelegate`，保活发送会话、锚定源窗口） |
| `App/SettingsModel.swift` | 写盘防抖 + `flushPendingSave()`；终端列表改为存储属性；删除辅助功能权限死代码与 `addNewFileItem()`；新增 `restoreDefaultItems()`；启动时执行配置迁移 |
| `App/SettingsView.swift` | 原生精简风重设计：Metrics 统一间距、状态单行互斥、hover 铅笔重命名、空态恢复入口、终端行按需显示、删除路径文本与未使用状态 |
| `Extension/FinderSyncExtension.swift` | 新增 `ConfigurationCache`；AirDrop 项在无选中项时过滤 |
| `App/QuickRightClickTests.swift` | 更新默认项断言；新增配置迁移 3 项、AirDrop 5 项（共 31 项测试全绿） |
| `README.md` | 功能表补 AirDrop；源码分工表更新；新增菜单项的指引补充 schema 版本要求 |

**验证结果**：`xcodebuild build` 成功、构建输出零警告；`xcodebuild clean test` 全部 31 项测试通过（0 failures）。

---

## 八、后续路线图（未在本次实施）

1. **菜单项类型可视化**：把"添加命令"扩展为类型下拉（拷贝路径 / 进入终端 / 新建文件 / 运行命令 / AirDrop），补齐 P2-6。
2. **图标选择器**：SF Symbol 拾取器，替代手写 `symbolName`。
3. **配置导入导出**：设置项迁移到新机器时免于手工复制 JSON。
4. **首次启动引导**：检测到扩展未启用时，用一次性引导卡片替代逐次点击"打开系统设置"。
5. **多目录监控**：当前扩展只监控家目录，可提供"额外监控目录"设置（需评估 FinderSync 权限模型）。
6. **性能度量埋点**：在 `menu(for:)` 前后记录耗时（仅 Debug 生效），用于回归验证缓存收益。
