#!/bin/bash
# 编译并在 iOS 模拟器内运行 vconsole 单元测试（纯逻辑，无 UI 依赖）
# 用法: bash Tests/run_tests.sh
set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
LIB_SRC="$ROOT/Sources/vconsole"
TESTS_SRC="$SCRIPT_DIR"
OUT="$ROOT/build/tests"

echo "==> 测试源码: $TESTS_SRC"
mkdir -p "$OUT"

SIM_SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"

# 选模拟器：优先复用已启动设备
SIM_UDID="$(xcrun simctl list devices | grep '(Booted)' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
if [ -z "$SIM_UDID" ]; then
  SIM_UDID="$(xcrun simctl list devices available | grep -E '^\s+\S.*\([0-9A-Fa-f-]{36}\)' | head -1 | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
  if [ -z "$SIM_UDID" ]; then
    echo "!! 未找到可用模拟器"; exit 1
  fi
  xcrun simctl boot "$SIM_UDID" || true
fi
echo "==> 使用模拟器: $SIM_UDID"

# 只编译库源码 + 测试 main（不含 Demo，Demo 自带 main 函数会冲突）
SRCS="$(find "$LIB_SRC" "$TESTS_SRC" -name '*.m' ! -path "$ROOT/Demo/*" | tr '\n' ' ')"

echo "==> 编译测试可执行文件..."
xcrun --sdk iphonesimulator clang \
  -target arm64-apple-ios15.0-simulator \
  -fobjc-arc -fobjc-exceptions -ObjC -DDEBUG=1 \
  -I"$LIB_SRC" \
  -isysroot "$SIM_SDK" \
  $SRCS \
  -framework UIKit -framework Foundation -framework Photos -framework WebKit \
  -framework CoreGraphics -framework QuartzCore -framework Security \
  -lSystem \
  -o "$OUT/vcs_tests" || { echo "!! 编译失败"; exit 1; }

echo "==> 运行测试..."
xcrun simctl spawn "$SIM_UDID" "$OUT/vcs_tests"
EXIT=$?
if [ $EXIT -eq 0 ]; then
  echo "==> 全部测试通过"
else
  echo "!! 存在失败用例"
fi
exit $EXIT
