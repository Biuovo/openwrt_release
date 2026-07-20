#!/usr/bin/env bash

set -euo pipefail

BUILD_DIR="$1"
IMM_NSS_REPO="${IMM_NSS_REPO:-https://github.com/VIKINGYFY/immortalwrt.git}"
IMM_NSS_BRANCH="${IMM_NSS_BRANCH:-main}"
TMP_DIR="${TMPDIR:-/tmp}/imm-full-nss-src"

rm -rf "$TMP_DIR"
git clone --depth=1 --filter=blob:none --sparse -b "$IMM_NSS_BRANCH" "$IMM_NSS_REPO" "$TMP_DIR"
(
    cd "$TMP_DIR"
    git sparse-checkout set \
        package/qca-nss \
        package/kernel/mac80211 \
        target/linux/qualcommax/patches-6.12 \
        target/linux/qualcommax/files/include/uapi/linux/tc_act \
        target/linux/qualcommax/Makefile
)

# Full NSS package stack from the previous ER1 Imm source.
rm -rf "$BUILD_DIR/package/qca-nss"
mkdir -p "$BUILD_DIR/package"
cp -a "$TMP_DIR/package/qca-nss" "$BUILD_DIR/package/qca-nss"

# mac80211 NSS options/patches are needed by qca-nss headers/build glue.
if [ -d "$TMP_DIR/package/kernel/mac80211/patches/nss" ]; then
    mkdir -p "$BUILD_DIR/package/kernel/mac80211/patches"
    rm -rf "$BUILD_DIR/package/kernel/mac80211/patches/nss"
    cp -a "$TMP_DIR/package/kernel/mac80211/patches/nss" "$BUILD_DIR/package/kernel/mac80211/patches/nss"
fi

# Kernel NSS/ECM/client support patches for qualcommax 6.12.
mkdir -p "$BUILD_DIR/target/linux/qualcommax/patches-6.12"
find "$TMP_DIR/target/linux/qualcommax/patches-6.12" -maxdepth 1 -type f \
    \( -name '0600-*' -o -name '0601-*' -o -name '0602-*' -o -name '0603-*' -o -name '0605-*' -o -name '0606-*' -o -name '0607-*' \) \
    -exec cp -f {} "$BUILD_DIR/target/linux/qualcommax/patches-6.12/" \;

# NSS qdisc userspace header.
if [ -d "$TMP_DIR/target/linux/qualcommax/files/include/uapi/linux/tc_act" ]; then
    mkdir -p "$BUILD_DIR/target/linux/qualcommax/files/include/uapi/linux"
    rm -rf "$BUILD_DIR/target/linux/qualcommax/files/include/uapi/linux/tc_act"
    cp -a "$TMP_DIR/target/linux/qualcommax/files/include/uapi/linux/tc_act" \
        "$BUILD_DIR/target/linux/qualcommax/files/include/uapi/linux/tc_act"
fi

# Make target defaults use the full NSS stack instead of only official qca-nss-dp.
qual_mk="$BUILD_DIR/target/linux/qualcommax/Makefile"
if [ -f "$qual_mk" ]; then
    python3 - "$qual_mk" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = "kmod-qca-nss-dp kmod-ath11k-ahb"
new = "kmod-qca-nss-dp kmod-qca-nss-drv kmod-qca-ssdk kmod-qca-nss-ecm kmod-qca-nss-drv-bridge-mgr kmod-qca-nss-drv-vlan-mgr kmod-qca-nss-drv-pppoe kmod-ath11k-ahb"
if old in s and new not in s:
    s = s.replace(old, new)
p.write_text(s)
PY
fi

# Hard fail if full NSS is not really present.
for p in \
    "$BUILD_DIR/package/qca-nss/qca-nss-drv/Makefile" \
    "$BUILD_DIR/package/qca-nss/qca-nss-ecm/Makefile" \
    "$BUILD_DIR/package/qca-nss/qca-nss-clients/Makefile" \
    "$BUILD_DIR/package/qca-nss/qca-ssdk/Makefile"; do
    [ -f "$p" ] || { echo "Missing full NSS component: $p" >&2; exit 1; }
done

grep -R "define KernelPackage/qca-nss-drv" "$BUILD_DIR/package/qca-nss/qca-nss-drv/Makefile" >/dev/null
grep -R "define KernelPackage/qca-nss-ecm" "$BUILD_DIR/package/qca-nss/qca-nss-ecm/Makefile" >/dev/null
grep -R "define KernelPackage/qca-nss-drv-vlan-mgr" "$BUILD_DIR/package/qca-nss/qca-nss-clients/Makefile" >/dev/null

echo "Ported full Imm NSS stack into official OpenWrt tree for ER1."
