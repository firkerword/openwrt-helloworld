#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (C) 2023 Tianling Shen <cnsztl@immortalwrt.org>

export PKG_SOURCE_DATE_EPOCH="$(date "+%s")"

BASE_DIR="$(cd "$(dirname $0)"; pwd)"
PKG_DIR="$BASE_DIR/.."

function get_mk_value() {
	awk -F "$1:=" '{print $2}' "$PKG_DIR/Makefile" | xargs
}

PKG_NAME="$(get_mk_value "PKG_NAME")"
if [ "$RELEASE_TYPE" == "release" ]; then
	PKG_VERSION="$(get_mk_value "PKG_VERSION")"
else
	PKG_VERSION="dev-$PKG_SOURCE_DATE_EPOCH-$(git rev-parse --short HEAD)"
fi

TEMP_DIR="$(mktemp -d -p $BASE_DIR)"
TEMP_PKG_DIR="$TEMP_DIR/$PKG_NAME"
mkdir -p "$TEMP_PKG_DIR/CONTROL/"
mkdir -p "$TEMP_PKG_DIR/lib/upgrade/keep.d/"
mkdir -p "$TEMP_PKG_DIR/www/"

cp -fpR "$PKG_DIR/htdocs"/* "$TEMP_PKG_DIR/www/"
cp -fpR "$PKG_DIR/root"/* "$TEMP_PKG_DIR/"

echo -e "/etc/config/homeproxy" > "$TEMP_PKG_DIR/CONTROL/conffiles"
echo -e "/etc/homeproxy/certs/" > "$TEMP_PKG_DIR/lib/upgrade/keep.d/$PKG_NAME"

cat > "$TEMP_PKG_DIR/CONTROL/control" <<-EOF
	Package: $PKG_NAME
	Version: $PKG_VERSION
	Depends: libc, sing-box, kmod-tun, curl, firewall4
	Source: https://github.com/immortalwrt/homeproxy
	SourceName: $PKG_NAME
	Section: luci
	SourceDateEpoch: $PKG_SOURCE_DATE_EPOCH
	Maintainer: Tianling Shen <cnsztl@immortalwrt.org>
	Architecture: all
	Installed-Size: TO-BE-FILLED-BY-IPKG-BUILD
	Description:  The modern ImmortalWrt proxy platform for ARM64/AMD64
EOF

echo -e '#!/bin/sh
[ "${IPKG_NO_SCRIPT}" = "1" ] && exit 0
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_postinst $0 $@' > "$TEMP_PKG_DIR/CONTROL/postinst"
chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst"

echo -e "[ -n "\${IPKG_INSTROOT}" ] || {
	(. /etc/uci-defaults/$PKG_NAME) && rm -f /etc/uci-defaults/$PKG_NAME
	rm -f /tmp/luci-indexcache
	rm -rf /tmp/luci-modulecache/
	exit 0
}" > "$TEMP_PKG_DIR/CONTROL/postinst-pkg"
chmod 0755 "$TEMP_PKG_DIR/CONTROL/postinst-pkg"

echo -e '#!/bin/sh
[ -s ${IPKG_INSTROOT}/lib/functions.sh ] || exit 0
. ${IPKG_INSTROOT}/lib/functions.sh
default_prerm $0 $@' > "$TEMP_PKG_DIR/CONTROL/prerm"
chmod 0755 "$TEMP_PKG_DIR/CONTROL/prerm"

curl -fsSL "https://raw.githubusercontent.com/openwrt/openwrt/master/scripts/ipkg-build" -o "$TEMP_DIR/ipkg-build"
chmod 0755 "$TEMP_DIR/ipkg-build"
"$TEMP_DIR/ipkg-build" -m "" "$TEMP_PKG_DIR" "$TEMP_DIR"

mv "$TEMP_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk" "$BASE_DIR/${PKG_NAME}_${PKG_VERSION}_all.ipk"
rm -rf "$TEMP_DIR"
