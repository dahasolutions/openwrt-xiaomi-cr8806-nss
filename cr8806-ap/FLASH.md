# Flash bản CR8806 AP (NSS) lên Xiaomi CR8806 (M79)

Hướng dẫn này dựa trên phần *Flash instructions* trong commit thêm thiết bị
`84bfba4acc` ("qualcommax: ipq50xx: add Xiaomi CR8806 (M79) with NSS offload") của
fanha99, áp cho bản build trong release `cr8806-ap-*` của fork này.

> [!WARNING]
> Đây là bản tự build, chưa có ai flash thử bản AP này trên máy thật. Flash sai bước có
> thể làm máy không khởi động được. Làm trên **1 AP** trước, giữ slot cũ làm đường lui.

## 0. Tổng quan

CR8806 có **2 slot hệ thống** (Xiaomi dual-boot):

| Slot | Phân vùng | Thiết bị |
|---|---|---|
| 0 | `rootfs` | `/dev/mtd18` |
| 1 | `rootfs_1` | `/dev/mtd19` |

Firmware 集客 (Gecoos) đang chạy ở một slot. OpenWrt sẽ được ghi vào **slot còn lại**.
Nếu OpenWrt lỗi, chỉ cần chọn lại slot cũ.

Trình tự:

1. Nối UART, dừng U-Boot.
2. Boot image **initramfs** từ TFTP: OpenWrt chạy trên RAM, chưa ghi gì vào flash.
3. Kiểm tra máy chạy ổn (mạng dây, Wi-Fi, NSS).
4. Từ initramfs, ghi `factory.ubi` vào slot không đang dùng, đặt cờ khởi động, khởi động lại.
5. Cấu hình Wi-Fi bằng `/root/setup-ap.sh`.

## 1. Chuẩn bị

### Phần cứng
- **Adapter USB-TTL 3.3 V** (CP2102, CH340, FT232…). **Không dùng 5 V.**
- 3 dây jumper. Đầu đực có thể cắm thẳng vào lỗ, hoặc dùng kim/pogo pin.
- 1 dây LAN nối máy tính với AP.
- Nguồn 12 V 1 A của chính AP. Không dùng nguồn chập chờn trong lúc flash.

### File (từ release `cr8806-ap-*`)
```
openwrt-qualcommax-ipq50xx-xiaomi_cr8806-initramfs-uImage.itb
openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-factory.ubi
sha256sums
```
Kiểm tra trước khi dùng:
```sh
shasum -a 256 -c sha256sums 2>/dev/null | grep -E 'initramfs|factory'
# cả 2 dòng phải là OK
```
Ghi lại kích thước file `factory.ubi` (byte), dùng ở bước 5:
```sh
stat -f %z openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-factory.ubi
# bản cr8806-ap-2026.11.04-1: 16384000
```

### Máy tính (macOS)
- **TFTP server** có sẵn trên macOS:
  ```sh
  sudo cp openwrt-qualcommax-ipq50xx-xiaomi_cr8806-initramfs-uImage.itb /private/tftpboot/cr.itb
  sudo chmod 644 /private/tftpboot/cr.itb
  sudo launchctl load -F /System/Library/LaunchDaemons/tftp.plist
  # xong việc thì tắt: sudo launchctl unload -F /System/Library/LaunchDaemons/tftp.plist
  ```
- **IP tĩnh** cho cổng mạng nối với AP: `192.168.1.2`, mask `255.255.255.0`, không cần gateway
  (System Settings → Network → cổng Ethernet/USB-LAN → Details → TCP/IP → Manually).
- **Terminal serial:** `screen` có sẵn. Tìm tên adapter:
  ```sh
  ls /dev/tty.usbserial* /dev/tty.wchusbserial* /dev/tty.SLAB* 2>/dev/null
  ```
  CH340 trên macOS đời mới thường không cần cài driver. Nếu không thấy thiết bị, cài driver
  của hãng chip.

## 2. Nối UART (không cần mở vỏ)

