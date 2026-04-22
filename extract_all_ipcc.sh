#!/bin/bash

set -euo pipefail

LANG_MODE="${LANG_MODE:-zh}"
IPSW_TOOL="${IPSW_TOOL:-/opt/homebrew/bin/ipsw}"
WORK_ROOT="${WORK_ROOT:-$(pwd)}"
BREW_TOOL="${BREW_TOOL:-/opt/homebrew/bin/brew}"
LOCAL_IPSW_FILE="${LOCAL_IPSW_FILE_OVERRIDE:-}"

msg() {
    case "${LANG_MODE}:$1" in
        zh:title) echo "全自动 IPSW -> IPCC 提取脚本" ;;
        en:title) echo "Automatic IPSW -> IPCC Extractor" ;;
        zh:device_prompt) echo "请输入机型代号（例如 iPhone18,2）:" ;;
        en:device_prompt) echo "Enter device identifier (for example iPhone18,2):" ;;
        zh:download_mode) echo "请选择下载模式：" ;;
        en:download_mode) echo "Choose a download mode:" ;;
        zh:mode_1) echo "1) 最新正式版" ;;
        en:mode_1) echo "1) Latest stable release" ;;
        zh:mode_2) echo "2) 最新 Beta" ;;
        en:mode_2) echo "2) Latest beta" ;;
        zh:mode_3) echo "3) 指定版本号" ;;
        en:mode_3) echo "3) Specific version" ;;
        zh:mode_4) echo "4) 指定构建号" ;;
        en:mode_4) echo "4) Specific build number" ;;
        zh:mode_input) echo "输入 1/2/3/4:" ;;
        en:mode_input) echo "Enter 1/2/3/4:" ;;
        zh:version_prompt) echo "请输入 iOS 版本号（例如 26.5 或 18.2）:" ;;
        en:version_prompt) echo "Enter the iOS version (for example 26.5 or 18.2):" ;;
        zh:build_prompt) echo "请输入构建号（例如 23F5059e）:" ;;
        en:build_prompt) echo "Enter the build number (for example 23F5059e):" ;;
        zh:confirm_start) echo "确认开始下载并提取？(y/N):" ;;
        en:confirm_start) echo "Start download and extraction now? (y/N):" ;;
        zh:installing_ipsw) echo "未检测到 ipsw，开始自动安装..." ;;
        en:installing_ipsw) echo "ipsw not found, installing automatically..." ;;
        zh:no_brew) echo "错误：未找到 ipsw，也未检测到 Homebrew。请先安装 Homebrew，再执行 brew install ipsw" ;;
        en:no_brew) echo "Error: ipsw not found and Homebrew is unavailable. Install Homebrew first, then run brew install ipsw" ;;
        zh:carrier_testing) echo "步骤0: 开启 carrier-testing..." ;;
        en:carrier_testing) echo "Step 0: Enable carrier-testing..." ;;
        zh:extract_aea) echo "步骤1: 提取文件系统 AEA..." ;;
        en:extract_aea) echo "Step 1: Extract filesystem AEA..." ;;
        zh:largest_aea) echo "步骤2: 查找最大的 .dmg.aea..." ;;
        en:largest_aea) echo "Step 2: Find the largest .dmg.aea..." ;;
        zh:decrypt_dmg) echo "步骤3: 解密 .dmg.aea -> .dmg..." ;;
        en:decrypt_dmg) echo "Step 3: Decrypt .dmg.aea -> .dmg..." ;;
        zh:extract_bundles) echo "步骤4: 挂载 DMG 并提取 Carrier Bundles..." ;;
        en:extract_bundles) echo "Step 4: Mount DMG and extract Carrier Bundles..." ;;
        zh:pack_ipcc) echo "步骤5: 生成全部 IPCC..." ;;
        en:pack_ipcc) echo "Step 5: Build all IPCC files..." ;;
        zh:sort_regions) echo "步骤6: 按地区整理并重命名..." ;;
        en:sort_regions) echo "Step 6: Organize and rename by region..." ;;
        zh:cleanup_prompt) echo "是否清理中间文件并只保留 IPCC？(y/N):" ;;
        en:cleanup_prompt) echo "Clean intermediate files and keep only IPCC output? (y/N):" ;;
        zh:delete_ipsw_prompt) echo "是否同时删除下载的 IPSW 文件？(y/N):" ;;
        en:delete_ipsw_prompt) echo "Also delete the downloaded IPSW file? (y/N):" ;;
        zh:guide_title) echo "简单安装指引：" ;;
        en:guide_title) echo "Quick install guide:" ;;
        zh:done) echo "完成" ;;
        en:done) echo "Done" ;;
        *) echo "$1" ;;
    esac
}

