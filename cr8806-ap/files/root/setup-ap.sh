#!/bin/sh
# Cau hinh Wi-Fi cho tung AP sau khi flash. Ten Wi-Fi (Enter = mac dinh) va mat khau hoi luc chay.
#   sh /root/setup-ap.sh <ten> <kenh-2.4G> <kenh-5G> [--no-luci]
#   vi du:  sh /root/setup-ap.sh Mesh1F 1 36
#           sh /root/setup-ap.sh Mesh2F 6 149
#           sh /root/setup-ap.sh Mesh3F 11 36
#   --no-luci: tat uhttpd + rpcd (giao dien web) de lay lai ~2-3 MB RAM; bat lai bang
#              /etc/init.d/rpcd enable && /etc/init.d/rpcd start && /etc/init.d/uhttpd enable && /etc/init.d/uhttpd start
# Bien moi truong (tuy chon): SSID_5G, SSID_IOT (dat thi khong hoi), MOBILITY_DOMAIN (4 so hex)
#   Ten Wi-Fi, mat khau va MOBILITY_DOMAIN phai giong nhau o moi AP thi moi roaming duoc.
#   ROAM_SCAN (-70), ROAM_TRIGGER (-75), ROAM_DIFF (8 dB), USTEER_DEBUG (1), MCAST_SNOOP (1)
#   KEEP_FALLBACK=1: giu IP du phong 192.168.1.1 (mac dinh tat sau setup, xem cuoi file)
#
# Wi-Fi 5 GHz (mac dinh DHs-5GHz): 802.11r (FT-PSK sinh khoa tai cho) + 802.11k + 802.11v, usteer.
# Wi-Fi IoT 2.4 GHz (mac dinh DHs-IoT): WPA2 thuan, KHONG 802.11r/k/v (IoT cu loi khi co FT).

set -e
name="$1"; ch2="$2"; ch5="$3"; opt="$4"
[ -n "$name" ] && [ -n "$ch2" ] && [ -n "$ch5" ] || { sed -n '2,16p' "$0"; exit 1; }

MOBILITY_DOMAIN="${MOBILITY_DOMAIN:-d5a1}"

# Radio chi co trong cau hinh sau khi NSS arm va ath11k nap xong (~1 phut sau boot): cho toi da 2 phut.
radio_2g=""; radio_5g=""; n=0
while :; do
	for r in $(uci show wireless 2>/dev/null | sed -n 's/^wireless\.\([^.=]*\)=wifi-device$/\1/p'); do
		case "$(uci -q get wireless.$r.band)" in
		2g) radio_2g="$r" ;;
		5g) radio_5g="$r" ;;
		esac
	done
	[ -n "$radio_2g" ] && [ -n "$radio_5g" ] && break
	[ $n -eq 0 ] && echo "Cho radio Wi-Fi san sang (toi da 2 phut)..." >&2
	n=$((n + 1)); [ $n -le 24 ] || { echo "Khong tim thay radio 2g/5g" >&2; exit 1; }
	sleep 5
done

