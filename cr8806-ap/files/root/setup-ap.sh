#!/bin/sh
# Cau hinh Wi-Fi cho tung AP sau khi flash. Mat khau nhap luc chay, khong nam trong image.
#   sh /root/setup-ap.sh <ten> <kenh-2.4G> <kenh-5G> [--no-luci]
#   vi du:  sh /root/setup-ap.sh Mesh1F 1 36
#           sh /root/setup-ap.sh Mesh2F 6 149
#           sh /root/setup-ap.sh Mesh3F 11 52
#   --no-luci: tat uhttpd + rpcd (giao dien web) de lay lai ~2-3 MB RAM; bat lai bang
#              /etc/init.d/rpcd enable && /etc/init.d/rpcd start && /etc/init.d/uhttpd enable && /etc/init.d/uhttpd start
# Bien moi truong (tuy chon): SSID_5G, SSID_IOT, MOBILITY_DOMAIN (4 so hex, giong nhau o ca 3 AP)
#   ROAM_SCAN (-70), ROAM_TRIGGER (-75), ROAM_DIFF (8 dB), USTEER_DEBUG (1), MCAST_SNOOP (1)
#
# DHs-5GHz: 802.11r (FT-PSK sinh khoa tai cho) + 802.11k + 802.11v, usteer dieu phoi.
# DHs-IoT : WPA2 thuan, KHONG 802.11r/k/v (thiet bi IoT cu loi khi AP quang ba FT).

set -e
name="$1"; ch2="$2"; ch5="$3"; opt="$4"
[ -n "$name" ] && [ -n "$ch2" ] && [ -n "$ch5" ] || { sed -n '2,14p' "$0"; exit 1; }

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

# usteer: cac AP trao doi qua br-lan, chi dieu phoi DHs-5GHz (DHs-IoT khong bi dung toi).
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

uci commit wireless
uci commit network
uci commit system
uci commit usteer
/etc/init.d/system reload
[ -z "$brdev" ] || /etc/init.d/network reload
/etc/init.d/usteer enable
/etc/init.d/usteer restart
wifi reload

if [ "$opt" = "--no-luci" ]; then
	/etc/init.d/uhttpd stop || true; /etc/init.d/uhttpd disable || true
	/etc/init.d/rpcd stop || true; /etc/init.d/rpcd disable || true
	echo "Da tat LuCI (uhttpd, rpcd)"
fi
echo "Xong: $name, 2.4G kenh $ch2 (HE20), 5G kenh $ch5 (HE80), mobility domain $MOBILITY_DOMAIN"