say() {
    msg "$1"
}

prompt() {
    printf "%s " "$(msg "$1")"
}

answer_yes() {
    case "${1:-}" in
        y|Y|yes|YES|Yes|true|TRUE|1) return 0 ;;
        *) return 1 ;;
    esac
}

require_tool() {
    local tool="$1"
    local hint="${2:-}"
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "Error: missing tool $tool"
        [ -n "$hint" ] && echo "$hint"
        exit 1
    fi
}

ensure_ipsw() {
    if [ -x "$IPSW_TOOL" ] || command -v ipsw >/dev/null 2>&1; then
        [ -x "$IPSW_TOOL" ] || IPSW_TOOL="$(command -v ipsw)"
        return
    fi

    if [ -x "$BREW_TOOL" ] || command -v brew >/dev/null 2>&1; then
        [ -x "$BREW_TOOL" ] || BREW_TOOL="$(command -v brew)"
        say installing_ipsw
        "$BREW_TOOL" install ipsw
        IPSW_TOOL="$(command -v ipsw)"
        return
    fi

    say no_brew
    exit 1
}

sanitize_name() {
    printf '%s' "$1" | tr ' /' '__' | tr -cd '[:alnum:]_.+-'
}

carrier_name_from_bundle() {
    local bundle_dir="$1"
    /usr/libexec/PlistBuddy -c "Print :CarrierName" "$bundle_dir/carrier.plist" 2>/dev/null || true
}

canonical_name_for_bundle() {
    local bundle_name="$1"
    local bundle_dir="$2"
    case "$bundle_name" in
        CMCC_cn) echo "China_Mobile_CN" ;;
        Unicom_cn) echo "China_Unicom_CN" ;;
        ChinaTelecom_USIM_cn) echo "China_Telecom_CN" ;;
        CBN_cn) echo "China_Broadcasting_CN" ;;
        CMCC_hk) echo "CMHK" ;;
        CMCC_HKBN_hk) echo "HKBN_on_CMHK" ;;
        PCCW_hk) echo "PCCW" ;;
        CSL_hk) echo "CSL_1010" ;;
        CSL_SunMobile_hk) echo "SunMobile" ;;
        SmarTone_hk) echo "SmarTone" ;;
        SmarTone_HKBN_hk) echo "HKBN_on_SmarTone" ;;
        Hutchison_hk) echo "3HK" ;;
        Hutchison_HKBN_hk) echo "HKBN_on_3HK" ;;
        ChinaTelecom_hk) echo "China_Telecom_HK" ;;
        Unicom_hk) echo "China_Unicom_HK" ;;
        Docomo_jp) echo "Docomo" ;;
        Softbank_jp) echo "SoftBank" ;;
        Softbank_YMobile_jp) echo "YMobile" ;;
        Rakuten_jp) echo "Rakuten" ;;
        KDDI_NR_jp) echo "au_KDDI_NR" ;;
        KDDI_LTE_only_jp) echo "au_KDDI_LTE" ;;
        KDDI_UQ_NR_jp) echo "UQ_NR" ;;
        KDDI_UQ_LTE_only_jp) echo "UQ_LTE" ;;
        KDDI_Povo_NR_jp) echo "povo_NR" ;;
        KDDI_BIGLOBE_LTE_only_jp) echo "BIGLOBE_LTE" ;;
        KDDI_JCOM_LTE_only_jp) echo "JCOM_LTE" ;;
        TMobile_US) echo "TMobile_US" ;;
        *) 
            local carrier_name
            carrier_name="$(carrier_name_from_bundle "$bundle_dir")"
            if [ -n "$carrier_name" ]; then
                sanitize_name "$carrier_name"
            else
                echo "$bundle_name"
            fi
            ;;
    esac
}

