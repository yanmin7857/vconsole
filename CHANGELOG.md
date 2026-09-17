# Changelog

## [1.4.2] - 2026-09-17

### 修复
- **不再吞掉 Xcode 控制台日志**：`[VConsole start]` 默认会把进程 `stderr` 用 `dup2` 重定向到内部管道以捕获 `NSLog` / `fprintf`，但读线程只把日志存进面板、不写回原 `stderr`，导致 Xcode 控制台看不到任何 `NSLog` 输出。现改为捕获的同时把原始行 **tee 写回真实 `stderr`**（Xcode 控制台照常可见），面板也照常收集。
- **新增关闭开关**：暴露 `[VConsole setCaptureStderrEnabled:NO]`（底层 `VConsoleLogger` 的 `setCaptureStderrEnabled:` / `stopCapturingStderr`）。设为 NO 会恢复真实 `stderr`、Xcode 控制台恢复，但面板不再收集 `NSLog`。默认仍为 YES（捕获 + tee）。

## [1.4.1] - 2026-09-17

### 修复
- **详情页查找条输入框不可见**：日志/网络/存储详情页点击「查找」后，搜索框宽度塌缩为 0、只剩放大镜图标。根因是 `VConsoleDetailViewController` 查找条约束链末端误用 `constraintLessThanOrEqualToAnchor`（≤），整条链右侧无锚点，而 UISearchBar 不报告固有宽度 → 输入框被解算为宽度 0。改为 `constraintEqualToAnchor`（=）后约束链左右两端闭合，搜索框吸收剩余宽度正常显示、可输入。

## [1.4.0] - 2026-09-17

### 新增
- **P0-1 日志按源码定位搜索**：日志面板搜索在原有 message 匹配基础上，对 `file` / `function` / `line` 也做 OR 匹配，可直接输入文件名（如 `LoginVC.m`）、函数名或行号，反查「哪个文件 / 函数打的这条」。
- **P0-2 网络搜索扩展状态码 + 响应体**：默认搜索范围由 url / method / error 扩展为 url / method / error / **statusCode**（可直接搜 `404` / `500` 等错误码）；筛选行新增 **「含响应体」开关（默认关）**，开启后额外匹配 `requestBody` / `responseBody` —— 默认关闭以避免大 body 带来的噪声与性能开销。

### 改进
- 搜索框 placeholder 明确搜索范围：日志「搜索 内容 / 文件 / 函数」、网络「搜索 URL / 方法 / 状态码」。

## [1.3.0] - 2026-09-16

### 新增
- **搜索结果导航**：日志 / 网络面板的列表搜索支持「上一个 / 下一个匹配」跳转。底部操作栏出现 `‹ k/N ›` 计数器（当前命中序号 / 总命中数），`‹` / `›` 按钮或键盘 `⌘G` / `⇧⌘G` 在匹配间移动；当前匹配行以橙点（`accessoryView`）+ 淡橙背景标记，并自动 `scrollToRow` 定位；切换匹配时同步 reload 旧/新两行，避免复用 cell 残留高亮；首次键入搜索词时自动滚到首条命中。

## [1.2.0] - 2026-09-16

### 改进
- **P3 多 window / Scene 增强**：监听 `UISceneDidActivateNotification`，面板窗口（`VConsoleController.consoleWindow`）与悬浮球承载窗口自动重绑到当前激活的 `UIWindowScene`，iPad 多窗口 / Stage Manager 下调试入口不丢失。

## [1.1.0] - 2026-09-16

### 新增
- **P0 崩溃 / 异常 / 主线程卡顿捕获**（`VConsoleCrashReporter`）：`NSSetUncaughtExceptionHandler` + 信号 Handler（SIGABRT/SIGSEGV/SIGBUS/SIGILL/SIGFPE/SIGTRAP）+ 主线程 watchdog。崩溃信息写入日志面板（ERROR 级）并落盘 `vconsole-last-crash.log`，下次启动由 `replayLastCrashIfAny` 回填。
- **P1 隐私脱敏**（`VConsoleRedactor`）：网络/日志中的 `Authorization`、token、密码类键值、身份证号、银行卡号自动涂抹（默认开启）。提供 `VConsole.setRedactionEnabled:` 与 `+ addCustomPattern:replacement:` 自定义规则；设置页新增「崩溃捕获 / 隐私脱敏 / 摇一摇唤起」三个开关。
- **P2 网络时间轴**：`VConsoleNetworkEntry.ttfbMs` 记录首字节耗时（TTFB），详情页展示 TTFB + 总耗时分段时间轴条。
- **P2 存储面板补全**：新增只读的「WebView 数据」（WKWebsiteDataStore 的 Cookie / localStorage 站点）与「Keychain」（通用密码属性，不取明文）两段。
- **P2 SwiftUI 包装**：`Examples/SwiftUIExample.swift` 提供 Swift 接入与 `.onAppear { VConsole.start() }` 注入示例（库本身 `@import VConsole` 即可在 Swift 中直接调用）。
- **P3 摇一摇唤起**：`VConsole.setShakeToToggleEnabled:` + 设置页开关，摇动设备即可切换面板。

### 工程化
- 新增 GitHub Actions CI（`.github/workflows/ci.yml`）：每次 push/PR 自动 `xcodebuild` 编译 + 运行单测。
- 单测新增 `testRedactor` / `testCrashReporter`。

## [1.0.0] - 2026-09-12

### 初始发布
- 日志 / 网络 / 存储 / 系统 四面板；H5 console + 网络捕获（WKWebView JS 钩子）。
- 网络抓包（NSURLProtocol）+ 本地 Mock 中心 + curl 还原。
- 设置页（主题 / 级别过滤 / 抓包 / Mock / 导出相册 / 导出文件 / 慢请求阈值 / 清空）。
- CocoaPods + SPM 双分发；Release 构建零开销。
