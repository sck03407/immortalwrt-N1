#!/bin/bash
# =====================================================================
# diy.sh - ImmortalWrt openwrt-24.10 分支 N1 自定义编译脚本
# 包含 Passwall 官方替换、OpenClash、mosdns v5、argon 主题等
# =====================================================================

# ==================== 内嵌 merge_package 函数（避免外部依赖） ====================
merge_package() {
    # 用法: merge_package <branch> <repo_url> <target_dir> <subpath1> [subpath2 ...]
    if [[ $# -lt 3 ]]; then
        echo "Error: merge_package 需要至少 3 个参数: branch repo_url target_dir [subdirs...]" >&2
        return 1
    fi

    local branch="$1"
    local repo_url="$2"
    local target_dir="$3"
    shift 3

    local rootdir="$PWD"
    local tmpdir
    tmpdir=$(mktemp -d) || { echo "创建临时目录失败"; return 1; }
    trap 'rm -rf "$tmpdir"' EXIT

    echo "正在从 $repo_url sparse clone $branch 分支的 $@ 到 $target_dir"

    git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$repo_url" "$tmpdir" || { echo "git clone 失败"; return 1; }
    cd "$tmpdir" || { echo "进入临时目录失败"; return 1; }
    git sparse-checkout init --cone
    git sparse-checkout set "$@" || { echo "sparse-checkout set 失败"; return 1; }

    for folder in "$@"; do
        if [ -d "$folder" ]; then
            mv -f "$folder" "$rootdir/$target_dir/" || echo "移动 $folder 失败"
        else
            echo "警告: $folder 不存在，跳过"
        fi
    done

    cd "$rootdir" || return 1
    echo "merge_package 完成"
}
# ==================== 内嵌函数结束 ====================

# Git稀疏克隆，只克隆指定目录到 ./package
function git_sparse_clone() {
  branch="$1" repourl="$2" && shift 2
  git clone --depth=1 -b $branch --single-branch --filter=blob:none --sparse $repourl
  repodir=$(echo $repourl | awk -F '/' '{print $(NF)}')
  cd $repodir && git sparse-checkout set $@
  for dir in "$@"; do
    mv -f "$dir" ../package/ || echo "mv $dir failed"
  done
  cd .. && rm -rf $repodir
}

# ==================== 解决常见编译冲突 & 覆盖关键依赖 ====================

# 删除 Rust（解决 LLVM CI 404 下载失败，24.10 常见问题）
rm -rf feeds/packages/lang/rust 2>/dev/null || true

# golang 用 sbwml 最新版（Go 1.26.x，修复 musl 兼容、加速 Go 包编译）
rm -rf feeds/packages/lang/golang 2>/dev/null || true
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

# 删除不必要的/冲突包（节省空间、避免潜在错误）
rm -rf feeds/packages/net/homeproxy feeds/luci/applications/luci-app-homeproxy 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-turboacc 2>/dev/null || true
rm -rf feeds/packages/lang/ruby 2>/dev/null || true
rm -rf feeds/packages/net/aria2 feeds/packages/net/ariang feeds/luci/luci-app-aria2 2>/dev/null || true

# ==================== Python 处理（简化版，避免旧版兼容问题） ====================
rm -rf feeds/packages/lang/python 2>/dev/null || true
echo "官方 python 包已删除，避免 setuptools/host 等 WARNING（如果需要 python，请在 menuconfig 手动选）"
# 如果以后需要 python，可取消注释下面两行，用 merge_package 替换
# merge_package master https://github.com/rmoyulong/old_coolsnowwolf_packages feeds/packages/lang lang/python
# ==================== Python 处理结束 ====================

# Passwall 里的旧核心子模块（配合 Passwall 替换）
rm -rf package/passwall-luci/shadowsocks-rust package/passwall-luci/hysteria 2>/dev/null || true

# ==================== Passwall 官方最新替换 ====================
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true

git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci
# ==================== Passwall 替换结束 ====================

# Add packages
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth 1 https://github.com/ophub/luci-app-amlogic package/amlogic
git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome package/luci-app-adguardhome
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/luci-app-nikki
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky

# 加入 OpenClash 核心
git clone --depth 1 https://github.com/vernesong/openclash.git OpenClash
rm -rf feeds/luci/applications/luci-app-openclash
mv OpenClash/luci-app-openclash feeds/luci/applications/luci-app-openclash

##------------- meta core ---------------------------------
curl -sL -m 30 --retry 5 https://raw.githubusercontent.com/vernesong/OpenClash/core/master/meta/clash-linux-arm64.tar.gz -o /tmp/clash.tar.gz || echo "Clash Meta 下载失败，请检查网络"
tar zxvf /tmp/clash.tar.gz -C /tmp >/dev/null 2>&1
chmod +x /tmp/clash >/dev/null 2>&1
mv /tmp/clash feeds/luci/applications/luci-app-openclash/root/etc/openclash/core/clash_meta >/dev/null 2>&1
rm -rf /tmp/clash.tar.gz >/dev/null 2>&1

##-------------- GeoIP 数据库 -----------------------------
curl -sL -m 30 --retry 5 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geoip.dat -o /tmp/GeoIP.dat
mv /tmp/GeoIP.dat feeds/luci/applications/luci-app-openclash/root/etc/openclash/GeoIP.dat >/dev/null 2>&1

##-------------- GeoSite 数据库 ---------------------------
curl -sL -m 30 --retry 5 https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat -o /tmp/GeoSite.dat
mv /tmp/GeoSite.dat feeds/luci/applications/luci-app-openclash/root/etc/openclash/GeoSite.dat >/dev/null 2>&1

# mosdns v5 + v2ray-geodata（sbwml 版本）
rm -f $(find feeds/packages -name Makefile | grep -E 'v2ray-geodata|mosdns') 2>/dev/null || true
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# 向文件添加 DISTRIB_SOURCECODE
echo "DISTRIB_SOURCECODE='immortalwrt'" >> package/base-files/files/etc/openwrt_release

# 修改默认IP
sed -i 's/192.168.1.1/192.168.6.6/g' package/base-files/files/bin/config_generate

# 清理软件包（避免 feeds 里的旧版冲突）
rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-argon-config 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-nikki 2>/dev/null || true

# 可选：设置 argon 为默认主题（取消注释启用）
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
#sed -i 's/luci-theme-design/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

echo "diy.sh 执行完成"