region_for_bundle() {
    local bundle_name="$1"
    case "$bundle_name" in
        *_cn|ChinaTelecom_USIM_cn|CMCC_cn|Unicom_cn|CBN_cn|ChinaTelecom_*_cn)
            echo "Mainland_China"
            ;;
        *_hk|PCCW_hk|CSL_hk|CSL_SunMobile_hk|SmarTone_hk|SmarTone_HKBN_hk|Hutchison_hk|Hutchison_HKBN_hk|ChinaTelecom_hk|Unicom_hk|CMCC_hk|CMCC_HKBN_hk)
            echo "Hong_Kong"
            ;;
        *_tw|TaiwanMobile_tw|Chunghwa_tw|FarEasTone_tw|TStar_tw)
            echo "Taiwan"
            ;;
        *_jp|Docomo_jp|Softbank_jp|Softbank_YMobile_jp|Rakuten_jp|KDDI_*)
            echo "Japan"
            ;;
        *_kr|SKTelecom_*|KT_*|LGU*|LGUplus_*|SKT_*|KTF_*)
            echo "Korea"
            ;;
        *_ca|Rogers_*|Bell_*|Telus_*|FreedomMobile_*|Videotron_*|Fido_*|Koodo_*|Virgin_ca|SaskTel_*)
            echo "Canada"
            ;;
        *_au|*_nz|Telstra_*|Optus_*|Vodafone_au|Spark_nz|OneNZ_*|2degrees_*)
            echo "Australia_NZ"
            ;;
        *_uk|*_ie|EE_*|O2_uk|Three_uk|Vodafone_uk|TescoMobile_uk|giffgaff_uk|Virgin_uk|Eir_*|Three_ie|Vodafone_ie)
            echo "UK_Ireland"
            ;;
        *_US|*_us|TMobile_*|ATT_*|Verizon_*|Sprint_*|Boost_*|MetroPCS_*|USCC_*)
            echo "USA"
            ;;
        *_de|*_fr|*_it|*_es|*_nl|*_be|*_at|*_ch|*_se|*_no|*_dk|*_fi|*_pt|*_pl|*_cz|*_sk|*_hu|*_ro|*_bg|*_hr|*_si|*_ee|*_lv|*_lt|*_gr|*_cy|*_lu|*_mt|*_me|*_mk|*_al|*_rs|*_ba|*_tr|TMobile_Germany|TMobile_pl|TMobile_nl|TMobile_hr|TMobile_cz|TMobile_sk|TMobile_hu|TMobile_at|TMobile_ro|TMobile_gr|TMobile_bg|TMobile_al|TMobile_me|TMobile_mk)
            echo "Europe"
            ;;
        *)
            echo "Other"
            ;;
    esac
}

prompt_download_mode() {
    say download_mode
    say mode_1
    say mode_2
    say mode_3
    say mode_4
    prompt mode_input
    read -r mode
    case "$mode" in
        1|2|3|4) printf '%s' "$mode" ;;
        *) echo "Invalid input"; exit 1 ;;
    esac
}

build_download_command() {
    local device="$1"
    local mode="$2"
    local version="$3"
    local build="$4"

    local cmd=("$IPSW_TOOL" download appledb --os iOS --device "$device")
    case "$mode" in
        1) cmd+=(--latest --release) ;;
        2) cmd+=(--beta --latest) ;;
        3) cmd+=(--version "$version") ;;
        4) cmd+=(--build "$build") ;;
    esac
    printf '%q ' "${cmd[@]}"
}

print_install_guide() {
    local final_dir="$1"
    echo ""
    say guide_title
    if [ "$LANG_MODE" = "zh" ]; then
        echo "  1. 脚本已自动尝试开启 carrier-testing。"
        echo "  2. 用数据线连接 iPhone，并在手机上点“信任这台电脑”。"
        echo "  3. Finder 打开你的 iPhone，停留在“通用/General”页面。"
        echo "  4. 按住 Option，点击“检查更新...”。"
        echo "  5. 在下面目录里按地区选择对应的 .ipcc："
        echo "     $final_dir"
        echo "  6. 常用地区目录：Mainland_China / Hong_Kong / Taiwan / Japan / Korea / USA / Canada / Australia_NZ / UK_Ireland / Europe。"
    else
        echo "  1. The script already tried to enable carrier-testing."
        echo "  2. Connect the iPhone with a cable and tap Trust on the device."
        echo "  3. Open the iPhone in Finder and stay on the General page."
        echo "  4. Hold Option and click Check for Update..."
        echo "  5. Pick the matching .ipcc file from this folder:"
        echo "     $final_dir"
        echo "  6. Common region folders: Mainland_China / Hong_Kong / Taiwan / Japan / Korea / USA / Canada / Australia_NZ / UK_Ireland / Europe."
    fi
}

ensure_ipsw
require_tool hdiutil
require_tool zip
require_tool unzip
require_tool find
require_tool plutil
require_tool /usr/libexec/PlistBuddy
require_tool python3
require_tool defaults

echo "=============================="
say title
echo "=============================="
echo ""

if [ -n "$LOCAL_IPSW_FILE" ]; then
    IPSW_FILE="$LOCAL_IPSW_FILE"
    DEVICE_CODE="${DEVICE_CODE_OVERRIDE:-}"
    if [ ! -f "$IPSW_FILE" ]; then
        echo "Local IPSW file not found: $IPSW_FILE"
        exit 1
    fi
