#!/bin/bash
#
# QuickRightClick 一键安装脚本
#
#   ./install.sh              # 自动使用钥匙串里的 Apple Development 证书签名
#   ./install.sh ABCDE12345   # 指定团队 ID（Xcode → Settings → Accounts 里能看到）
#
# 做四件事：Release 构建 → 安装到 /Applications → 注册并启用 Finder 扩展 → 重启 Finder。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="QuickRightClick"
EXTENSION_ID="com.local.QuickRightClick.Extension"
INSTALL_DIR="/Applications"
DERIVED="$SCRIPT_DIR/build"
PROJECT="$SCRIPT_DIR/QuickRightClick.xcodeproj"

info() { printf "\033[1;34m==>\033[0m %s\n" "$1"; }
warn() { printf "\033[1;33m!!\033[0m %s\n" "$1"; }
fail() {
    printf "\033[1;31mxx\033[0m %s\n" "$1" >&2
    exit 1
}

# ---------- 0. 环境检查 ----------

[ "$(uname -s)" = "Darwin" ] || fail "只能在 macOS 上运行。"

command -v xcodebuild >/dev/null 2>&1 \
    || fail "找不到 xcodebuild。请安装 Xcode，并执行：sudo xcode-select -s /Applications/Xcode.app"

info "Xcode：$(xcodebuild -version | head -1)"

[ -d "$INSTALL_DIR" ] || fail "找不到 $INSTALL_DIR。"
[ -w "$INSTALL_DIR" ] || fail "$INSTALL_DIR 不可写，请用 sudo 运行，或把 App 安装到别处。"

# ---------- 1. 确定签名团队 ----------

TEAM_ID="${1:-${TEAM_ID:-}}"
if [ -z "$TEAM_ID" ]; then
    # 团队 ID 在证书主体的 OU 字段里。
    # 注意不能用 `security find-identity` 输出里括号内的值——那是个人 ID，不是团队 ID。
    TEAM_ID="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
        | openssl x509 -noout -subject -nameopt RFC2253 2>/dev/null \
        | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p')"
fi
if [ -z "$TEAM_ID" ] && [ -d "$INSTALL_DIR/$APP_NAME.app" ]; then
    # 兜底：从已安装版本的签名里读团队 ID（升级场景）
    TEAM_ID="$(codesign -dv --verbose=4 "$INSTALL_DIR/$APP_NAME.app" 2>&1 \
        | sed -n 's/^TeamIdentifier=\([A-Z0-9]*\)$/\1/p')"
fi
if [ -z "$TEAM_ID" ]; then
    fail "未找到 Apple Development 签名证书。

   Finder 扩展必须由受信任的证书签名，ad-hoc 签名无法被系统加载。
   解决方式（免费 Apple ID 即可）：
     1. 打开 Xcode → Settings → Accounts → 添加 Apple ID
     2. 重新运行本脚本，或手动指定团队：./install.sh YOUR_TEAM_ID"
fi
info "签名团队：$TEAM_ID"

# ---------- 2. 构建 ----------

info "构建 Release（首次构建约 1 分钟）…"
BUILD_LOG="$SCRIPT_DIR/build.log"
if ! xcodebuild -project "$PROJECT" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates \
    build > "$BUILD_LOG" 2>&1; then
    tail -30 "$BUILD_LOG"
    fail "构建失败，完整日志：$BUILD_LOG"
fi

APP_PATH="$DERIVED/Build/Products/Release/$APP_NAME.app"
[ -d "$APP_PATH" ] || fail "构建产物不存在：$APP_PATH"

# ---------- 3. 安装 ----------

info "安装到 $INSTALL_DIR …"
osascript -e "quit app \"$APP_NAME\"" >/dev/null 2>&1 || true
pkill -f "$APP_NAME.app" >/dev/null 2>&1 || true
sleep 1
rm -rf "$INSTALL_DIR/$APP_NAME.app"
cp -R "$APP_PATH" "$INSTALL_DIR/"

# ---------- 4. 注册并启用扩展 ----------

info "注册并启用 Finder 扩展 …"
pluginkit -a "$INSTALL_DIR/$APP_NAME.app/Contents/PlugIns/${APP_NAME}Extension.appex"
pluginkit -e use -i "$EXTENSION_ID"

# ---------- 5. 重启 Finder ----------

info "重启 Finder（系统只在 Finder 启动时加载扩展）…"
killall Finder >/dev/null 2>&1 || true
sleep 2

# ---------- 6. 启动并自检 ----------

open -a "$INSTALL_DIR/$APP_NAME.app"

if pluginkit -m -i "$EXTENSION_ID" | grep -q "$EXTENSION_ID"; then
    info "安装完成。在任意文件夹里选中文件右键试试。"
else
    warn "扩展尚未出现在系统列表里，请手动启用：
   系统设置 → 通用 → 登录项与扩展 → 文件提供程序
   （注意不是「Finder」那一节。启用后可再运行 ./install.sh 或 enable-extension.command）"
fi
