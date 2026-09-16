# Changelog

## [1.2.0] - 2026-09-16

### 新增
- **P3 视图树面板（Element）**（`VConsoleElementViewController`，Tab「视图」）：递归检视当前 App 的 UIView 层级（对标 H5 vConsole 的 Element 面板）。逐节点展示类名 / frame / alpha / hidden / tag / 子视图数，支持点击展开/折叠，下拉刷新；自动过滤 vConsole 自身浮层窗口，只呈现业务视图。
- **P3 性能面板（Performance）**（`VConsolePerformanceViewController`，Tab「性能」）：`CADisplayLink` 实时 FPS + 基于 `mach` 的 App CPU 占用与常驻内存，含 FPS 折线 sparkline 与颜色分级（≥50 绿 / 30~50 橙 / <30 红）。仅在面板可见时采样，切走即停，零常驻开销。
- **P3 多 window / Scene 增强**：监听 `UISceneDidActivateNotification`，面板窗口（`VConsoleController.consoleWindow`）与悬浮球承载窗口自动重绑到当前激活的 `UIWindowScene`，iPad 多窗口 / Stage Manager 下调试入口不丢失。
- 新增 `VConsoleMetrics` 指标模块（`VConsoleAppCPUUsage` / `VConsoleAppMemoryMB` / 字节与百分比格式化），供性能面板与单测复用。

### 面板容器
- `VConsolePanelTab` 枚举新增 `VConsolePanelTabElement = 4` / `VConsolePanelTabPerformance = 5`；Tab 数量由硬编码 4 解耦为常量 `kVConsoleTabCount = 6`，角标 / 键盘快捷键（⌘1~⌘6）/ 无障碍文案按 Tab 数动态适配。

### 工程化
- 单测新增 `testMetrics`（8 断言：字节/百分比格式化 + 运行时内存/CPU 可读取），共 80 项全过。
- 测试脚本链接补 `-lSystem`，确保 mach 符号在模拟器中可解析。

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