else
    prompt device_prompt
    DEVICE_CODE="${DEVICE_CODE_OVERRIDE:-}"
    if [ -z "$DEVICE_CODE" ]; then
        read -r DEVICE_CODE
    else
        echo "$DEVICE_CODE"
    fi
    if [ -z "$DEVICE_CODE" ]; then
        echo "Device identifier cannot be empty."
        exit 1
    fi

    DOWNLOAD_MODE="${DOWNLOAD_MODE_OVERRIDE:-}"
    if [ -z "$DOWNLOAD_MODE" ]; then
        DOWNLOAD_MODE="$(prompt_download_mode)"
    fi
    VERSION_INPUT=""
    BUILD_INPUT=""

    if [ "$DOWNLOAD_MODE" = "3" ]; then
        prompt version_prompt
        VERSION_INPUT="${VERSION_INPUT_OVERRIDE:-}"
        if [ -z "$VERSION_INPUT" ]; then
            read -r VERSION_INPUT
        else
            echo "$VERSION_INPUT"
        fi
        [ -n "$VERSION_INPUT" ] || { echo "Version cannot be empty."; exit 1; }
    fi

    if [ "$DOWNLOAD_MODE" = "4" ]; then
        prompt build_prompt
        BUILD_INPUT="${BUILD_INPUT_OVERRIDE:-}"
        if [ -z "$BUILD_INPUT" ]; then
            read -r BUILD_INPUT
        else
            echo "$BUILD_INPUT"
        fi
        [ -n "$BUILD_INPUT" ] || { echo "Build number cannot be empty."; exit 1; }
    fi

    DOWNLOAD_CMD="$(build_download_command "$DEVICE_CODE" "$DOWNLOAD_MODE" "$VERSION_INPUT" "$BUILD_INPUT")"

    echo ""
    echo "$DOWNLOAD_CMD"
    CONFIRM="${AUTO_CONFIRM_OVERRIDE:-}"
    if [ -z "$CONFIRM" ]; then
        prompt confirm_start
        read -r CONFIRM
    else
        echo "$CONFIRM"
    fi
    if ! answer_yes "$CONFIRM"; then
        exit 0
    fi

    cd "$WORK_ROOT"
    before_download="$(find "$WORK_ROOT" -maxdepth 1 -name '*.ipsw' -type f -print)"
    eval "$DOWNLOAD_CMD"
    after_download="$(find "$WORK_ROOT" -maxdepth 1 -name '*.ipsw' -type f -print)"

    IPSW_FILE="$(comm -13 <(printf '%s\n' "$before_download" | sort) <(printf '%s\n' "$after_download" | sort) | head -1)"
    if [ -z "$IPSW_FILE" ]; then
        IPSW_FILE="$(find "$WORK_ROOT" -maxdepth 1 -name "*${DEVICE_CODE}*.ipsw" -type f | sort | tail -1)"
    fi
    if [ -z "$IPSW_FILE" ] || [ ! -f "$IPSW_FILE" ]; then
        echo "Failed to locate the downloaded IPSW."
        exit 1
    fi
fi

IPSW_FILE="$(python3 - <<'PY' "$IPSW_FILE"
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
)"

IPSW_BASENAME="$(basename "$IPSW_FILE" .ipsw)"
WORK_DIR="$WORK_ROOT/${IPSW_BASENAME}_ipcc_extraction"
RAW_DIR="$WORK_DIR/raw"
OUTPUT_DIR="$WORK_DIR/output"
IPCC_DIR="$OUTPUT_DIR/ipcc_files"
SORTED_DIR="$OUTPUT_DIR/ipcc_by_region"
IPHONE_DIR="$OUTPUT_DIR/iPhone"
mkdir -p "$RAW_DIR" "$IPCC_DIR" "$SORTED_DIR"

echo ""
say carrier_testing
defaults write com.apple.AMPDevicesAgent carrier-testing -bool YES || true

echo ""
say extract_aea
cd "$RAW_DIR"
"$IPSW_TOOL" extract --dmg fs "$IPSW_FILE"
find . -type d -name "Firmware" -exec rm -rf {} + 2>/dev/null || true

echo ""
say largest_aea
LARGEST_AEA="$(find . -name '*.dmg.aea' -type f -exec ls -ln {} + | sort -k5 -nr | head -1 | awk '{print $NF}')"
[ -n "$LARGEST_AEA" ] || { echo "No .dmg.aea found."; exit 1; }
echo "  $LARGEST_AEA"

echo ""
say decrypt_dmg
"$IPSW_TOOL" fw aea "$LARGEST_AEA"