# Ten Wi-Fi: bien moi truong neu da dat, khong thi hoi (Enter = mac dinh). SSID toi da 32 byte.
read_ssid() {
	s="$3"
	if [ -z "$s" ]; then
		printf '%s [%s]: ' "$1" "$2" >&2
		read -r s
		s="${s:-$2}"
	fi
	[ ${#s} -le 32 ] || { echo "Ten Wi-Fi toi da 32 byte: $s" >&2; exit 1; }
	echo "$s"
}
SSID_5G="$(read_ssid "Ten Wi-Fi 5 GHz" DHs-5GHz "$SSID_5G")"
SSID_IOT="$(read_ssid "Ten Wi-Fi IoT 2.4 GHz" DHs-IoT "$SSID_IOT")"
[ "$SSID_5G" != "$SSID_IOT" ] || { echo "Hai ten Wi-Fi phai khac nhau" >&2; exit 1; }

# BusyBox khong co stty; read -s cua ash tat hien ky tu
read_key() {
	printf '%s: ' "$1" >&2
	read -rs k; echo >&2
	[ ${#k} -ge 8 ] || { echo "Mat khau phai tu 8 ky tu" >&2; exit 1; }
	echo "$k"
}
KEY_5G="$(read_key "Mat khau $SSID_5G")"
KEY_IOT="$(read_key "Mat khau $SSID_IOT")"

# Xoa cac SSID cu, giu cau hinh radio. Moi radio dung 1 SSID (moi SSID them ton bo dem).
for i in $(uci show wireless | sed -n 's/^wireless\.\([^.=]*\)=wifi-iface$/\1/p'); do
	uci delete wireless.$i
done

uci set wireless.$radio_2g.country='VN'
uci set wireless.$radio_2g.channel="$ch2"
uci set wireless.$radio_2g.htmode='HE20'
uci set wireless.$radio_2g.cell_density='0'
uci set wireless.$radio_2g.legacy_rates='0'   # mac dinh da la 0: khong 802.11b, toc do co ban 6/12/24
uci -q delete wireless.$radio_2g.disabled || true

uci set wireless.$radio_5g.country='VN'
uci set wireless.$radio_5g.channel="$ch5"
uci set wireless.$radio_5g.htmode='HE80'
uci set wireless.$radio_5g.cell_density='0'
uci -q delete wireless.$radio_5g.disabled || true

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
uci set wireless.iot.disassoc_low_ack='1'

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
uci set wireless.fast5g.rrm_beacon_report='1'   # usteer hoi client "thay AP nao, manh bao nhieu"
uci set wireless.fast5g.bss_transition='1'
uci set wireless.fast5g.wnm_sleep_mode='1'
uci set wireless.fast5g.disassoc_low_ack='1'    # client mat ACK lien tuc (da di xa) -> cat ngay

uci set system.@system[0].hostname="$name"

# IGMP snooping tren br-lan: multicast co nhom (SSDP, IPTV...) chi gui toi client da dang ky,
# va netifd doi sang unicast tren cong Wi-Fi (unicast co ACK + gui lai, khong ton airtime toc do
# thap). Khong co IGMP querier tren mang thi bridge van flood nhu cu. Tat: MCAST_SNOOP=0.
brdev=""
for d in $(uci show network | sed -n 's/^network\.\([^.=]*\)=device$/\1/p'); do
	if [ "$(uci -q get network.$d.name)" = "br-lan" ]; then brdev="$d"; fi
done
if [ -n "$brdev" ]; then
	uci set network.$brdev.igmp_snooping="${MCAST_SNOOP:-1}"
fi

# usteer: cac AP trao doi qua br-lan, chi dieu phoi Wi-Fi 5 GHz (Wi-Fi IoT khong bi dung toi).
# Nguong < 0 la dBm. Luong roam: tin hieu < roam_scan_snr -> xin client quet (beacon report);
# co AP khac manh hon >= signal_diff_threshold dB va >= roam_trigger_snr -> gui BSS Transition
# (802.11v) chi ten AP do; client khong chiu di sau roam_kick_delay -> ngat de no tu chon lai.
# signal_diff_threshold = 0 (mac dinh) thi usteer KHONG BAO GIO chu dong roam.
u=usteer.@usteer[0]
uci -q get $u >/dev/null || uci add usteer usteer >/dev/null
uci set $u.network='lan'
uci -q delete $u.ssid_list || true
uci add_list $u.ssid_list="$SSID_5G"
uci set $u.syslog='1'
uci set $u.debug_level="${USTEER_DEBUG:-1}"
uci set $u.roam_scan_snr="${ROAM_SCAN:--70}"
uci set $u.roam_trigger_snr="${ROAM_TRIGGER:--75}"
uci set $u.signal_diff_threshold="${ROAM_DIFF:-8}"
uci set $u.roam_scan_interval='5000'       # mac dinh 10s
uci set $u.roam_trigger_interval='20000'   # mac dinh 60s; cung la thoi gian toi thieu da ket noi
                                           # truoc khi bi dieu phoi -> 60s qua lau khi len cau thang
uci set $u.roam_kick_delay='10000'
uci set $u.band_steering_interval='0'      # moi bang tan la 1 SSID rieng, khong can band steering
uci -q delete $u.event_log_types || true
for t in signal_kick assoc_req_deny; do uci add_list $u.event_log_types="$t"; done

# IP du phong 192.168.1.1 chi de vao AP truoc khi setup. Moi AP deu co dia chi nay: usteer gui
# broadcast tu 192.168.1.1, AP nhan coi la goi cua chinh minh va bo -> cac AP khong thay nhau.
# Giu lai: KEEP_FALLBACK=1.
fallback_now=0
if [ "${KEEP_FALLBACK:-0}" != 1 ] && uci -q get network.lan_fallback >/dev/null; then
	uci set network.lan_fallback.auto='0'
	fallback_now=1
fi

uci commit wireless
uci commit network
uci commit system
uci commit usteer
/etc/init.d/system reload
[ -z "$brdev" ] || /etc/init.d/network reload
/etc/init.d/usteer enable
/etc/init.d/usteer restart
/etc/init.d/roam-cleanup enable
/etc/init.d/roam-cleanup restart
wifi reload

if [ "$opt" = "--no-luci" ]; then
	/etc/init.d/uhttpd stop || true; /etc/init.d/uhttpd disable || true
	/etc/init.d/rpcd stop || true; /etc/init.d/rpcd disable || true
	echo "Da tat LuCI (uhttpd, rpcd)"
fi
echo "Xong: $name, 2.4G kenh $ch2 (HE20), 5G kenh $ch5 (HE80), mobility domain $MOBILITY_DOMAIN"

if [ $fallback_now = 1 ]; then
	case "${SSH_CONNECTION:-}" in
	192.168.1.*)
		# Dang SSH qua chinh IP du phong: tat bay gio se cat phien nay
		echo "IP du phong 192.168.1.1 se tat o lan khoi dong sau (hoac chay: ifdown lan_fallback)" ;;
	*)
		ifdown lan_fallback 2>/dev/null || true
		echo "Da tat IP du phong 192.168.1.1" ;;
	esac
fi
