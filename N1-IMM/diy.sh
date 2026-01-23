#!/bin/bash
# =====================================================================
# diy.sh - ImmortalWrt openwrt-24.10 分支 N1 自定义编译脚本
# 已修复重复 clone、路径问题、保留必要覆盖
# =====================================================================

set -e  # 出错立即退出

echo "diy.sh 开始执行，当前目录: $PWD"

# 切换到 openwrt 目录（最重要！）
cd /workdir/openwrt || { echo "错误：/workdir/openwrt 不存在"; exit 1; }
echo "已切换到 openwrt 目录: $PWD"

# ==================== 内嵌 merge_package 函数 ====================
merge_package() {
    if [[ $# -lt 3 ]]; then
        echo "Error: merge_package 需要至少 3 个参数" >&2
        return 1
    fi
    local branch="$1" repo_url="$2" target_dir="$3"
    shift 3
    local rootdir="$PWD"
    local tmpdir=$(mktemp -d) || exit 1
    trap 'rm -rf "$tmpdir"' EXIT
    echo "merge_package: 从 $repo_url clone $branch 到 $target_dir"
    git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$repo_url" "$tmpdir"
    cd "$tmpdir"
    git sparse-checkout init --cone
    git sparse-checkout set "$@"
    for folder in "$@"; do
        [ -d "$folder" ] && mv -f "$folder" "$rootdir/$target_dir/" || echo "警告: $folder 不存在"
    done
    cd "$rootdir"
    echo "merge_package 完成"
}

# ==================== 解决常见冲突 ====================
rm -rf feeds/packages/lang/rust 2>/dev/null || true
echo "已删除 rust 包，避免 Rust 构建错误"

rm -rf feeds/packages/lang/golang 2>/dev/null || true
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
echo "已覆盖 golang 为 sbwml 26.x"

# 删除不必要包
rm -rf feeds/packages/net/homeproxy feeds/luci/applications/luci-app-homeproxy 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-turboacc 2>/dev/null || true
rm -rf feeds/packages/lang/ruby 2>/dev/null || true
rm -rf feeds/packages/net/aria2 feeds/packages/net/ariang feeds/luci/applications/luci-app-aria2 2>/dev/null || true

# ==================== Python 处理（只删除问题子包，保留核心） ====================
rm -rf feeds/packages/lang/python-zope* feeds/packages/lang/python-setuptools* feeds/packages/lang/python-hatch* 2>/dev/null || true
echo "已删除 python 的问题子包，避免 WARNING，但保留 python3 核心（修复 boost/python3 依赖）"

# ==================== amlogic + passwall（修复重复，只用一种方式） ====================
echo "开始 clone amlogic 和 passwall..."

mkdir -p temp_clone
cd temp_clone

git clone --depth=1 https://github.com/ophub/luci-app-amlogic.git amlogic
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git passwall

cd ..

rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true
cp -rf temp_clone/amlogic/luci-app-amlogic feeds/luci/applications/
cp -rf temp_clone/passwall/luci-app-passwall feeds/luci/applications/

rm -rf temp_clone
echo "amlogic 和 passwall 已覆盖完成"

# ==================== 其他包 ====================
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome package/luci-app-adguardhome
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/luci-app-nikki
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky

# OpenClash 核心（保持不变）
git clone --depth 1 https://github.com/vernesong/openclash.git OpenClash
rm -rf feeds/luci/applications/luci-app-openclash
mv OpenClash/luci-app-openclash feeds/luci/applications/luci-app-openclash

curl -sL -m 30 --retry 5 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz -o /tmp/clash.tar.gz || echo "Clash Meta 下载失败"
tar zxvf /tmp/clash.tar.gz -C /tmp >/dev/null 2>&1
chmod +x /tmp/clash >/dev/null 2>&1
mv /tmp/clash feeds/luci/applications/luci-app-openclash/root/etc/openclash/core/clash_meta >/dev/null 2>&1
rm -rf /tmp/clash.tar.gz >/dev/null 2>&1

curl -sL -m 30 --retry 5 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -o /tmp/GeoIP.dat
mv /tmp/GeoIP.dat feeds/luci/applications/luci-app-openclash/root/etc/openclash/GeoIP.dat >/dev/null 2>&1

curl -sL -m 30 --retry 5 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -o /tmp/GeoSite.dat
mv /tmp/GeoSite.dat feeds/luci/applications/luci-app-openclash/root/etc/openclash/GeoSite.dat >/dev/null 2>&1

# mosdns v5
rm -f $(find feeds/packages -name Makefile | grep -E 'v2ray-geodata|mosdns') 2>/dev/null || true
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# ==================== 基础设置 ====================

echo "DISTRIB_SOURCECODE='immortalwrt'" >> package/base-files/files/etc/openwrt_release
sed -i 's/192.168.1.1/192.168.6.6/g' package/base-files/files/bin/config_generate

rm -rf feeds/luci/themes/luci-theme-argon feeds/luci/applications/luci-app-argon-config feeds/luci/applications/luci-app-nikki 2>/dev/null || true

echo "diy.sh 执行完成"
