# QPSK qua không khí (loa điện thoại → mic laptop)

Thư mục này truyền QPSK bằng âm thanh qua không khí, không dùng cáp tai nghe.

- `Tx_qpsk_air.m` — sinh khung, ghi `tx_air_qpsk.wav` + `tx_params_qpsk_air.mat`.
- `Rx_qpsk_air.m` — thu bằng mic laptop (ghi lại vào `rx_air_qpsk.wav`), giải mã, in BER / EVM.

## Vì sao không dùng lại `qpsk/Rx_qpsk.m`

Qua cáp chỉ có một đường truyền. Qua không khí, mic nhận tia trực tiếp cộng với các bản
trễ của nó: phản xạ từ mặt bàn (trễ dưới 1 ms) và tiếng vang của phòng (kéo dài hàng trăm ms).
Ký hiệu trước chồng lên ký hiệu sau. `Rx_qpsk.m` chỉ chia mỗi block cho **một** hệ số phức
lấy từ pilot, nên sửa được biên độ và pha chung nhưng không gỡ được phần chồng lấn đó.

Hai file ở đây là bản sao của `qam/Tx_qam.m` / `qam/Rx_qam.m` với `M_qam = 4` (4-QAM chính là
QPSK). Khung có tiêu đề đã biết và các đoạn 0 bảo vệ; Rx ước lượng cả đáp ứng kênh `H` từ
tiêu đề rồi cân bằng trong miền tần số, nên gỡ được các tia trễ ngắn hơn đoạn 0.

Mô phỏng trên một căn phòng **tự đặt** (không phải đo thật), 2000 bit, lệch đồng hồ 0.3%, SNR 15 dB:

| Tia trực tiếp / vang | `Rx_qpsk.m` 1000 baud | `Rx_qpsk.m` 500 baud | Cân bằng miền tần số 1000 baud | Cân bằng miền tần số 500 baud |
|---|---|---|---|---|
| 20 dB | 101 bit sai | 0 | 0 | 0 |
| 10 dB | 152 | 40 | 6 | 0 |
| 5 dB | 318 | 98 | 78 | 20 |

Vì vậy mặc định ở đây là 500 baud.

## Khác gì so với `qam/`

| | `qam/` | `qpsk_air/` |
|---|---|---|
| `M_qam` | 16 | 4 (QPSK) |
| `baud_rate` | 1000 | 500 (ký hiệu 2 ms, đoạn 0 dài 16 ms) |
| khoảng lặng đầu/cuối | 0.5 s | 1.5 s |
| `RX_SOURCE` mặc định | `'sim'` | `'record'` |
| kênh `'sim'` | 3 tia rời | tia trực tiếp + phản xạ bàn + đuôi vang |
| file | `tx_cable_qam.wav`, `rx_debug_qam.wav` | `tx_air_qpsk.wav`, `rx_air_qpsk.wav` |

Thuật toán thu (bước 2–7) giữ nguyên.

## Cách chạy

1. Trong MATLAB: `cd qpsk_air`, chạy `Tx_qpsk_air.m`. Khung 2000 bit dài khoảng 4.4 s, file phát dài 7.4 s.
2. Chép `tx_air_qpsk.wav` sang điện thoại.
3. Kiểm tra trước, không cần điện thoại: đổi `RX_SOURCE` trong `Rx_qpsk_air.m` thành
   `'loopback'` (phải ra BER = 0), rồi `'sim'`.
4. Thu thật: đặt `RX_SOURCE = 'record'`, rút cáp tai nghe, để loa điện thoại cách mic laptop
   10–30 cm. Chạy `Rx_qpsk_air.m`, thấy dòng "Bat dau phat…" thì bấm phát trên điện thoại.
5. Muốn giải mã lại bản vừa thu mà không thu lại: `RX_SOURCE = 'file'`.

Lưu ý: chạy lại `Tx_qpsk_air.m` sẽ sinh bit mới. Bản thu `rx_air_qpsk.wav` cũ khi đó không còn
khớp với `.mat` → BER ≈ 0.5, không phải lỗi kênh.

## Đọc kết quả và xử lý khi lỗi

- **`peak` gần 0**: thu nhầm thiết bị, hoặc loa quá xa. Xem `audiodevinfo(1)`, chọn mic trong
  cài đặt âm thanh của hệ điều hành.
- **`peak` ≈ 1**: bị cắt đỉnh, giảm âm lượng điện thoại.
- **BER ≈ 0.5**: không khoá được khung (hoặc `.wav` và `.mat` không cùng một lần chạy Tx).
- **BER nhỏ nhưng khác 0, EVM cao**: đưa loa lại gần mic, kê điện thoại lên vật mềm để giảm
  phản xạ mặt bàn, giảm `baud_rate` (250), hoặc tăng `Lz`.
- Tắt khử ồn / khử vang / tự chỉnh âm lượng của mic nếu hệ điều hành có bật: chúng làm méo tín hiệu.
- Hình "Dap ung kenh uoc luong" cho thấy các tia trễ. Nếu còn cột cao ở gần cuối trục (gần `Lz`)
  thì vang dài hơn đoạn 0 → tăng `Lz`.

