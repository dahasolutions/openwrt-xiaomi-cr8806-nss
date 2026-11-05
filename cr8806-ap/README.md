# CR8806 AP (NSS)

Bản build **dumb AP** cho Xiaomi CR8806 (M79) trên cây NSS của `main`, dùng làm điểm phát Wi-Fi
nối dây về router chính, có roaming 802.11k/v/r giữa nhiều AP.

## Khác gì bản release của `main`

| | Thay đổi | Lý do |
|---|---|---|
| Kernel | `# CONFIG_BPF_JIT is not set` trong `ipq50xx/config-default` | ~2 MiB (`bpf_prog_pack`) |
| Bỏ | SQM, shaper/IGS NSS, `tc-full`, `cake`, `ifb` | AP không cần |
| Bỏ | `ppp`, `ppp-mod-pppoe`, `dnsmasq`, `odhcpd` | AP không quay PPPoE, không cấp DHCP |
| Bỏ | USB (máy không có cổng), `e2fsprogs`, `dumpimage`, `ATH_DEBUG`; `iperf3` thành gói riêng | RAM, flash |
| Giữ | `firewall4`, `kmod-nf-conntrack`, `kmod-ppp(oe)` | phụ thuộc của ECM |
| Thêm | `wpad-mbedtls` (đầy đủ) thay `wpad-basic`, `usteer`, `luci-app-usteer` | 802.11k/v/r, điều phối client |
| Thêm | `zram-swap` | vùng đệm RAM |
| Thêm | image initramfs | chạy thử trên RAM trước khi ghi flash |

## Mặc định sau khi flash

- 4 cổng (lan1-3 + wan) chung `br-lan`, **lấy IP bằng DHCP** từ router chính, không cấp DHCP.
- IP dự phòng **192.168.1.1/24** trên `br-lan` để vào AP **trước khi setup** (cắm máy tính, đặt IP
  192.168.1.2). `setup-ap.sh` tắt nó: AP nào cũng có địa chỉ này, usteer gửi tin từ 192.168.1.1 nên
  các AP bỏ gói của nhau và không thấy nhau. Giữ lại bằng `KEEP_FALLBACK=1`.
- Múi giờ Asia/Ho_Chi_Minh, NTP Việt Nam.
- **Wi-Fi tạm** 2.4 GHz `DHs-AP-XXXX` (XXXX = 4 ký tự cuối MAC trên tem), mật khẩu `88888888`, để vào
  AP lần đầu không cần dây. Hostname cũng là `DHs-AP-XXXX` (tìm IP trong DHCP của router). Chạy
  `setup-ap.sh` thì Wi-Fi tạm bị xoá. Chỉ xuất hiện khi chưa có cấu hình Wi-Fi (lần flash đầu
  hoặc `sysupgrade -n`), `sysupgrade` giữ cấu hình thì không.

## Cấu hình từng AP

```sh
sh /root/setup-ap.sh Mesh1F 1 36
sh /root/setup-ap.sh Mesh2F 6 149
sh /root/setup-ap.sh Mesh3F 11 36     # thêm --no-luci để tắt giao diện web, lấy lại RAM
```

- `DHs-5GHz`: WPA2 + 802.11r (FT-PSK, mobility domain chung) + 802.11k/v (có beacon report), usteer
  chủ động đẩy client sang AP mạnh hơn: dưới -70 dBm thì xin client quét, AP khác mạnh hơn 8 dB
  thì gửi BSS Transition. Ngưỡng chỉnh được bằng `ROAM_SCAN`, `ROAM_TRIGGER`, `ROAM_DIFF`.
- IGMP snooping trên `br-lan` (tắt bằng `MCAST_SNOOP=0`).
- `roam-cleanup` (service): client đã roam sang AP khác (usteer thấy) mà AP cũ còn giữ thì gỡ
  ngay, thay vì chờ driver tự phát hiện mất ACK (~8 s). Trong ~8 s đó, máy nối cùng AP cũ không
  liên lạc được với client vừa roam. Log: `logread -e roam-cleanup`.
- `net.core.message_cost=300`: chặn dòng `eth0: dropped frame` (bản sao broadcast không tag mà
  tag driver `qca-8021q` bỏ) làm đầy log. NTP khởi động lại khi `lan` có IP (hotplug).
- `DHs-IoT`: WPA2 thuần, không 802.11r/k/v.

## Build

GitHub Actions: workflow **CR8806 AP build** (chạy tay). Hoặc trên Linux: `sh cr8806-ap/build.sh`.
Kết quả ở `bin/cr8806-ap/`.

## Flash

Từng bước chi tiết: [FLASH.md](FLASH.md). Tóm tắt: lần đầu cần UART + TFTP (hoặc SSH từ firmware
gốc Xiaomi), boot initramfs trước, ổn rồi mới ghi `factory.ubi` vào **slot không đang chạy**, giữ
slot kia làm đường lui. Đây là bản tự build, không có bảo hành.
