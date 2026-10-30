#!/bin/bash
# 保存 SwiftUI 源码或资源后，自动重建、安装并打开蛋六日记。
# 停止监听：在本终端按 Ctrl-C。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/蛋六日记.xcodeproj"
SCHEME="蛋六日记"
BUNDLE_IDENTIFIER="com.danliu.diary"
DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
SIMULATOR_NAME="${SIMULATOR_NAME:-iPhone 18 Pro}"
SOURCE_DIR="$ROOT_DIR/蛋六日记"

ensure_simulator() {
  if ! xcrun simctl list devices | grep -q '(Booted)'; then
    echo "▶ 正在启动模拟器：$SIMULATOR_NAME"
    xcrun simctl boot "$SIMULATOR_NAME" 2>/dev/null || true
    xcrun simctl bootstatus booted -b
  fi
  # 某些 Xcode 安装不提供独立 Simulator.app；simctl 仍可正常管理设备。
}

build_and_launch() {
  echo "\n▶ 检测到改动，正在编译并刷新模拟器…"
  xcodebuild build \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    CODE_SIGNING_ALLOWED=NO \
    | tail -n 20

  xcrun simctl install booted "$DERIVED_DATA_PATH/Build/Products/Debug-iphonesimulator/蛋六日记.app"
  xcrun simctl launch --terminate-running-process booted "$BUNDLE_IDENTIFIER"
  echo "✓ 已刷新蛋六日记；继续监听保存。"
}

source_signature() {
  find "$SOURCE_DIR" -type f \( -name '*.swift' -o -name '*.xcassets' -o -name '*.json' -o -name '*.png' \) -print0 \
    | xargs -0 stat -f '%m %N' \
    | shasum
}

ensure_simulator
last_signature=""
echo "正在监听 ${SOURCE_DIR}（按 Ctrl-C 停止）"
while true; do
  current_signature="$(source_signature)"
  if [[ "$current_signature" != "$last_signature" ]]; then
    last_signature="$current_signature"
    build_and_launch
  fi
  sleep 1
done
