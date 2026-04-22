#!/bin/bash

set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CORE_SCRIPT="$DIR/extract_all_ipcc.sh"
IPSW_TOOL="${IPSW_TOOL:-/opt/homebrew/bin/ipsw}"
APP_HOME="$DIR/.ipsw_app_home"

escape_sq() {
    printf "%s" "$1" | sed "s/'/'\\\\''/g"
}

run_ipsw() {
    HOME="$APP_HOME" "$IPSW_TOOL" "$@" 2>/dev/null || return 1
}

detect_device_code() {
    mkdir -p "$APP_HOME/.config/ipsw"
    local raw
    raw="$(run_ipsw idev list -i -j || true)"
    [ -n "$raw" ] || return 1
    python3 - <<'PY' "$raw"
import json, sys
try:
    data = json.loads(sys.argv[1])
except Exception:
    sys.exit(1)
if isinstance(data, list) and data:
    item = data[0]
    for key in ("product_type", "ProductType", "device", "Device"):
        if isinstance(item, dict) and item.get(key):
            print(item[key])
            break
PY
}

latest_label() {
    local device="$1"
    local kind="$2"
    mkdir -p "$APP_HOME/.config/ipsw"
    local raw
    if [ "$kind" = "release" ]; then
        raw="$(run_ipsw download appledb --show-latest --os iOS --device "$device" --release || true)"
    else
        raw="$(run_ipsw download appledb --show-latest --os iOS --device "$device" --beta || true)"
    fi
    [ -n "$raw" ] || return 0
    printf "%s" "$raw" | python3 - <<'PY'
import re, sys
text = sys.stdin.read()
lines = [l.strip() for l in text.splitlines() if l.strip()]
if not lines:
    raise SystemExit(0)
for line in reversed(lines):
    if re.search(r'\b\d+[A-Z]?\d+[a-z]?\b', line) or re.search(r'\b\d+(?:\.\d+)+(?:\s*(?:beta|rc)\s*\d+)?\b', line, re.I):
        print(line)
        raise SystemExit(0)
print(lines[-1])
PY
}

choose_language() {
    osascript <<'APPLESCRIPT'
set picked to choose from list {"中文", "English"} with prompt "Choose language / 选择语言" default items {"中文"}
if picked is false then error number -128
return item 1 of picked
APPLESCRIPT
}

ask_text() {
    local prompt="$1"
    local default_value="${2:-}"
    osascript <<APPLESCRIPT
text returned of (display dialog "$(escape_sq "$prompt")" default answer "$(escape_sq "$default_value")")
APPLESCRIPT
}

choose_mode() {
    local lang="$1"
    local stable_info="$2"
    local beta_info="$3"
    local stable_suffix=""
    local beta_suffix=""
    [ -n "$stable_info" ] && stable_suffix=" - $stable_info"
    [ -n "$beta_info" ] && beta_suffix=" - $beta_info"
    if [ "$lang" = "zh" ]; then
        osascript <<APPLESCRIPT
set picked to choose from list {"1 最新正式版$(escape_sq "$stable_suffix")", "2 最新 Beta$(escape_sq "$beta_suffix")", "3 指定版本号", "4 指定构建号"} with prompt "请选择下载模式" default items {"1 最新正式版$(escape_sq "$stable_suffix")"}
if picked is false then error number -128
return text 1 thru 1 of (item 1 of picked)
APPLESCRIPT
    else
        osascript <<APPLESCRIPT
set picked to choose from list {"1 Latest stable release$(escape_sq "$stable_suffix")", "2 Latest beta$(escape_sq "$beta_suffix")", "3 Specific version", "4 Specific build number"} with prompt "Choose a download mode" default items {"1 Latest stable release$(escape_sq "$stable_suffix")"}
if picked is false then error number -128
return text 1 thru 1 of (item 1 of picked)
APPLESCRIPT
    fi
}

ask_yes_no() {
    local prompt="$1"
    local yes_label="$2"
    local no_label="$3"
    osascript <<APPLESCRIPT
button returned of (display dialog "$(escape_sq "$prompt")" buttons {"$(escape_sq "$no_label")", "$(escape_sq "$yes_label")"} default button "$(escape_sq "$yes_label")")
APPLESCRIPT
}

