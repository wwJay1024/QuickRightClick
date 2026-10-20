#!/bin/bash
# 注册并启用 QuickRightClick 的 Finder 扩展。
#
# macOS Sequoia 不会自动加载 App 内嵌的 Finder 扩展，首次安装后需要执行一次本脚本。
# 双击本文件即可运行。

set -u

APP="/Applications/QuickRightClick.app"
APPEX="$APP/Contents/PlugIns/QuickRightClickExtension.appex"
EXTENSION_ID="com.local.QuickRightClick.Extension"

echo "=============================================="
echo " QuickRightClick 扩展启用工具"
echo "=============================================="
echo

if [ ! -d "$APP" ]; then
    echo "找不到 $APP"
    echo "请先在 Xcode 里按 Cmd+R 运行一次，或把编译产物复制到「应用程序」文件夹。"
    echo
    read -n 1 -s -r -p "按任意键关闭..."
    exit 1
fi

if [ ! -d "$APPEX" ]; then
    echo "应用内没有找到扩展：$APPEX"
    echo
    read -n 1 -s -r -p "按任意键关闭..."
    exit 1
fi

echo "第 1 步 / 3：注册扩展"
pluginkit -a "$APPEX" && echo "    完成"
echo

echo "第 2 步 / 3：启用扩展"
pluginkit -e use -i "$EXTENSION_ID" && echo "    完成"
echo

echo "第 3 步 / 3：重启 Finder"
killall Finder 2>/dev/null && echo "    完成" || echo "    失败，可稍后手动执行 killall Finder"
echo

echo "----- 当前状态 -----"
if pluginkit -m -i "$EXTENSION_ID" | grep -q "$EXTENSION_ID"; then
    pluginkit -m -i "$EXTENSION_ID" | sed 's/^/  /'
    echo
    echo "=============================================="
    echo " 已就绪。现在在任意文件夹里右键试试。"
    echo "=============================================="
else
    echo "  扩展未出现在系统列表中。"
    echo
    echo "=============================================="
    echo " 请手动启用："
    echo "   系统设置 → 通用 → 登录项与扩展 → 文件提供程序"
    echo "   在列表里打开 QuickRightClick 的开关"
    echo
    echo " 注意不是「Finder」那一节，Finder 右键扩展归在「文件提供程序」下。"
    echo "=============================================="
fi
echo
read -n 1 -s -r -p "按任意键关闭..."
