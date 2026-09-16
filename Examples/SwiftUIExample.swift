//
//  SwiftUIExample.swift
//  vconsole — Swift / SwiftUI 接入示例（参考文件，不参与库编译）
//
//  库本身为 Objective-C，Swift 项目直接 `@import VConsole` 即可调用。
//  下面演示如何在 SwiftUI App 中挂载面板，以及利用新增能力。
//

import SwiftUI
import VConsole            // 库模块（CocoaPods/SPM 接入后可用）
import WebKit

@main
struct MyApp: App {
    init() {
        // 最简：DEBUG 下挂载悬浮球（Release 自动零开销）
        #if DEBUG
        VConsole.start()

        // 进阶开关（可选）
        VConsole.setCrashReportingEnabled(true)   // 崩溃/异常/卡顿捕获
        VConsole.setRedactionEnabled(true)        // 隐私脱敏（默认已开）
        // VConsole.setShakeToToggleEnabled(true) // 摇一摇唤起
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Button("打开调试面板") { VConsole.show() }
            Button("切换面板")     { VConsole.toggle() }
            Button("切到网络面板") { VConsole.selectPanelTab(.network) }
            WebView(url: URL(string: "https://example.com")!)
        }
        // 也可在视图生命周期里挂载，效果等同 VConsole.start()
        .onAppear { VConsole.start() }
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> WKWebView {
        WKWebView()
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.load(URLRequest(url: url))
    }
}