Header **J1**: 4 lỗ chưa hàn chân, **cạnh jack nguồn DC**, nhìn được qua khe thoáng.
Thứ tự **từ trái sang phải**:

| Lỗ | Chân bo mạch | Nối với adapter |
|---|---|---|
| 1 | (không ghi) | **KHÔNG NỐI** (thường là nguồn) |
| 2 | RX | **TX** của adapter |
| 3 | GND | **GND** |
| 4 | TX | **RX** của adapter |

- TX và RX nối **chéo**: TX của adapter vào RX của bo mạch, và ngược lại.
- **Không nối chân VCC/3.3 V** của adapter. AP được cấp nguồn bằng adapter 12 V của nó.

Mở terminal (thay đúng tên thiết bị):
```sh
screen /dev/tty.usbserial-XXXX 115200
# thoát screen: Ctrl-A rồi K, xác nhận y
```

## 3. Dừng U-Boot

1. Rút điện AP. Cắm dây LAN từ máy tính vào **cổng LAN1** của AP.
2. Cắm điện. Màn hình serial sẽ chạy log U-Boot.
3. Khi thấy dòng đếm ngược kiểu `Hit any key to stop autoboot`, **bấm phím bất kỳ** (ví dụ
   Enter liên tục ngay khi cắm điện). Dấu nhắc U-Boot hiện ra (thường là `IPQ5018#`).

