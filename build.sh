#!/bin/bash
# 使用 iPhoneSimulator SDK 直接编译打包 vconsole，并安装/启动到模拟器验证稳定性。
# 用法: bash build.sh
set -u

APP_NAME="vconsole"
BUNDLE_ID="com.vconsole.ios"
DEPLOY="15.0"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIB_SRC="$SCRIPT_DIR/Sources/vconsole"    # 库源码（同时被 podspec / Package.swift 引用）
DEMO_SRC="$SCRIPT_DIR/Demo"                # 演示 App 源码（不进库）
OUT="$SCRIPT_DIR/build"
APP="$OUT/$APP_NAME.app"

echo "==> 库源码目录: $LIB_SRC"
echo "==> Demo 目录: $DEMO_SRC"
SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
echo "==> Simulator SDK: $SIM_SDK"

# ---------- 模拟器选择：优先复用已启动设备，否则启动第一个可用设备 ----------
SIM_UDID="$(xcrun simctl list devices | grep '(Booted)' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
if [ -z "$SIM_UDID" ]; then
  SIM_UDID="$(xcrun simctl list devices available | grep -E '^\s+\S.*\([0-9A-Fa-f-]{36}\)' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
  if [ -z "$SIM_UDID" ]; then
    echo "!! 未找到可用模拟器，请先在 Xcode 中创建"; exit 1
  fi
  echo "==> 启动模拟器 $SIM_UDID"
  xcrun simctl boot "$SIM_UDID" || true
  xcrun simctl bootstatus "$SIM_UDID" -b || true
fi
echo "==> 使用模拟器: $SIM_UDID"

rm -rf "$APP"
mkdir -p "$APP"

SRCS="$(find "$LIB_SRC" "$DEMO_SRC" -name '*.m' | tr '\n' ' ')"
echo "==> 编译源文件:"
find "$LIB_SRC" "$DEMO_SRC" -name '*.m'

# -DDEBUG=1：与 Xcode Debug 配置一致，激活 VConsoleLog 宏与 #ifdef DEBUG 分支
xcrun --sdk iphonesimulator clang \
  -target arm64-apple-ios${DEPLOY}-simulator \
  -fobjc-arc -fobjc-exceptions -ObjC -DDEBUG=1 \
  -I"$LIB_SRC" \
  $SRCS \
  -framework UIKit -framework Foundation -framework Photos -framework WebKit \
  -framework CoreGraphics -framework QuartzCore -framework Security -lSystem \
  -o "$APP/$APP_NAME" || { echo "!! 编译失败"; exit 1; }

echo "==> 编译成功，生成可执行文件"

# Info.plist：把 $(...) 占位符替换为字面量（手动打包不走 xcodebuild，用 sed 避免依赖外部 Python）
sed -e 's/\$(EXECUTABLE_NAME)/vconsole/g' \
    -e 's/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.vconsole.ios/g' \
    -e 's/\$(PRODUCT_NAME)/vconsole/g' \
    -e 's/\$(IPHONEOS_DEPLOYMENT_TARGET)/15.0/g' \
    "$SCRIPT_DIR/Info.plist" > "$APP/Info.plist" || { echo "!! 写入 Info.plist 失败"; exit 1; }
echo "==> 已写入 Info.plist"

chmod +x "$APP/$APP_NAME"
echo "==> 打包完成: $APP"

echo "==> 安装到模拟器"
xcrun simctl install "$SIM_UDID" "$APP" || { echo "!! 安装失败"; exit 1; }

echo "==> 启动 App"
xcrun simctl launch "$SIM_UDID" "$BUNDLE_ID" || { echo "!! 启动失败"; exit 1; }

echo "==> 等待 4s 采集日志..."
sleep 4

echo "==> 运行日志（过滤 vconsole 进程）:"
xcrun simctl spawn "$SIM_UDID" log show --last 10s --predicate 'process CONTAINS "vconsole"' 2>/dev/null | tail -50 || echo "(无日志输出)"

echo "==> 验证进程是否存活:"
# 新版模拟器镜像已不带 ps，改用 launchctl list 查询
xcrun simctl spawn "$SIM_UDID" launchctl list 2>/dev/null | grep -q "UIKitApplication:$BUNDLE_ID" \
  && echo "App 运行中" \
  || echo "(进程未找到，可能已退出)"
echo "DONE"