echo ""
say extract_bundles
DMG_FILES="$(find . -name '*.dmg' -type f)"
[ -n "$DMG_FILES" ] || { echo "No decrypted .dmg found."; exit 1; }

mkdir -p "$IPHONE_DIR"
while IFS= read -r dmg_file; do
    [ -z "$dmg_file" ] && continue
    mount_point="$(mktemp -d /tmp/ipcc_mount.XXXXXX)"
    if hdiutil attach "$dmg_file" -mountpoint "$mount_point" -readonly -nobrowse -quiet; then
        carrier_path="$mount_point/System/Library/Carrier Bundles/iPhone"
        if [ -d "$carrier_path" ]; then
            cp -R "$carrier_path"/. "$IPHONE_DIR"/
            echo "  ✓ $dmg_file"
        fi
        hdiutil detach "$mount_point" -quiet || true
    fi
    rmdir "$mount_point" 2>/dev/null || true
done <<< "$DMG_FILES"

if [ -z "$(find "$IPHONE_DIR" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]; then
    echo "No carrier bundles extracted."
    exit 1
fi

echo ""
say pack_ipcc
while IFS= read -r bundle_dir; do
    [ -z "$bundle_dir" ] && continue
    bundle_name="$(basename "$bundle_dir" .bundle)"
    tmp_dir="$(mktemp -d /tmp/ipcc_pack.XXXXXX)"
    mkdir -p "$tmp_dir/Payload"
    cp -R "$bundle_dir" "$tmp_dir/Payload/"
    (
        cd "$tmp_dir"
        zip -r "$IPCC_DIR/$bundle_name.zip" Payload/ >/dev/null
    )
    mv "$IPCC_DIR/$bundle_name.zip" "$IPCC_DIR/$bundle_name.ipcc"
    rm -rf "$tmp_dir"
done < <(find "$IPHONE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

echo ""
say sort_regions
mkdir -p \
    "$SORTED_DIR/Mainland_China" \
    "$SORTED_DIR/Hong_Kong" \
    "$SORTED_DIR/Taiwan" \
    "$SORTED_DIR/Japan" \
    "$SORTED_DIR/Korea" \
    "$SORTED_DIR/USA" \
    "$SORTED_DIR/Canada" \
    "$SORTED_DIR/Australia_NZ" \
    "$SORTED_DIR/UK_Ireland" \
    "$SORTED_DIR/Europe" \
    "$SORTED_DIR/Other"

while IFS= read -r bundle_dir; do
    [ -z "$bundle_dir" ] && continue
    bundle_name="$(basename "$bundle_dir" .bundle)"
    source_ipcc="$IPCC_DIR/$bundle_name.ipcc"
    [ -f "$source_ipcc" ] || continue
    region="$(region_for_bundle "$bundle_name")"
    pretty_name="$(canonical_name_for_bundle "$bundle_name" "$bundle_dir")"
    target="$SORTED_DIR/$region/$pretty_name.ipcc"
    if [ -e "$target" ]; then
        target="$SORTED_DIR/$region/${pretty_name}__${bundle_name}.ipcc"
    fi
    cp -f "$source_ipcc" "$target"
done < <(find "$IPHONE_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

FINAL_DIR="$SORTED_DIR"
echo ""
CLEAN_CONFIRM="${CLEAN_CONFIRM_OVERRIDE:-}"
if [ -z "$CLEAN_CONFIRM" ]; then
    prompt cleanup_prompt
    read -r CLEAN_CONFIRM
else
    echo "$CLEAN_CONFIRM"
fi
if answer_yes "$CLEAN_CONFIRM"; then
    KEEP_DIR="$WORK_ROOT/${IPSW_BASENAME}_IPCC_Final"
    mkdir -p "$KEEP_DIR"
    cp -R "$SORTED_DIR"/. "$KEEP_DIR"/
    rm -rf "$WORK_DIR"
    DELETE_IPSW="${DELETE_IPSW_OVERRIDE:-}"
    if [ -z "$DELETE_IPSW" ]; then
        prompt delete_ipsw_prompt
        read -r DELETE_IPSW
    else
        echo "$DELETE_IPSW"
    fi
    if answer_yes "$DELETE_IPSW"; then
        rm -f "$IPSW_FILE"
    fi
    FINAL_DIR="$KEEP_DIR"
fi

print_install_guide "$FINAL_DIR"
if answer_yes "${OPEN_FINAL_DIR_OVERRIDE:-n}"; then
    open "$FINAL_DIR" >/dev/null 2>&1 || true
fi
echo ""
say done