**Nếu thấy log mà gõ phím không có tác dụng:** U-Boot của Xiaomi có thể đang tắt nhập liệu qua
UART (`uart_en`). Xem mục [Phụ lục A](#phụ-lục-a-u-boot-không-nhận-phím).

Ghi lại cờ khởi động hiện tại, để biết firmware 集客 đang ở slot nào:
```
printenv flag_boot_rootfs flag_last_success flag_try_sys1_failed flag_try_sys2_failed
```
`flag_last_success=0` nghĩa là đang chạy **slot 0** (`rootfs`, mtd18), `=1` là **slot 1**
(`rootfs_1`, mtd19). **Chụp lại màn hình này**, cần cho bước 5 và khi muốn quay lại.

## 4. Boot initramfs (chạy thử trên RAM)

Tại dấu nhắc U-Boot:
```
setenv ipaddr 192.168.1.1
setenv serverip 192.168.1.2
tftpboot 0x44000000 cr.itb
bootm 0x44000000#config@mp02.1
```
- `tftpboot` phải báo đã tải khoảng 15 MB. Nếu báo timeout: kiểm tra IP máy tính, TFTP server
  và firewall macOS, hoặc thử cắm dây sang cổng LAN khác hoặc cổng WAN.
- Lệnh `setenv` ở đây **không** `saveenv`, nên không thay đổi gì vĩnh viễn.

Máy boot OpenWrt từ RAM, **flash chưa bị đụng tới**. Rút điện là quay về firmware cũ.

### Kiểm tra trong initramfs
Bản AP luôn có IP dự phòng **192.168.1.1** trên `br-lan`, nên từ máy tính (`192.168.1.2`):
```sh
ssh root@192.168.1.1          # chưa có mật khẩu, Enter là vào
```
Trong AP:
```sh
cat /proc/mtd                         # phải có rootfs (mtd18), rootfs_1 (mtd19)
logread -e nss | tail -5              # có dòng NSS ... ECM up
grep MemAvailable /proc/meminfo
ls /proc/sys/net/core/bpf_jit_enable  # "No such file" = BPF JIT đã tắt, đúng
fw_printenv flag_boot_rootfs flag_last_success
```
- Có thể cắm thêm dây từ router nhà vào một cổng khác của AP, rồi `ip -4 addr show br-lan`:
  ngoài `192.168.1.1` phải có thêm IP `192.168.2.x` do router cấp.
- Initramfs chiếm thêm RAM (toàn bộ hệ thống nằm trong RAM). **Không đo tải nặng ở bước này**,
  tác giả cảnh báo có thể hết RAM.

Mọi thứ ổn thì sang bước 5. Có lỗi thì rút điện là xong, báo lại log.

## 5. Ghi vào slot không đang chạy

Chọn slot đích dựa vào bước 3:

| Firmware 集客 đang ở | Ghi OpenWrt vào | Thiết bị |
|---|---|---|
| slot 0 (`flag_last_success=0`) | **slot 1** | `/dev/mtd19` |
| slot 1 (`flag_last_success=1`) | **slot 0** | `/dev/mtd18` |

Kiểm tra lại tên phân vùng trước khi ghi, **không ghi nhầm slot đang chứa firmware cũ**:
```sh
ssh root@192.168.1.1 "grep -E 'rootfs' /proc/mtd"
# mtd18: ... "rootfs"
# mtd19: ... "rootfs_1"
```

Từ **máy tính** (thư mục chứa file), ví dụ ghi vào **slot 1 (mtd19)**:
```sh
ssh root@192.168.1.1 "ubiformat /dev/mtd19 -y -f - -S 16384000" \
  < openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-factory.ubi
```
`-S` là kích thước file `factory.ubi` (byte) ghi ở bước 1. Lệnh phải kết thúc không báo lỗi.

Đặt cờ để U-Boot khởi động slot vừa ghi, rồi khởi động lại (chạy trong AP):

**Nếu ghi vào slot 1 (mtd19):**
```sh
fw_setenv flag_try_sys2_failed 0
fw_setenv flag_last_success 1
fw_setenv flag_ota_reboot 0
reboot
```
**Nếu ghi vào slot 0 (mtd18):**
```sh
fw_setenv flag_try_sys1_failed 0
fw_setenv flag_last_success 0
fw_setenv flag_ota_reboot 0
reboot
```

## 6. Lần khởi động đầu

- Lần đầu, OpenWrt chạy script `99-cr8806-ap`: gộp 4 cổng vào `br-lan`, lấy IP bằng DHCP,
  giữ IP dự phòng `192.168.1.1`, đặt múi giờ Việt Nam. Chờ khoảng 1–2 phút.
- AP phát **Wi-Fi tạm** 2.4 GHz `DHs-AP-XXXX` (XXXX = 4 ký tự cuối MAC in trên tem), mật khẩu
  `88888888`. Hostname của AP cũng là `DHs-AP-XXXX`.
- Cắm AP vào mạng nhà (cổng nào cũng được), điện thoại/máy tính vào `DHs-AP-XXXX` (hoặc Wi-Fi nhà).
  Tìm IP của AP trong danh sách DHCP của router (tên `DHs-AP-XXXX`), mở `http://<IP-AP>` hoặc SSH.
  Nên đặt **DHCP reservation** cho AP.
- AP **không cấp DHCP**: nếu AP chưa cắm vào router, máy vào Wi-Fi tạm sẽ không có IP. Khi đó đặt
  IP tĩnh `192.168.1.2/24` (iPhone: *Cài đặt → Wi-Fi → (i) → Cấu hình IP → Thủ công*) rồi vào
  `192.168.1.1`. Hoặc cắm dây máy tính `192.168.1.2`.
- Ai trong tầm sóng biết mật khẩu `88888888` là vào được AP với quyền root khi chưa đặt mật khẩu,
  nên làm **ngay** 2 việc dưới và bước 7.

```sh
ssh root@<IP-AP>
passwd                                   # đặt mật khẩu root ngay
fw_printenv flag_last_success            # đúng slot vừa ghi
```

## 7. Cấu hình Wi-Fi

```sh
sh /root/setup-ap.sh Mesh1F 1 36         # tên, kênh 2.4G, kênh 5G
# script hỏi mật khẩu DHs-5GHz và DHs-IoT (không hiện khi gõ)
```
Script xoá mọi SSID cũ, gồm cả Wi-Fi tạm `DHs-AP-XXXX`. Nếu đang SSH qua Wi-Fi tạm, kết nối sẽ rớt
khi script chạy tới `wifi reload`; vào lại qua `DHs-5GHz` hoặc Wi-Fi nhà. Hostname đổi thành
`Mesh1F`... (router có thể vẫn hiện tên cũ tới lần gia hạn DHCP sau).
Các AP còn lại: `Mesh2F 6 149`, `Mesh3F 11 36` (hoặc `52` nếu iPhone nhảy nhầm tầng).
Tên SSID, mật khẩu và mobility domain phải **giống nhau** trên mọi AP. Chi tiết và cách
đổi tên SSID: xem `README.md`.

Kiểm tra:
```sh
iw dev                                   # 2 SSID đúng kênh
logread -e nss | tail -3
grep MemAvailable /proc/meminfo          # lúc nghỉ ~25 MiB trở lên
ubus call usteer remote_info             # khi có từ 2 AP OpenWrt trở lên
```

Sao lưu cấu hình sau khi xong:
```sh
sysupgrade -b /tmp/backup-$(uci get system.@system[0].hostname).tar.gz
# trên máy tính: scp root@<IP-AP>:/tmp/backup-*.tar.gz .
```

## 8. Quay lại firmware cũ

Slot chứa firmware 集客 **không bị đụng tới**. Để khởi động lại nó:

- **Từ OpenWrt**, ví dụ OpenWrt ở slot 1 và firmware cũ ở slot 0:
  ```sh
  fw_setenv flag_try_sys1_failed 0
  fw_setenv flag_last_success 0
  fw_setenv flag_ota_reboot 0
  reboot
  ```
  (đảo lại nếu OpenWrt ở slot 0: `flag_try_sys2_failed 0`, `flag_last_success 1`)
- **Từ U-Boot** (OpenWrt không boot được), đặt các cờ trên bằng `setenv` rồi `saveenv`, `reset`.
- **Cứu hộ cuối cùng:** MiWiFi Repair Tool (khôi phục TFTP của Xiaomi) đưa máy về firmware
  gốc. Xem Phụ lục B.

## 9. Nâng cấp về sau

Khi đã chạy OpenWrt, bản build mới cài bằng file `sysupgrade.bin`:
```sh
scp openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-sysupgrade.bin root@<IP-AP>:/tmp/
ssh root@<IP-AP> "sysupgrade -v /tmp/openwrt-qualcommax-ipq50xx-xiaomi_cr8806-squashfs-sysupgrade.bin"
```
`sysupgrade` giữ cấu hình và tự ghi vào đúng slot. Sau khi nâng cấp, nếu đã tắt LuCI thì
kiểm tra lại (trạng thái tắt/bật dịch vụ có thể không được giữ).

## 10. Kiểm tra NSS và k/v/r

### NSS có thật sự tăng tốc không
Theo mục *Checking that it works* trong `README.ipq50xx.md`:
```sh
ls /etc/rc.d | grep S19nss                        # dịch vụ arm NSS đã cài
logread -e nss                                    # kết thúc bằng "NSS wired plane + ECM up (Wi-Fi on the NSS path)"
cat /sys/kernel/debug/qca-dwmac-nss/status        # cổng ở trạng thái "started"
cat /sys/kernel/debug/ecm/ecm_nss_ipv4/tcp_accelerated_count   # > 0 khi đang có lưu lượng
grep -m1 ipv4_rx_pkts /sys/kernel/debug/qca-nss-drv/stats/ipv4 # tăng dần khi có lưu lượng
nssinfo                                           # tải lõi NSS, số gói
```
Phép thử trung thực nhất là **CPU**: chạy iperf3 giữa điện thoại (app iPerf, nối Wi-Fi của AP)
và một máy tính **cắm dây** trong mạng nhà (`iperf3 -s`), đồng thời chạy `top` trên AP.
- NSS chạy: tốc độ cao, CPU **rảnh > 90 %**, softirq gần như không tăng.
- NSS không chạy: CPU bận hẳn, tốc độ thấp hơn nhiều.

Dễ hiểu nhầm:
- Bộ đếm của các cổng mạng có thể không thấy lưu lượng đã được tăng tốc.
- `ipv4_rx_byts` đếm cả 2 chiều, chia đôi mới ra tốc độ thật.
- **Không bật "flow offloading"** trong firewall: nó chặn trước ECM, NSS không tăng tốc được.
- Image không có iperf3 (để tiết kiệm RAM): chạy server trên máy tính, client trên điện thoại.

### 802.11r/k/v có hoạt động không
Tên interface xem bằng `iw dev` (dạng `phy1-ap0` cho 5 GHz).

| Kiểm tra | Lệnh | Dấu hiệu đúng |
|---|---|---|
| r đang dùng | `hostapd_cli -i phy1-ap0 all_sta \| grep -E '^[0-9a-f:]{17}\|AKMSuiteSelector'` | Client ở `DHs-5GHz` có AKM `00-0f-ac-4` (FT-PSK). `00-0f-ac-2` là WPA2-PSK thường |
| r lúc chuyển AP | `logread -f -e hostapd` trong khi đi giữa các tầng | Kết nối lại **không** kèm bắt tay 4 bước (`sending 1/4 … 4/4`) |
| k | `ubus call hostapd.phy1-ap0 rrm_nr_list` | Có BSSID của các AP còn lại |
| usteer thấy nhau | `ubus call usteer remote_info` | Liệt kê các AP khác |
| usteer đã nhận ngưỡng | `ubus call usteer get_config` | `roam_scan_snr -70`, `roam_trigger_snr -75`, `signal_diff_threshold 8` |
| k (beacon report) | `ubus call usteer get_client_info '{"address":"d0:4d:86:f3:67:21"}'` | Có tín hiệu client đo được ở **AP khác** (client trả lời beacon report) |
| v / usteer điều phối | `uci set usteer.@usteer[0].debug_level=2; uci commit usteer; /etc/init.d/usteer restart; logread -f -e usteer` | Thấy usteer quyết định chuyển client |
| v lúc chuyển AP | `logread -f -e hostapd` | Có `BSS-TM-RESP` từ client, `status_code=0` là client đồng ý chuyển |

### Chỉnh ngưỡng roaming
`setup-ap.sh` đặt usteer như sau (đơn vị dBm, chỉ áp dụng cho `DHs-5GHz`):

| Option | Giá trị | Ý nghĩa |
|---|---|---|
| `roam_scan_snr` | -70 | Tín hiệu dưới mức này thì AP xin client quét xung quanh (beacon report) |
| `roam_trigger_snr` | -75 | AP đích phải mạnh hơn mức này mới được chọn |
| `signal_diff_threshold` | 8 | AP đích phải mạnh hơn AP hiện tại ít nhất 8 dB. **Để 0 thì usteer không bao giờ đẩy client** |
| `roam_trigger_interval` | 20000 | Phải kết nối đủ 20 giây mới bị điều phối, và giữa 2 lần điều phối cách nhau 20 giây (mặc định 60 giây) |
| `roam_kick_delay` | 10000 | Gửi BSS Transition (802.11v) xong mà 10 giây client không đi thì ngắt kết nối để client tự chọn lại |

Điện thoại vẫn bám AP cũ quá lâu thì nâng ngưỡng (ví dụ -67 / -72). Nếu điện thoại nhảy qua lại
giữa 2 tầng thì hạ ngưỡng xuống hoặc tăng chênh lệch lên 10. Đổi trên **cả 3 AP** cho giống nhau:
```sh
uci set usteer.@usteer[0].roam_scan_snr=-67
uci set usteer.@usteer[0].roam_trigger_snr=-72
uci commit usteer && /etc/init.d/usteer restart
```
Hoặc chạy lại setup với biến môi trường: `ROAM_SCAN=-67 ROAM_TRIGGER=-72 sh /root/setup-ap.sh Mesh1F 1 36`.

IGMP snooping đang bật trên `br-lan` (multicast chỉ gửi tới máy đã đăng ký, trên Wi-Fi được đổi
thành unicast). Nếu Chromecast, AirPlay hay thiết bị IoT mất kết nối với app thì tắt bằng
`uci set network.@device[0].igmp_snooping=0; uci commit network; /etc/init.d/network reload`
(kiểm tra `uci show network | grep br-lan` để chắc `@device[0]` là br-lan), hoặc chạy lại setup
với `MCAST_SNOOP=0`.

### Theo dõi một thiết bị chuyển tầng
`tools/roammon.sh` chạy trên máy tính, đọc cả 3 AP qua SSH mỗi 2 giây: AP đang kết nối,
tín hiệu, thời gian kết nối, và **AKM (FT-PSK hay PSK)** ngay sau mỗi lần chuyển.

1. Cho phép SSH không hỏi mật khẩu (làm 1 lần trên mỗi AP):
   ```sh
   cat ~/.ssh/id_ed25519.pub | ssh root@<IP-AP> "cat >> /etc/dropbear/authorized_keys"
   ```
2. Chạy, rồi cầm điện thoại đi tầng 1 → 2 → 3 → 2 → 1 (mỗi tầng dừng ~20 giây):
   ```sh
   MAC=d0:4d:86:f3:67:21 sh cr8806-ap/tools/roammon.sh 192.168.2.81 192.168.2.82 192.168.2.83
   ```
   Dòng có `<<< DOI` là lúc chuyển AP; xem tín hiệu AP cũ trước đó và chữ `FT-PSK` ở AP mới.
   Kết quả ghi vào `roam-<giờ>.log`. iPhone dùng địa chỉ Wi-Fi riêng cho từng mạng:
   lấy MAC trong *Cài đặt → Wi-Fi → (i) → Địa chỉ Wi-Fi*.

## Phụ lục A: U-Boot không nhận phím

U-Boot của Xiaomi có thể tắt nhập liệu qua UART. Theo repo `hzyitc/openwrt-redmi-ax3000`,
nhập liệu UART được mở sau **một lần khôi phục TFTP thành công** (MiWiFi Repair Tool, Phụ
lục B). Khi đã vào được dấu nhắc U-Boot, bật vĩnh viễn:
```
setenv boot_wait on
setenv uart_en 1
saveenv
```
Lưu ý: khôi phục TFTP sẽ ghi firmware gốc Xiaomi, firmware 集客 sẽ mất. Khi đó đường lui
là firmware gốc Xiaomi.

## Phụ lục B: Không dùng UART (qua SSH của firmware gốc Xiaomi)

Tác giả xác nhận có thể bỏ qua UART bằng cách SSH vào và ghi slot còn lại. Cách này **chưa
được thử** với bản AP này và có nhiều bước hơn:

1. **Về firmware gốc:** chạy MiWiFi Repair Tool (Windows) với firmware gốc đúng model. Rút điện,
   giữ nút reset, cắm điện; đèn nháy cam thì thả; chờ đèn nháy xanh.
2. **Lấy SSH:** dùng `xmir-patcher` (mục mở SSH, đăng nhập `root`/`root`).
3. **Sao lưu toàn bộ phân vùng** bằng `xmir-patcher` (bắt buộc).
4. Chép `factory.ubi` vào `/tmp`, xác định slot đang chạy (`cat /proc/cmdline`,
   `nvram get flag_last_success`), `ubiformat` slot **còn lại** như bước 5.
5. Đặt cờ bằng `nvram set flag_...=...` rồi `nvram commit` (firmware gốc dùng `nvram` thay
   cho `fw_setenv`), `reboot`.

Cách này không có bước chạy thử initramfs. Nếu OpenWrt không boot, U-Boot của Xiaomi sẽ thử
lại slot cũ sau vài lần thất bại (cờ `flag_try_sys*_failed`).
