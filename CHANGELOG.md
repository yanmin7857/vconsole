# Changelog

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
