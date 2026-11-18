# Giải thích chi tiết: mã hoá bit ở `Tx.m` → giải mã từng bước ở `Rx.m`

Tham số dùng xuyên suốt: `Fs=48000`, `Fc=8000`, `baud_rate=1000` → `sps=Fs/baud_rate=48`
(48 mẫu/ký hiệu), `bits_per_block=10`, `num_blocks=20`, `pilot_val=1`.

## 1. `Tx.m` — mã hoá bit thành sóng âm thanh

### 1.1 Cấu trúc khung bit
- `preamble_bits`: 50 bit ngẫu nhiên **biết trước cả ở Rx** — dùng để đồng bộ khung và ước lượng CFO, không mang dữ liệu.
- `data_bits`: 20×10 = 200 bit dữ liệu thật (ngẫu nhiên, dùng để tính BER sau).
- Với mỗi block trong 20 block: chèn 1 bit pilot cố định (`=1`) vào **đầu** 10 bit data → mỗi block thành 11 bit `[pilot, b1..b10]`.
- `frame_bits` = nối 20 block đó = 220 bit.
- `tx_bits = [preamble_bits, frame_bits]` = 270 bit tổng — đây là toàn bộ chuỗi bit sẽ lên sóng.

### 1.2 Điều chế 2-PAM (BPSK lưỡng cực)
```
symbols  = 2*tx_bits - 1;        % bit 0 -> -1, bit 1 -> +1
baseband = repelem(symbols, sps); % mỗi symbol lặp thành 48 mẫu = xung vuông NRZ
```
Xung vuông giữ biên độ ±1 không đổi suốt 1 symbol-time (1 ms) — dạng xung này quyết định
bộ lọc phối hợp phía Rx phải là gì (xem 2.2).

### 1.3 Đưa lên tần số mang (passband)
```
passband = baseband .* cos(2*pi*Fc*t);   % Fc = 8000 Hz, điều chế DSB-SC
```
8 kHz nằm trong băng tần audio mà loa điện thoại / mic-in laptop truyền tốt qua cáp.

### 1.4 Đóng gói ra file `.wav`
- Thêm 0.5 s im lặng đầu/cuối (`pad`) để không mất mẫu đầu khi bấm play/record không
  khớp tuyệt đối thời điểm.
- Chuẩn hoá biên độ về `0.9 * max(|.|)` để tránh clip trên DAC điện thoại.
- `audiowrite('tx_cable.wav', ...)` — **đây chính là "bit đã mã hoá thành âm thanh"**,
  copy file này sang điện thoại và phát qua cáp headphone vào line-in/mic laptop.
- `save('tx_params.mat', ...)` lưu lại toàn bộ tham số + `data_bits`/`tx_bits` gốc, để
  `Rx.m` nạp lại và so BER được ngay cả khi mở MATLAB session mới, workspace đã mất.

## 2. `Rx.m` — giải mã từng bước

### 2.0 Thu tín hiệu
`audiorecorder(Fs,16,1)` ghi `record_time` giây qua thiết bị input thật (line-in/mic).
`rx_raw = getaudiodata(rec)`. Ghi thêm `rx_debug.wav` để soi lại nếu giải sai; in
peak/rms — gần 0 nghĩa là thu nhầm thiết bị hoặc chưa cắm cáp.

### 2.1 Hạ tần xuống baseband phức (I/Q)
```
rx_bb = rx_raw .* exp(-1j*2*pi*Fc*t);
```
Nhân với sóng mang phức liên hợp để đưa phổ tín hiệu về quanh 0 Hz.

### 2.2 Lọc phối hợp (matched filter = integrate-and-dump)
```
mf_out = conv(rx_bb, ones(sps,1)/sps, 'same');
```
Vì Tx phát xung vuông dài đúng `sps` mẫu, bộ lọc phối hợp tối ưu là trung bình trượt
độ dài `sps` — tương đương "tích luỹ rồi xả" cho từng symbol, tối đa SNR tại điểm lấy
mẫu giữa symbol.

### 2.3 Đồng bộ khung: tương quan chéo, quét CFO trước
Nếu tương quan trực tiếp với preamble mà chưa bù CFO, pha trôi dần trong lúc tương quan
trên 50 symbol (~50 ms) nên đỉnh co lại: lệch 10 Hz còn 64% đỉnh, lệch 20 Hz thì pha trôi
hết 1 vòng → đỉnh về 0; CFO thật trên cáp (≈ −22 Hz) chỉ còn ~9% → khoá nhầm dù độ tin
cậy báo cao. Giải pháp: quét lưới CFO ứng viên
`-500:15:500 Hz`, với mỗi ứng viên bù xoay pha rồi `xcorr` với bản preamble ±1 đã
upsample; chọn cặp (độ trễ, CFO thô) cho đỉnh tương quan lớn nhất.
- `start_idx` = vị trí mẫu bắt đầu preamble tìm được.
- `sync_confidence = peak/median(|c|)` — càng cao càng chắc chắn khoá đúng preamble
  (không phải nhiễu).

