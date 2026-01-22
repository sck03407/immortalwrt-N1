#!/bin/bash
# =====================================================================
# diy.sh - ImmortalWrt openwrt-24.10 N1 单文件编译脚本
# 保留 shadowsocks-rust 和 hysteria，修复 libev/ssr 编译错误
# =====================================================================

# ==================== 解决常见编译冲突 & 覆盖关键依赖 ====================

# 删除官方 Rust（避免 LLVM CI 404，但保留 Passwall 中的 shadowsocks-rust/hysteria）
rm -rf feeds/packages/lang/rust 2>/dev/null || true
echo "已删除官方 rust 包，避免全局 Rust 构建错误"

# golang 用 sbwml 最新版
rm -rf feeds/packages/lang/golang 2>/dev/null || true
git clone --depth=1 https://github.com/sbwml/packages_lang_golang -b 26.x feeds/packages/lang/golang
echo "已覆盖 golang 为 sbwml 26.x"

# 删除不必要的包
rm -rf feeds/packages/net/homeproxy feeds/luci/applications/luci-app-homeproxy 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-turboacc 2>/dev/null || true
rm -rf feeds/packages/lang/ruby 2>/dev/null || true
rm -rf feeds/packages/net/aria2 feeds/packages/net/ariang feeds/luci/applications/luci-app-aria2 2>/dev/null || true

# Python 处理（简化：删除官方，避免 WARNING）
rm -rf feeds/packages/lang/python 2>/dev/null || true
echo "官方 python 已删除，避免相关 WARNING"

# ==================== shadowsocks-libev / ssr-libev 修复覆盖（别人方案核心） ====================

# 先 clone sbwml 的修复版到本地 ./package/
git clone --depth=1 https://github.com/sbwml/shadowsocks-libev.git ./package/shadowsocks-libev
git clone --depth=1 https://github.com/sbwml/shadowsocksr-libev.git ./package/shadowsocksr-libev

# 覆盖官方 feeds 中的 libev/ssr
rm -rf feeds/packages/net/shadowsocks-libev 2>/dev/null || true
cp -rf ./package/shadowsocks-libev feeds/packages/net/

rm -rf feeds/packages/net/shadowsocksr-libev 2>/dev/null || true
cp -rf ./package/shadowsocksr-libev feeds/packages/net/

# 删除 Passwall 自带的旧 ssr（防止重复定义）
rm -rf package/passwall-luci/shadowsocksr-libev 2>/dev/null || true

echo "已用 sbwml 修复版覆盖 shadowsocks-libev / ssr-libev"

# ==================== Passwall 官方替换（保留 shadowsocks-rust / hysteria） ====================

rm -rf feeds/packages/net/{xray-core,v2ray-geodata,sing-box,chinadns-ng,dns2socks,ipt2socks,microsocks,naiveproxy,simple-obfs,tcping,trojan-plus,v2ray-plugin,xray-plugin,geoview,shadow-tls} 2>/dev/null || true
rm -rf feeds/luci/applications/luci-app-passwall 2>/dev/null || true

git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git package/passwall-packages
git clone --depth=1 https://github.com/Openwrt-Passwall/openwrt-passwall.git package/passwall-luci

# 注意：这里不 rm shadowsocks-rust / hysteria，保留它们！
echo "Passwall 已替换，保留 shadowsocks-rust 和 hysteria"

# ==================== Add packages ====================

git clone --depth 1 https://github.com/jerrykuku/luci-theme-argon package/luci-theme-argon
git clone --depth 1 https://github.com/ophub/luci-app-amlogic package/amlogic
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
