# CR8806 AP (NSS)

Bản build **dumb AP** cho Xiaomi CR8806 (M79) trên cây NSS của `main`, dùng làm điểm phát Wi-Fi
nối dây về router chính, có roaming 802.11k/v/r giữa nhiều AP.

## Khác gì bản release của `main`

| | Thay đổi | Lý do |
|---|---|---|
| Thêm | patch `999-998` (link descriptor cho 32 client mỗi radio, từ nhánh `testing`) | ~4 MiB RAM (NOTES mục 10) |
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

Script hỏi tên hai mạng Wi-Fi (Enter để giữ tên mặc định) rồi hỏi mật khẩu:

```
Ten Wi-Fi 5 GHz [DHs-5GHz]: NhaToi-5G
Ten Wi-Fi IoT 2.4 GHz [DHs-IoT]: NhaToi-IoT
Mat khau NhaToi-5G: ********
Mat khau NhaToi-IoT: ********
```

- **Mọi AP phải nhập cùng tên và cùng mật khẩu**, nếu không client sẽ coi là mạng khác và không
  roaming được. Tên tối đa 32 byte (chữ có dấu tốn 2-3 byte mỗi ký tự), hai tên phải khác nhau.
- Đặt sẵn tên để khỏi bị hỏi (vd. khi chạy lại cho nhiều AP):
  `SSID_5G=NhaToi-5G SSID_IOT=NhaToi-IoT sh /root/setup-ap.sh Mesh1F 1 36`.
- Usteer, `roam-cleanup` và `trafficled` tự theo tên mới, không cần sửa gì thêm.

Dưới đây gọi theo tên mặc định:

- `DHs-5GHz`: WPA2 + 802.11r (FT-PSK, mobility domain chung) + 802.11k/v (có beacon report), usteer
  chủ động đẩy client sang AP mạnh hơn: dưới -70 dBm thì xin client quét, AP khác mạnh hơn 8 dB
  thì gửi BSS Transition. Ngưỡng chỉnh được bằng `ROAM_SCAN`, `ROAM_TRIGGER`, `ROAM_DIFF`.
- IGMP snooping trên `br-lan` (tắt bằng `MCAST_SNOOP=0`).
- `roam-cleanup` (service): client đã roam sang AP khác (usteer thấy) mà AP cũ còn giữ thì gỡ
  ngay, thay vì chờ driver tự phát hiện mất ACK (~8 s). Trong ~8 s đó, máy nối cùng AP cũ không
  liên lạc được với client vừa roam. Log: `logread -e roam-cleanup`. Chỉ quét các SSID trong
  `ssid_list` của usteer (`DHs-5GHz`): SSID khác usteer không theo dõi nên không biết client ở AP
  nào, còn client IoT luôn im lặng nên trước đây bị hỏi usteer mỗi giây vô ích.
- `net.core.message_cost=300`: chặn dòng `eth0: dropped frame` (bản sao broadcast không tag mà
  tag driver `qca-8021q` bỏ) làm đầy log. NTP khởi động lại khi `lan` có IP (hotplug).
- `DHs-IoT`: WPA2 thuần, không 802.11r/k/v.

## Đèn LED

Mỗi đèn có hai màu: xanh, cam, bật cả hai thành màu pha. Xanh tối hơn nên dùng cho trạng thái
bình thường, cam và pha cho những gì cần thấy ngay. `trafficled` (service ucode) điều khiển:

| Đèn | Hiển thị | Ý nghĩa |
|---|---|---|
| Status | xanh đứng | bình thường |
| | cam đứng | thiếu sóng Wi-Fi (một radio không có interface AP nào up) |
| | cam nháy chậm | `lan` chưa có IP DHCP |
| | pha nháy | đang khởi động (tối đa 180 s) |
| Internet | xanh đứng | rảnh |
| | pha nháy | có lưu lượng Wi-Fi; nhanh dần 250/100/40 ms theo lưu lượng |
| | xanh nháy | chỉ có lưu lượng ở cổng LAN (thiết bị cắm dây vào AP) |
| | pha đứng | uplink dưới 1 Gbps (vẫn nháy pha/xanh khi có lưu lượng) |
| | cam nháy | không ping được gateway |
| | cam đứng | mọi cổng mất kết nối |
| Cả hai | pha nháy nhanh | `trafficled locate [giây]` (mặc định 30 s), để tìm AP |

Ngưỡng "rảnh" là 128 KB/s (`IDLE`), cao hơn mức nền của ~20 thiết bị IoT. Lưu lượng Wi-Fi đọc từ
`phy*-ap*` mỗi giây; cổng dây (`WIRED`, mặc định `lan1 lan2 lan3`) lấy trung bình 4 s vì NSS chỉ
cập nhật bộ đếm cổng dây theo đợt ~3 s, nên đèn đổi nhịp theo LAN chậm hơn vài giây. Không dùng
trigger `netdev` trên `wan` vì lý do đó; mục LED mặc định của board bị xoá khi flash.

## Tên thiết bị trong LuCI (DHCP lease từ router MikroTik)

AP không chạy DHCP nên tự nó không biết tên thiết bị. `lease-sync` (service ucode) lấy lease từ
REST API của MikroTik (RouterOS v7) 5 phút/lần và mỗi khi `lan` có IP, rồi cứ 10 giây ghi ra
`/tmp/dhcp.leases` **chỉ những client đang kết nối Wi-Fi vào chính AP đó** (file trên RAM, chỉ ghi
khi danh sách đổi). Nhờ vậy "Active DHCP Leases" của LuCI chỉ hiện máy đang ở AP này, không hiện
cả nhà. `/etc/config/dhcp` chỉ để LuCI đọc file đó. Tên ưu tiên **Comment** của lease, không có
thì dùng host-name. Thiết bị cắm dây vào cổng LAN của AP không có trong danh sách.

Đổi IP của AP thì thêm IP mới vào `address` của `www-ssl` và của user `ap-sync`, không thì
router cắt kết nối (`SSL - The connection indicated an EOF`).

Trên MikroTik (một lần):
```
/certificate add name=rest-api common-name=router.lan days-valid=3650
/certificate sign rest-api
/ip service set www-ssl certificate=rest-api disabled=no address=<IP các AP>/32,...
/user group add name=lease-ro policy=read,api,rest-api
/user add name=ap-sync group=lease-ro password="..." address=<IP các AP>/32,...
```
Đặt static lease cho các AP để IP khớp danh sách `address`.

Trên mỗi AP:
```sh
umask 077; cat > /etc/lease-sync.conf <<EOC
ROUTER=192.168.2.1
USER=ap-sync
PASS=...
EOC
/etc/init.d/lease-sync restart
lease-sync once && cat /tmp/dhcp.leases   # thử một lần
```
`/etc/lease-sync.conf` được giữ qua sysupgrade. Không có file này thì service không chạy.

## Build

GitHub Actions: workflow **CR8806 AP build** (chạy tay). Hoặc trên Linux: `sh cr8806-ap/build.sh`.
Kết quả ở `bin/cr8806-ap/`.

## Flash

Từng bước chi tiết: [FLASH.md](FLASH.md). Tóm tắt: lần đầu cần UART + TFTP (hoặc SSH từ firmware
gốc Xiaomi), boot initramfs trước, ổn rồi mới ghi `factory.ubi` vào **slot không đang chạy**, giữ
slot kia làm đường lui. Đây là bản tự build, không có bảo hành.
