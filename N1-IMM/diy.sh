#!/bin/bash
# Git稀疏克隆，只克隆指定目录到本地
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
# 删除 Rust（已解决 LLVM 404）
rm -rf feeds/packages/lang/rust 2>/dev/null || true

# golang 用 sbwml 最新版
rm -rf feeds/packages/lang/golang 2>/dev/null || true
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang

# 删除不必要的/冲突包
rm -rf feeds/packages/net/homeproxy feeds/luci/applications/luci-app-homeproxy 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-turboacc 2>/dev/null || true
rm -rf feeds/packages/lang/ruby 2>/dev/null || true
rm -rf feeds/packages/net/aria2 feeds/packages/net/ariang feeds/luci/luci-app-aria2 2>/dev/null || true

# ==================== Python 替换（解决 setuptools/host 不存在、zope WARNING 等） ====================
# 加载公用函数（merge_package 等）
[ -f $GITHUB_WORKSPACE/update_before/functions.sh ] && source $GITHUB_WORKSPACE/update_before/functions.sh || echo "Warning: functions.sh not found, skip python merge"

cd openwrt || exit 1

# 删除官方 python 包（包括 python3、setuptools、zope 等）
rm -rf feeds/packages/lang/python 2>/dev/null || true

# 从 rmoyulong/old_coolsnowwolf_packages 合并 python 包（旧版修复）
if type merge_package >/dev/null 2>&1; then
  merge_package master https://github.com/rmoyulong/old_coolsnowwolf_packages feeds/packages/lang lang/python
  echo "Python 包已从 old_coolsnowwolf_packages 合并"
else
  echo "merge_package 函数未定义，跳过 python 替换。请确认 functions.sh 已加载。"
fi

# ==================== Python 替换结束 ====================

# Passwall 里的旧核心子模块（已配合 Passwall 替换）
rm -rf package/passwall-luci/shadowsocks-rust package/passwall-luci/hysteria 2>/dev/null || true

# Add packages（原有部分）
git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth 1 https://github.com/ophub/luci-app-amlogic package/amlogic
git clone --depth=1 https://github.com/rufengsuixing/luci-app-adguardhome package/luci-app-adguardhome
git clone --depth=1 https://github.com/nikkinikki-org/OpenWrt-nikki package/luci-app-nikki
git clone --depth=1 https://github.com/gdy666/luci-app-lucky.git package/lucky

# ==================== Passwall 官方最新替换（推荐方法2，2026年1月最新） ====================
# 移除官方 feeds 里冲突的代理核心包（防止 Makefile 重复定义或版本过旧）
rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,hysteria,ipt2socks,microsocks,naiveproxy,shadowsocks-libev,shadowsocks-rust,shadowsocksr-libev,simple-obfs,tcping,trojan-plus,tuic-client,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null || true

# 移除官方 luci-app-passwall（如果 feeds/luci 里有残留旧版）
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true

# 克隆 Passwall 核心依赖包（包含最新 xray-core、sing-box 等）
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages

# 克隆 Passwall LuCI 界面（main 分支，包名为 luci-app-passwall）
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci

# ==================== Passwall 替换结束 ====================

# 加入OpenClash核心
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

# mosdns（原有部分保持，但优化 rm 方式）
rm -f $(find feeds/packages -name Makefile | grep -E 'v2ray-geodata|mosdns') 2>/dev/null || true
git clone https://github.com/sbwml/luci-app-mosdns -b v5 package/mosdns
git clone https://github.com/sbwml/v2ray-geodata package/v2ray-geodata

# 向文件添加 DISTRIB_SOURCECODE
echo "DISTRIB_SOURCECODE='immortalwrt'" >> package/base-files/files/etc/openwrt_release

# 修改默认IP
sed -i 's/192.168.1.1/192.168.6.6/g' package/base-files/files/bin/config_generate

# 清理软件包（原有 rm 保持，但加容错）
rm -rf feeds/luci/themes/luci-theme-argon 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-argon-config 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-nikki 2>/dev/null || true

# 可选：如果想用 argon 作为默认主题，取消注释下面两行（注意 feeds/luci/collections/luci/Makefile 可能已变）
#sed -i 's/luci-theme-bootstrap/luci-theme-argon/g' feeds/luci/collections/luci/Makefile
#sed -i 's/luci-theme-design/luci-theme-argon/g' feeds/luci/collections/luci/Makefile

# 其他原有注释部分保持不变
