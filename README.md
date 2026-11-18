# Modem âm thanh BPSK / QPSK / QAM (MATLAB + Python)

Laptop sinh tín hiệu số điều chế lên sóng mang 8 kHz và ghi ra `.wav`. Điện thoại phát file đó. Laptop thu lại qua dây tai nghe (hoặc qua loa → mic) rồi giải mã về bit và đo BER/EVM.
Mục tiêu tiếp theo: gửi âm thanh thật qua kênh không dây, rồi qua kênh dưới nước bằng QAM coherent.

Mỗi script có hai bản nằm cạnh nhau: `.m` (MATLAB) và `.py` (Python, dịch từng dòng). Hai bản đọc/ghi cùng các file `.mat`/`.wav`, nên có thể phát bằng bản này và thu bằng bản kia.

## Thư mục

| Thư mục | Nội dung |
|---|---|
| `bpsk/` | `Tx`/`Rx`: BPSK (2-PAM) qua cáp, bản cơ sở |
| `qpsk/` | `Tx_qpsk`/`Rx_qpsk`: QPSK qua cáp. `Audio_qpsk`: gửi một đoạn âm thanh (8 kHz, 8 bit) rồi phát lại. `Plot_qpsk`: vẽ các bước trung gian |
| `qam/` | `Tx_qam`/`Rx_qam`: M-QAM với khung chèn 0 và bộ cân bằng miền tần số (theo bằng sáng chế FSK), có kênh đa đường mô phỏng |
| `qpsk_air/` | `Tx_qpsk_air`/`Rx_qpsk_air`: QPSK qua không khí (loa điện thoại → mic laptop), 500 baud, có mã Reed-Solomon |
| `air_wireless/`, `underwater_ofdm/` | Thử nghiệm phụ (chỉ có MATLAB) |
| `docs/` | Ứng dụng dạy học `modem-lab.html` và sơ đồ `modem-pipeline.html`. Tài liệu riêng của từng modem nằm trong `<thư mục>/docs/` |

Mỗi thư mục giữ các file sinh ra của chính nó: `tx_params*.mat` (tham số + bit đã phát) và `rx_debug*.wav` / `rx_air*.wav` (bản thu thật).

## Chạy bằng Python (uv)

```sh
uv sync                                   # một lần: tạo .venv với numpy, scipy, matplotlib, sounddevice, reedsolo
uv run qpsk/Tx_qpsk.py                    # sinh tx_cable_qpsk.wav + tx_params_qpsk.mat
uv run qpsk/Rx_qpsk.py loopback           # tự kiểm tra, BER phải = 0
uv run qpsk/Rx_qpsk.py record             # thu thật từ thiết bị thu mặc định
uv run qpsk/Rx_qpsk.py file               # giải mã lại bản thu đã lưu
uv run qpsk/Audio_qpsk.py tx qpsk/giong.wav 3
uv run qpsk/Audio_qpsk.py rx [record|loopback|file]
uv run qpsk/Plot_qpsk.py file
uv run qam/Rx_qam.py sim                  # kênh đa đường mô phỏng
uv run qpsk_air/Rx_qpsk_air.py [loopback|sim|record|file]
```

Nếu không truyền tham số, mỗi Rx dùng nguồn `RX_SOURCE` khai báo ở đầu file, giống bản `.m`. Thu nhầm thiết bị thì xem danh sách bằng `uv run python -m sounddevice`.

## Chạy bằng MATLAB

Mở script trong thư mục của nó và chọn Run → "Change Folder": các `Tx*.m` ghi file vào *thư mục hiện tại*. Nguồn thu chọn bằng biến `RX_SOURCE` ở đầu mỗi `Rx*.m`. Gửi âm thanh: `Audio_qpsk('tx', 'giong.wav', 3)` rồi `Audio_qpsk('rx')`.

## Quy trình đo thật

1. Chạy Tx, copy file `tx_*.wav` sang điện thoại.
2. Cắm dây (điện thoại → line-in/mic của laptop), hoặc đặt loa cách mic 10–30 cm với `qpsk_air`.
3. Chạy Rx với `record` rồi bấm phát trên điện thoại trong lúc đang thu.
4. Bản thu được lưu vào `rx_debug*.wav`. Sau này giải mã lại bằng `file`.

## Kết quả đã đo

| Modem | Kênh | Kết quả |
|---|---|---|
| BPSK 1000 baud | cáp | 0 / 200 bit sai, CFO ≈ −22 Hz |
| QPSK 1000 baud | cáp | 0 / 2000 bit sai, EVM ≈ 6% (bản thu hiện tại: 1 / 2000, EVM 30%) |
| QPSK audio 4000 baud | cáp | 1 s: 0 / 64000 bit sai. 3 s: 2 / 192000 bit sai, EVM 14.6% |
| QPSK 500 baud | không khí | 13–68 / 2000 bit sai (các bản thu trong `qpsk_air/truoc_fec/`). Bản thu hiện tại: 258 / 2000 bit sai, Reed-Solomon không sửa được |
| 16-QAM 1000 baud | mô phỏng 3 tia | 0–10 / 4000 bit sai |

Trên cùng các bản thu, bản Python in ra đúng các con số của bản MATLAB.

## Lỗi hay gặp

- **BER ≈ 0.5**: file `.wav` đang giải mã không đi cùng `tx_params*.mat` hiện tại. Lý do thường gặp: đã chạy lại Tx, mà mỗi lần chạy Tx sinh bit ngẫu nhiên mới và ghi đè `.mat`. Đây không phải lỗi kênh truyền.
- Chạy Tx sẽ ghi đè `tx_params*.mat`, nên bản thu cũ trong cùng thư mục không giải mã được nữa. Muốn giữ bản thu cũ thì copy cả `.wav` lẫn `.mat` ra chỗ khác trước khi chạy Tx.
- Rx ở chế độ `record` ghi đè `rx_debug*.wav`.
- Trong MATLAB, BPSK và QPSK dùng chung tên biến. Khi chuyển giữa hai modem trong cùng một phiên, chạy `clear` trước.
