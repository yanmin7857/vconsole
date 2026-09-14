Pod::Spec.new do |s|
  s.name             = 'VConsole'
  s.version          = '1.0.0'
  s.summary          = 'vConsole 风格的 iOS 原生调试面板（Objective-C）。'

  s.description      = <<-DESC
  仿 H5 vConsole 的 iOS 原生调试工具面板：
  * 日志面板：分级采集（Verbose~Error）、NSLog/stderr 捕获、级别过滤、JSON 美化、导出相册
  * 网络面板：NSURLProtocol 全局抓包 + WKWebView 页面内 fetch/XHR 捕获（JS 钩子自动注入），记录请求/响应头、Body、状态码、耗时，可开关
  * 存储面板：UserDefaults 键值查看、沙盒文件浏览（搜索 + 文本预览）
  * 系统面板：设备/系统/磁盘/电量等信息
  * 一行接入：[VConsole attachToWindow:window]；DEBUG 构建生效，Release 自动零开销
  DESC

  # TODO: 发布前替换为真实的仓库地址与作者信息
  s.homepage         = 'https://github.com/yourname/vconsole-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'yourname' => 'yourname@example.com' }
  s.source           = { :git => 'https://github.com/yourname/vconsole-ios.git', :tag => s.version.to_s }

  s.platform         = :ios, '9.0'
  s.requires_arc     = true

  s.source_files        = 'Sources/vconsole/**/*.{h,m}'
  # 公开头必须自洽：伞头只能 #import 同样被标成 public 的头。
  # 内部 VC / 抓包实现头保持私有，避免宿主编译时 'VConsoleXxx.h' file not found。
  s.public_header_files = [
    'Sources/vconsole/VConsole.h',
    'Sources/vconsole/VConsoleLogger.h',
    'Sources/vconsole/VConsoleLogEntry.h',
  ]
  s.frameworks          = 'UIKit', 'Foundation', 'Photos', 'WebKit'

  # 关键：宿主 App 的 DEBUG 宏不会自动传入 Pod target（CocoaPods 只注入 COCOAPODS=1）。
  # 库内所有能力都由 #ifdef DEBUG 门控，不显式传递时消费方的 Debug 构建
  # 会编译出空实现——悬浮球完全不出现。用条件 xcconfig 仅在 Debug 配置注入。
  # DEFINES_MODULE：生成 module.modulemap，让 @import VConsole 在静态库（无 use_frameworks）下也能用。
  # 注意：s.modular_headers 不是 podspec 属性（CocoaPods 1.13 会直接报错），模块化走 xcconfig。
  s.pod_target_xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS[config=Debug]' => 'DEBUG=1 $(inherited)',
    'DEFINES_MODULE' => 'YES',
    'PRODUCT_MODULE_NAME' => 'VConsole'
  }

  # 本地开发验证（Demo 工程不依赖 pod，独立编译）：
  #   pod lib lint VConsole.podspec --platforms=ios --skip-tests --allow-warnings
  # 宿主 App Podfile 示例：
  #   pod 'VConsole', :path => '../vconsole-ios'        # 本地路径
  #   pod 'VConsole', :git => 'https://github.com/yourname/vconsole-ios.git'  # 远程
end