## Giới hạn hiện tại

- Mới có một bản thu thật (xem mục dưới); các bảng số ở trên là mô phỏng.
- Tốc độ thực khoảng 470 bit/s (500 baud × 2 bit × 47% khung là dữ liệu). 1 s âm thanh 8 kHz/8 bit
  (64000 bit) sẽ cần khung dài hơn 2 phút, nên chưa nối với `Audio_qpsk.m`.
- Đầu thu và phát phải đứng yên (chưa xử lý Doppler).

## Bản thu thật đầu tiên (16/11/2026)

`rx_air_qpsk.wav`: tín hiệu 8 kHz mạnh hơn nền khoảng 54 dB, 0.05% mẫu chạm đỉnh, CFO ≈ 0 Hz
(không phải −24 Hz như qua cáp), độ trễ không trôi.

- **Lần giải mã đầu: 1019 / 2000 bit sai.** Nguyên nhân là bước đồng bộ, không phải kênh: lưới quét
  CFO bước 15 Hz (chép từ bản cáp, preamble 50 ms) quá thô cho preamble 100 ms ở 500 baud, nên
  tương quan tại CFO thật bị mất gần hết và Rx khoá vào giữa khung.
- **Sau khi sửa** (bước lưới = `baud_rate / (4 × số ký hiệu preamble)` = 2.5 Hz, CFO thô lấy luôn từ
  điểm lưới thắng): khoá đúng 2.505 s, **68 / 2000 bit sai, EVM 49.7%**.
- **Phần lỗi còn lại nằm trong bản thu.** Khớp một bộ lọc tuyến tính giữa tín hiệu phát đã biết và
  bản thu chỉ giải thích được khoảng 85–90% năng lượng (phần dư −7 đến −10 dB), dù cửa sổ khớp ngắn
  50 ms hay dài 4 s, bộ lọc 4 ms hay 400 ms. Đã loại trừ: nhiễu nền, cắt đỉnh ở mic, rơi mẫu, lệch
  đồng hồ, ảnh gương phổ. Chưa xác định được nguyên nhân; nghi nhất là loa điện thoại méo khi mở to
  hoặc mic laptop có khử ồn. Kênh có hai tia cách nhau khoảng 1.3 ms, độ mạnh thay đổi trong vài
  trăm ms.

Thử tiếp: giảm âm lượng điện thoại xuống khoảng một nửa (`peak` nên ở 0.2–0.5), đặt điện thoại nằm
yên thay vì cầm tay, tắt khử ồn của mic, rồi thu lại và so EVM.

## Bản thu thật thứ hai (16/11/2026, mức thu giảm một nửa)

`peak` 0.50, tín hiệu mạnh hơn nền khoảng 45 dB, khung bắt đầu tại 2.654 s, CFO ≈ 0 Hz, timing lệch
không quá 4 mẫu cả khung. **13 / 2000 bit sai (BER 0.65%), EVM in ra 49.6%.**

- EVM in ra bị đội lên vì biên độ: ký hiệu dữ liệu sau cân bằng lớn hơn điểm lý tưởng 1.2 lần (chưa
  rõ vì sao hệ số lấy từ pilot lại nhỏ hơn). Chia hệ số đó ra thì độ tản thật là 38% (SNR ký hiệu
  8.4 dB). Với QPSK việc lệch biên độ không ảnh hưởng quyết định bit; với 16-QAM thì có.
- Giảm mức một nửa không làm EVM đổi so với bản thu đầu, nên phần méo không do mic bị quá tải.

## Bản thu 18:19 và 18:25 (16/11/2026)

- **18:19 — 500 / 2000 bit sai.** Khoá đúng khung (3.102 s) nhưng kênh không có tia chính: 4 hệ số
  gần bằng nhau trải 6–8 ms. Bản thu này đã bị ghi đè.
- **18:25 — 124 / 2000 bit sai, EVM 54%.** Kênh sạch (một hệ số 0.030, còn lại ≤ 0.006), CFO ≈ 0,
  timing lệch 8 mẫu cả khung, tín hiệu hơn nền 43 dB. Hai điều đo được:
  - Trong đoạn 0 (16 ms im lặng ở Tx) biên độ thu vẫn bằng 48% lúc có dữ liệu và không giảm dần
    → tiếng vang của phòng dài hơn đoạn 0 rất nhiều, bộ cân bằng coi nó như nhiễu. Mô phỏng vang
    8 dB cho tỷ lệ 30%, nên phòng thật vang mạnh hơn thế.
  - EVM tăng dần trong mỗi block: 42% ngay sau tiêu đề → 80% ở cuối block (120 ms sau). Mô phỏng
    vang tĩnh chỉ tăng 26 → 36%, nên kênh thật còn thay đổi trong vòng một block.

Hướng sửa chưa làm: block dữ liệu ngắn hơn (giảm `n_sub`) để ước lượng kênh mới hơn, và giảm
`baud_rate` để mỗi ký hiệu lấy trung bình được nhiều vang hơn. Cả hai đều phải sinh lại file phát.
