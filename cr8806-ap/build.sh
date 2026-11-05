#!/bin/sh
# Build ban AP co NSS cho Xiaomi CR8806 (M79). Chay o goc cay nguon tren Linux.
# Ket qua: bin/cr8806-ap/ (factory.ubi, sysupgrade.bin, initramfs, manifest, sha256sums)
set -e
cd "$(dirname "$0")/.."

./scripts/feeds update -a
./scripts/feeds install -a

rm -rf files && mkdir files
cp -a cr8806-ap/files/. files/
chmod +x files/root/setup-ap.sh files/etc/uci-defaults/99-cr8806-ap files/etc/uci-defaults/98-cr8806-ap-runtime \
	files/usr/sbin/roam-cleanup files/etc/init.d/roam-cleanup

cp cr8806-ap/ap.config .config
make defconfig

# defconfig am tham bo dong nao no khong chon duoc -> coi la loi
dropped=""
for req in $(grep -E '^CONFIG_[A-Za-z0-9_-]+=' cr8806-ap/ap.config); do
	grep -qxF "$req" .config || dropped="$dropped $req"
done
for off in $(sed -n 's/^# \(CONFIG_[A-Za-z0-9_-]*\) is not set$/\1/p' cr8806-ap/ap.config); do
	grep -qE "^$off=[ym]" .config && dropped="$dropped $off(van-bat)"
done
[ -z "$dropped" ] || { echo "defconfig khong giu duoc:$dropped" >&2; exit 1; }

make -j"$(nproc)" download || make -j1 download
make -j"$(nproc)" || make -j1 V=s

tdir=bin/targets/qualcommax/ipq50xx
out=bin/cr8806-ap
rm -rf "$out" && mkdir -p "$out"
cp "$tdir"/*xiaomi_cr8806* "$out"/
cp "$tdir"/*.manifest "$out"/ 2>/dev/null || true
cp .config "$out"/config.full
./scripts/diffconfig.sh > "$out"/diffconfig
(cd "$out" && sha256sum * > sha256sums)
ls -l "$out"