lang_label="$(choose_language)"
if [ "$lang_label" = "English" ]; then
    LANG_MODE="en"
else
    LANG_MODE="zh"
fi

DETECTED_DEVICE="$(detect_device_code || true)"

if [ "$LANG_MODE" = "zh" ]; then
    DEVICE_CODE="$(ask_text "请输入机型代号，例如 iPhone18,2。如果已连接手机，会自动带出默认值。" "$DETECTED_DEVICE")"
else
    DEVICE_CODE="$(ask_text "Enter the device identifier, for example iPhone18,2. If an iPhone is connected, it will be used as the default." "$DETECTED_DEVICE")"
fi
[ -n "$DEVICE_CODE" ] || exit 1

LATEST_STABLE="$(latest_label "$DEVICE_CODE" release || true)"
LATEST_BETA="$(latest_label "$DEVICE_CODE" beta || true)"
DOWNLOAD_MODE="$(choose_mode "$LANG_MODE" "$LATEST_STABLE" "$LATEST_BETA")"
VERSION_INPUT=""
BUILD_INPUT=""

case "$DOWNLOAD_MODE" in
    3)
        if [ "$LANG_MODE" = "zh" ]; then
            VERSION_INPUT="$(ask_text "请输入 iOS 版本号，例如 26.5 或 18.2" "")"
        else
            VERSION_INPUT="$(ask_text "Enter the iOS version, for example 26.5 or 18.2" "")"
        fi
        [ -n "$VERSION_INPUT" ] || exit 1
        ;;
    4)
        if [ "$LANG_MODE" = "zh" ]; then
            BUILD_INPUT="$(ask_text "请输入构建号，例如 23F5059e" "")"
        else
            BUILD_INPUT="$(ask_text "Enter the build number, for example 23F5059e" "")"
        fi
        [ -n "$BUILD_INPUT" ] || exit 1
        ;;
esac

if [ "$LANG_MODE" = "zh" ]; then
    CLEAN_REPLY="$(ask_yes_no "提取完成后，是否清理中间文件并只保留整理好的 IPCC？" "清理" "保留")"
    DELETE_REPLY="$(ask_yes_no "如果选择清理，是否顺手删除下载的 IPSW 文件？" "删除" "保留")"
else
    CLEAN_REPLY="$(ask_yes_no "After extraction, clean intermediate files and keep only organized IPCC output?" "Clean" "Keep")"
    DELETE_REPLY="$(ask_yes_no "If cleaning is enabled, also delete the downloaded IPSW file?" "Delete" "Keep")"
fi

if [[ "$CLEAN_REPLY" =~ ^(清理|Clean)$ ]]; then
    CLEAN_CONFIRM="y"
else
    CLEAN_CONFIRM="n"
fi

if [[ "$DELETE_REPLY" =~ ^(删除|Delete)$ ]]; then
    DELETE_IPSW="y"
else
    DELETE_IPSW="n"
fi

terminal_cmd="cd '$(escape_sq "$DIR")' && LANG_MODE='$(escape_sq "$LANG_MODE")' DEVICE_CODE_OVERRIDE='$(escape_sq "$DEVICE_CODE")' DOWNLOAD_MODE_OVERRIDE='$(escape_sq "$DOWNLOAD_MODE")' VERSION_INPUT_OVERRIDE='$(escape_sq "$VERSION_INPUT")' BUILD_INPUT_OVERRIDE='$(escape_sq "$BUILD_INPUT")' AUTO_CONFIRM_OVERRIDE='y' CLEAN_CONFIRM_OVERRIDE='$(escape_sq "$CLEAN_CONFIRM")' DELETE_IPSW_OVERRIDE='$(escape_sq "$DELETE_IPSW")' OPEN_FINAL_DIR_OVERRIDE='y' '$CORE_SCRIPT'; echo; echo 'Press Enter to close...'; read"

osascript <<APPLESCRIPT
tell application "Terminal"
    activate
    do script "$(escape_sq "$terminal_cmd")"
end tell
APPLESCRIPT
