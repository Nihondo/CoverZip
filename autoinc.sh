#!/bin/bash
set -euo pipefail

# コミット数を取得（git -C でSRCROOTを明示指定）
commit_count=$(git -C "$SRCROOT" rev-list --count HEAD 2>/dev/null || echo "0")

# 前回のビルド番号をカウンターファイルから取得
# DERIVED_FILE_DIR はターゲット・構成ごとの中間ファイル置き場
counter_file="${DERIVED_FILE_DIR}/.build_counter"
build_count=1

if [[ -f "$counter_file" ]]; then
    saved_commit=$(awk '{print $1}' "$counter_file" 2>/dev/null || echo "")
    saved_build=$(awk '{print $2}' "$counter_file" 2>/dev/null || echo "0")
    if [[ "$saved_commit" == "$commit_count" ]]; then
        build_count=$((saved_build + 1))
    fi
fi

# カウンターファイルを更新
echo "$commit_count $build_count" > "$counter_file"

new_version="${commit_count}.${build_count}"
echo "Build version = $new_version"

# ビルド済み Info.plist の CFBundleVersion を直接更新
# （agvtool は project.pbxproj を書き換えようとするためビルド中は使用不可）
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $new_version" \
    "${TARGET_BUILD_DIR}/${INFOPLIST_PATH}"
