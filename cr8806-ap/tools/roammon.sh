#!/bin/sh
# Theo doi 1 thiet bi Wi-Fi chuyen giua cac AP OpenWrt (chay tren may tinh, doc qua SSH).
#   MAC=d0:4d:86:f3:67:21 sh roammon.sh 192.168.2.81 192.168.2.82 192.168.2.83
# Tuy chon: INTERVAL (giay, mac dinh 2), DURATION (giay, mac dinh 600), LOG (file, mac dinh roam-<gio>.log)
#
# Moi lan doc, voi tung AP: interface, tin hieu (dBm), thoi gian da ket noi (giay) va AKM
# lay tu hostapd_cli:  00-0f-ac-4 = FT-PSK (802.11r dang dung)   00-0f-ac-2 = WPA2-PSK thuong
# AP hien tai = AP co thoi gian ket noi nho nhat (AP cu con giu entry them mot luc sau khi roi).
# Can SSH vao AP khong hoi mat khau: them public key cua may tinh vao /etc/dropbear/authorized_keys.

MAC=$(echo "${MAC:?dat MAC cua thiet bi, vd MAC=d0:4d:86:f3:67:21}" | tr 'A-F' 'a-f')
INTERVAL=${INTERVAL:-2}
DURATION=${DURATION:-600}
LOG=${LOG:-roam-$(date +%Y%m%d-%H%M%S).log}
[ $# -ge 1 ] || { sed -n '2,10p' "$0"; exit 1; }

ctl=$(mktemp -d)
trap 'for ip in "$@"; do ssh -o ControlPath="$ctl/%h" -O exit "root@$ip" 2>/dev/null; done; rm -rf "$ctl"' EXIT INT TERM
SSH="ssh -o BatchMode=yes -o ConnectTimeout=3 -o ControlMaster=auto -o ControlPath=$ctl/%h -o ControlPersist=15m"

remote='mac='"$MAC"'
for i in $(iw dev | awk "/Interface/{print \$2}"); do
	o=$(iw dev $i station get $mac 2>/dev/null) || continue
	sig=$(echo "$o" | awk "/signal:/{print \$2; exit}")
	ct=$(echo "$o" | awk "/connected time/{print \$3}")
	akm=$(hostapd_cli -i $i sta $mac 2>/dev/null | sed -n "s/^AKMSuiteSelector=//p")
	echo "$i $sig $ct ${akm:--}"
done'

akm_name() {
	case "$1" in
	00-0f-ac-4) echo FT-PSK ;;
	00-0f-ac-2) echo PSK ;;
	00-0f-ac-9) echo FT-SAE ;;
	00-0f-ac-8) echo SAE ;;
	*) echo "$1" ;;
	esac
}

echo "Theo doi $MAC tren: $* (moi ${INTERVAL}s, ${DURATION}s) -> $LOG"
end=$(( $(date +%s) + DURATION ))
last=""
while [ "$(date +%s)" -lt "$end" ]; do
	now=$(date +%H:%M:%S)
	line=""; best=""; bestct=999999999
	for ip in "$@"; do
		out=$($SSH "root@$ip" "$remote" 2>/dev/null)
		[ -n "$out" ] || continue
		host=${ip##*.}
		while read -r ifc sig ct akm; do
			[ -n "$ifc" ] || continue
			line="$line | .$host $ifc ${sig}dBm ${ct}s $(akm_name "$akm")"
			if [ "${ct:-999999999}" -lt "$bestct" ]; then bestct=$ct; best=".$host/$ifc $(akm_name "$akm")"; fi
		done <<EOF
$out
EOF
	done
	if [ -z "$line" ]; then
		msg="$now KHONG KET NOI"; cur="none"
	else
		msg="$now hien tai: $best$line"; cur="${best%% *}"
	fi
	[ "$cur" != "$last" ] && msg="$msg   <<< DOI"
	echo "$msg" | tee -a "$LOG"
	last="$cur"
	sleep "$INTERVAL"
done
