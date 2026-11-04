#!/bin/sh
# Cau hinh Wi-Fi cho tung AP sau khi flash. Mat khau nhap luc chay, khong nam trong image.
#   sh /root/setup-ap.sh <ten> <kenh-2.4G> <kenh-5G> [--no-luci]
#   vi du:  sh /root/setup-ap.sh Mesh1F 1 36
#           sh /root/setup-ap.sh Mesh2F 6 149
#           sh /root/setup-ap.sh Mesh3F 11 52
#   --no-luci: tat uhttpd + rpcd (giao dien web) de lay lai ~2-3 MB RAM; bat lai bang
#              /etc/init.d/rpcd enable && /etc/init.d/rpcd start && /etc/init.d/uhttpd enable && /etc/init.d/uhttpd start
# Bien moi truong (tuy chon): SSID_5G, SSID_IOT, MOBILITY_DOMAIN (4 so hex, giong nhau o ca 3 AP)
#
# DHs-5GHz: 802.11r (FT-PSK sinh khoa tai cho) + 802.11k + 802.11v, usteer dieu phoi.
# DHs-IoT : WPA2 thuan, KHONG 802.11r/k/v (thiet bi IoT cu loi khi AP quang ba FT).

set -e
name="$1"; ch2="$2"; ch5="$3"; opt="$4"
[ -n "$name" ] && [ -n "$ch2" ] && [ -n "$ch5" ] || { sed -n '2,13p' "$0"; exit 1; }

SSID_5G="${SSID_5G:-DHs-5GHz}"
SSID_IOT="${SSID_IOT:-DHs-IoT}"
MOBILITY_DOMAIN="${MOBILITY_DOMAIN:-d5a1}"

read_key() {
	printf '%s: ' "$1" >&2
	stty -echo 2>/dev/null || true; read -r k; stty echo 2>/dev/null || true; echo >&2
	[ ${#k} -ge 8 ] || { echo "Mat khau phai tu 8 ky tu" >&2; exit 1; }
	echo "$k"
}
KEY_5G="$(read_key "Mat khau $SSID_5G")"
KEY_IOT="$(read_key "Mat khau $SSID_IOT")"

radio_2g=""; radio_5g=""
for r in $(uci show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-device$/\1/p'); do
	case "$(uci -q get wireless.$r.band)" in
	2g) radio_2g="$r" ;;
	5g) radio_5g="$r" ;;
	esac
done
[ -n "$radio_2g" ] && [ -n "$radio_5g" ] || { echo "Khong tim thay radio 2g/5g" >&2; exit 1; }

# Xoa cac SSID cu, giu cau hinh radio. Moi radio dung 1 SSID (moi SSID them ton bo dem).
for i in $(uci show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-iface$/\1/p'); do
	uci delete wireless.$i
done

uci set wireless.$radio_2g.country='VN'
uci set wireless.$radio_2g.channel="$ch2"
uci set wireless.$radio_2g.htmode='HE20'
uci set wireless.$radio_2g.cell_density='0'
uci -q delete wireless.$radio_2g.disabled

uci set wireless.$radio_5g.country='VN'
uci set wireless.$radio_5g.channel="$ch5"
uci set wireless.$radio_5g.htmode='HE80'
uci set wireless.$radio_5g.cell_density='0'
uci -q delete wireless.$radio_5g.disabled

uci set wireless.iot=wifi-iface
uci set wireless.iot.device="$radio_2g"
uci set wireless.iot.network='lan'
uci set wireless.iot.mode='ap'
uci set wireless.iot.ssid="$SSID_IOT"
uci set wireless.iot.encryption='psk2+ccmp'
uci set wireless.iot.key="$KEY_IOT"
uci set wireless.iot.ieee80211r='0'
uci set wireless.iot.ieee80211k='0'
uci set wireless.iot.bss_transition='0'

uci set wireless.fast5g=wifi-iface
uci set wireless.fast5g.device="$radio_5g"
uci set wireless.fast5g.network='lan'
uci set wireless.fast5g.mode='ap'
uci set wireless.fast5g.ssid="$SSID_5G"
uci set wireless.fast5g.encryption='psk2+ccmp'
uci set wireless.fast5g.key="$KEY_5G"
uci set wireless.fast5g.ieee80211r='1'
uci set wireless.fast5g.mobility_domain="$MOBILITY_DOMAIN"
uci set wireless.fast5g.ft_over_ds='0'
uci set wireless.fast5g.ft_psk_generate_local='1'
uci set wireless.fast5g.ieee80211k='1'
uci set wireless.fast5g.rrm_neighbor_report='1'
uci set wireless.fast5g.bss_transition='1'
uci set wireless.fast5g.wnm_sleep_mode='1'

uci set system.@system[0].hostname="$name"

# usteer: cac AP trao doi qua br-lan, chi dieu phoi DHs-5GHz
uci -q get usteer.@usteer[0] >/dev/null || uci add usteer usteer >/dev/null
uci set usteer.@usteer[0].network='lan'
uci -q delete usteer.@usteer[0].ssid_list || true
uci add_list usteer.@usteer[0].ssid_list="$SSID_5G"

uci commit wireless
uci commit system
uci commit usteer
/etc/init.d/system reload
/etc/init.d/usteer enable
/etc/init.d/usteer restart
wifi reload

if [ "$opt" = "--no-luci" ]; then
	/etc/init.d/uhttpd stop || true; /etc/init.d/uhttpd disable || true
	/etc/init.d/rpcd stop || true; /etc/init.d/rpcd disable || true
	echo "Da tat LuCI (uhttpd, rpcd)"
fi
echo "Xong: $name, 2.4G kenh $ch2 (HE20), 5G kenh $ch5 (HE80), mobility domain $MOBILITY_DOMAIN"
