// swift-tools-version:5.9
// vconsole — 仿 H5 vConsole 的 iOS 原生调试面板（Objective-C）
//
// SPM 接入方式：
//   1. Xcode: File > Add Package Dependencies > Add Local（选择本目录）
//   2. Package.swift 依赖：
//        .package(path: "../vconsole-ios")
//   3. 远程（发布后替换为真实仓库地址）：
//        .package(url: "https://github.com/yourname/vconsole-ios.git", from: "1.0.0")
//
// 引入后使用：
//   Objective-C:  #import <VConsole/VConsole.h>  或  @import VConsole;
//   Swift:        import VConsole
//   接入：        VConsole.start()
import PackageDescription

let package = Package(
    name: "VConsole",
    platforms: [
        .iOS(.v9)
    ],
    products: [
        .library(name: "VConsole", targets: ["VConsole"])
    ],
    targets: [
        .target(
            name: "VConsole",
            path: "Sources/vconsole",
            // 平铺布局：所有公开头文件就在目标根目录，目录内 quoted import 可直接解析
            publicHeadersPath: ".",
            cSettings: [
                // Xcode 集成时 Debug 构建通常已自带 DEBUG 定义；这里显式兜底，
                // 保证 swift build / 其他构建路径下 #ifdef DEBUG 门控同样生效
                .define("DEBUG", .when(configuration: .debug))
            ],
            linkerSettings: [
                .linkedFramework("UIKit"),
                .linkedFramework("Foundation"),
                .linkedFramework("Photos"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