### 2.4 Ước lượng CFO chính xác từ độ trôi pha
Lấy đúng đoạn preamble tại `start_idx`, lấy mẫu tâm mỗi symbol, bù dấu ±1 đã biết trước
để chỉ còn lệch pha do CFO + nhiễu. Lấy **lệch pha giữa hai symbol liên tiếp**
(`diffs = sym(k+1)*conj(sym(k))`, luôn nằm trong `[-π,π]`, không cần unwrap), rồi
`avg_step = angle(mean(diffs))` — trung bình vector, bền với wraparound hơn trung bình
góc trực tiếp. `cfo_hz = avg_step / (2π·sps/Fs)`.
> Lý do không dùng `unwrap(angle(.))` rồi `polyfit` trên cả cụm 50 điểm: trên cáp thật,
> 1 mẫu nhiễu/méo đủ làm `unwrap` nhảy sai `2π`, khiến `polyfit` đọc ra một CFO giả rất
> lớn. Lấy lệch pha từng-cặp liên tiếp tránh được lỗi tích luỹ này.

### 2.5 Bù CFO cho toàn bộ phần dữ liệu
```
mf_corr = mf_out(start_idx:end) .* exp(-1j*2*pi*cfo_hz*n/Fs);
```

### 2.6 Lấy mẫu + theo dõi trôi pilot (early-late) + cân bằng zero-forcing mỗi block
Dù CFO đã bù đúng, đồng hồ lấy mẫu của DAC điện thoại và ADC laptop **không chung
tham chiếu** → số mẫu/symbol thực tế trôi dần so với `sps` danh nghĩa (đo được thực
tế ~3000 ppm, xem `bai_hoc.md`). Dùng vị trí mẫu cố định sẽ làm lỗi bit tăng dần về
cuối khung. Với mỗi block trong 20 block:
1. Vị trí pilot danh nghĩa = `data_start + (blk-1)*11*sps + timing_off` (lệch tích
   luỹ mang từ block trước).
2. Tìm lại đỉnh biên độ `|mf_corr|` thật trong cửa sổ `±search_win = sps/4` quanh vị
   trí danh nghĩa → `pilot_idx` thực tế; cập nhật `timing_off` cho block sau
   (early-late tracking đơn giản, không cần mô hình hoá tỉ lệ trôi đầy đủ).
3. `g = mf_corr(pilot_idx) / pilot_sym` — hệ số kênh ước lượng tại pilot (biên độ +
   pha còn lại do cáp/DAC/ADC).
4. Với mỗi bit trong block: lấy mẫu tâm symbol, `eq_sym = mf_corr(symbol)/g` — chia
   cho hệ số kênh vừa ước lượng = cân bằng **zero-forcing**.
5. `rx_bits(bit) = real(eq_sym) > 0` — slicer 2-PAM: dấu của phần thực quyết định
   bit 0/1.

### 2.7 Đánh giá lỗi
`[num_err, ber] = biterr(data_bits, rx_bits)` so trực tiếp với `data_bits` gốc (nạp
từ `tx_params.mat`). In thêm lỗi từng block để chẩn đoán: lỗi **tăng dần về cuối** →
trôi đồng hồ mẫu chưa bù đủ; lỗi **rải đều** → nhiễu/SNR thấp, không liên quan clock.

## Tóm tắt: bước nào giải quyết vấn đề gì

| Bước | Bù cho vấn đề |
|---|---|
| 2.1 downconvert | đưa passband về baseband để xử lý phức I/Q |
| 2.2 matched filter | tối đa SNR tại điểm lấy mẫu (khớp dạng xung Tx) |
| 2.3 sync (quét CFO + xcorr) | tìm đúng vị trí bắt đầu khung trong dòng mẫu ghi âm |
| 2.4 ước lượng CFO | bù **lệch tần số mang** (sóng mang danh nghĩa của 2 máy không khớp) |
| 2.6 pilot early-late tracking | bù **lệch đồng hồ lấy mẫu** (DAC/ADC trôi dần theo thời gian) |
| 2.6 zero-forcing (chia cho `g`) | bù **suy hao/lệch pha kênh** (cáp + loa + mic) còn lại tại mỗi block |
| 2.6 slicer | ra quyết định bit cuối cùng |

CFO dư và lệch đồng hồ mẫu là hai nguyên nhân **độc lập** (xem `bai_hoc.md` để rõ
cách phân biệt bằng thực nghiệm đổi `baud_rate`) — thiếu bù một trong hai đều không
đủ để BER về 0, dù có bù cái còn lại rất tốt.
