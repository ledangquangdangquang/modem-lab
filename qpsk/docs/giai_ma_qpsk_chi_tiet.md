# Giải mã QPSK từng bước: từ `rx_raw` đến BER (`Rx_qpsk.m`)

Tài liệu này đi qua `Rx_qpsk.m` theo đúng thứ tự chạy, dùng **một ví dụ đồ chơi xuyên suốt**, số nhỏ để tính tay được.

## Ví dụ đồ chơi

| tham số | đồ chơi | thật (`Tx_qpsk.m` / `Audio_qpsk.m`) |
|---|---|---|
| `Fs` | 360 Hz, chọn để **1 Hz lệch tần = 1° mỗi mẫu** | 48000 |
| `Fc` | 90 Hz, sóng mang quay **90° mỗi mẫu** | 8000 |
| `sps` | 4 mẫu/ký hiệu | 48 / 12 |
| preamble | 3 ký hiệu `[+1, −1, +1]`, dài 12 mẫu | 50 ký hiệu |
| block | `[pilot, 2 ký hiệu dữ liệu]`, `spb` = 3·4 = 12 mẫu | `[pilot, 5]`, `spb` = 288 / 72 |
| số block | 3 | 200 / 6400+ |
| `pilot_sym` | 1∠45° | 1∠45° |

Dữ liệu (ánh xạ Gray: bit 1 của cặp → dấu I, bit 2 → dấu Q):

| block | pilot | dữ liệu 1 | dữ liệu 2 |
|---|---|---|---|
| 1 | 1∠45° | 1∠135° (bit 0 1) | 1∠−135° (bit 0 0) |
| 2 | 1∠45° | 1∠45° (bit 1 1) | 1∠−45° (bit 1 0) |
| 3 | 1∠45° | 1∠−45° (bit 1 0) | 1∠135° (bit 0 1) |

Kênh đồ chơi (dùng từ bước 4 trở đi): độ lợi cáp 0.8, pha sóng mang lệch **20°**, CFO **5 Hz** (tức 5° mỗi mẫu). Không nhiễu, trừ khi nói khác.

Cả khung dài 12 + 3·12 = **48 mẫu**.

### Quy tắc tính dùng trong cả file

Số phức viết dạng **biên độ∠góc**. Chỉ cần 7 quy tắc sau:

- **(N) Nhân:** nhân biên độ, cộng góc. a∠α × b∠β = (a×b)∠(α+β).
  Ví dụ: 0.707∠180° × 1∠−90° = (0.707×1)∠(180°+(−90°)) = 0.707∠90°.
- **(Đ) Số thực cũng là số phức:** số dương x = x∠0°, số âm −x = x∠180°. Góc cộng hoặc trừ 360° vẫn là góc đó (∠−270° = ∠(−270°+360°) = ∠90°).
- **(C1) Cộng hai số cùng góc:** cộng biên độ. a∠θ + b∠θ = (a+b)∠θ.
  Ví dụ: 0.707∠0° + 0.707∠0° = (0.707+0.707)∠0° = 1.414∠0°.
- **(C2) Cộng hai số cùng biên độ, ngược góc (lệch 180°):** triệt tiêu. a∠θ + a∠(θ+180°) = 0.
  Ví dụ: 0.707∠0° + 0.707∠180° = 0.
- **(C3) Cộng hai số cùng biên độ, lệch nhau 90°:** biên độ nhân 1.414 (đường chéo hình vuông, √2 ≈ 1.414), góc nằm giữa. a∠θ + a∠(θ+90°) = (a×1.414)∠(θ+45°).
  Ví dụ: 1.414∠0° + 1.414∠90° = (1.414×1.414)∠(0°+45°) = 2∠45°.
- **(C4) Cộng hai số khác biên độ, lệch nhau 90°:** Pitago. a∠θ + b∠(θ+90°) = √(a²+b²)∠(θ + arctan(b/a)).
  Ví dụ: 1.414∠0° + 0.707∠90° = √(2+0.5)∠arctan(0.5) = 1.581∠26.6°.
- **(T) Số thực cos θ = hai mũi tên nửa độ dài, góc ngược dấu:** cos θ = 0.5∠θ + 0.5∠−θ. Hai mũi tên đối xứng qua trục ngang: phần dọc triệt tiêu, phần ngang cộng lại thành cos θ.
  Ví dụ: cos 135° = −0.707 = 0.5∠135° + 0.5∠−135° (mỗi mũi tên có phần ngang 0.5 × cos 135° = −0.354; cộng lại −0.707).
- **(C5) Cộng N vectơ cùng biên độ, góc cách đều 360°/N:** triệt tiêu. a∠θ + a∠(θ+360°/N) + … = 0. N mũi tên chia đều vòng tròn, phần ngang và phần dọc của chúng cân bằng nhau.
  Ví dụ: 0.4∠50° + 0.4∠170° + 0.4∠290° = 0 (ba vectơ cách đều 120°).

---

## Bước 1: lấy `rx_raw` (dòng 26–53)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | file `.wav` (`rx_debug_qpsk.wav` qua `'record'`/`'file'`) hoặc `tx_signal` trong bộ nhớ (`'loopback'`) |
| **Output (lý thuyết — đồ chơi)** | `rx_raw` = 48 mẫu **thực** trong [−1,1]: im lặng (nếu có) + 12 mẫu preamble + 36 mẫu block. Ví dụ 4 mẫu đầu ký hiệu 1∠45°: +0.707, −0.707, −0.707, +0.707 (là cos 45°, 135°, 225°, 315° — 2b) |
| **Output (thực tế — cáp thật)** | bản thu `rx_debug_qpsk.wav` Fs = 48000: im lặng/nhiễu → 0.5 s đệm → preamble 50 ký hiệu → 200 block (khung ≈ 1.25 s) → đệm. Biên độ bị thu nhỏ bởi gain điện thoại/cáp (đồ chơi mô phỏng bằng ×0.8). Chưa biết khung bắt đầu ở mẫu nào — đó là việc của bước 4 |

`rx_raw` là một dãy số thực, mỗi mẫu là một giá trị điện áp đã chuẩn hóa về [−1, 1]. Có ba nguồn:

- `'loopback'`: `rx_raw = tx_signal`. Kênh lý tưởng, BER phải bằng 0. Dùng để kiểm tra code.
- `'record'`: thu âm thật qua cáp trong `record_time` giây, rồi lưu vào `rx_debug_qpsk.wav`.
- `'file'`: đọc lại file `.wav` đã thu. File này chỉ khớp với `tx_params_qpsk.mat` của **cùng lần chạy** `Tx_qpsk.m`.

Bản thu gồm: im lặng hoặc nhiễu → 0.5 s đệm → preamble → các block → đệm. Chưa biết khung bắt đầu ở mẫu nào; bước 4 sẽ tìm.

**Các biến "móc" cho `Audio_qpsk.m` (dòng 22, 31, 38).** `Rx_qpsk.m` đọc 4 biến nếu chúng đã có sẵn, không thì lấy mặc định của QPSK:

| biến | chạy tay `Rx_qpsk.m` (mặc định) | khi `Audio_qpsk('rx')` gọi |
|---|---|---|
| `params_file` | `tx_params_qpsk.mat` | `tx_params_audio.mat` |
| `rx_wav` | `rx_debug_qpsk.wav` | `rx_debug_audio.wav` |
| `audio_src` → `RX_SOURCE` | giá trị gõ ở dòng 27 | đối số thứ 2: `'loopback'` / `'file'`, bỏ trống thì là `'record'` |
| `record_time` | 5 s | độ dài `tx_signal` (kể cả 2 đoạn đệm 0.5 s) + 3 s; audio 1 s ra khung ≈ 10.6 s |

`Audio_qpsk.m` là một *hàm*, nên `Rx_qpsk.m` chạy trong workspace riêng của hàm đó. Vì vậy không bị lẫn biến cũ của `Tx.m`/`Rx.m`, lỗi thường làm BER ≈ 0.5.

**Nhánh `'record'`:**
- `input_device_id = -1` nghĩa là dùng thiết bị thu mặc định. Nếu máy thu nhầm mic laptop, chạy `audiodevinfo(1)` để xem ID rồi gán vào đây. Trên Linux còn cần định tuyến PulseAudio trong `~/.asoundrc` (xem README của `tx_rx_basic/`).
- Dòng in `peak`/`rms` để kiểm tra nhanh. Nếu peak ≈ 0, cáp chưa cắm hoặc đang thu nhầm thiết bị, khỏi cần giải mã.
- Bản thu luôn được ghi ra `rx_wav`, để sau này giải mã lại bằng `'file'` mà không phải thu lại.

---

## Bước 2: hạ tần, `rx_bb = rx_raw .* exp(-1j*2*pi*Fc*t)` (dòng 56–57)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | `rx_raw` (N mẫu **thực**, Fs = 360 / 48000) + `Fc` (90 / 8000 Hz) |
| **Output (lý thuyết — đồ chơi, kênh lý tưởng)** | `rx_bb` = N mẫu **phức**. Ký hiệu 1∠45° ở mẫu 1–4 cho 0.707∠0°, 0.707∠90°, 0.707∠0°, 0.707∠90° (bảng 2b). Mỗi mẫu = 0.5∠45° (ký hiệu) + 0.5∠(−45°−180°·(n−1)) (rác 2·Fc) |
| **Output (thực tế — cáp thật)** | cũng N mẫu phức; ký hiệu giờ nằm ở 0 Hz, nhưng **pha còn lẫn** pha kênh và CFO (chưa sửa ở bước này). Thành phần rác 2·Fc chỉ bị khử bởi I&D khi cửa sổ khớp khung — khi lệch đồng hồ làm cửa sổ trôi, rác lọt qua (đây là lý do `Rx_qam.m` thêm FIR lowpass trước I&D) |

### 2a. Tại sao công thức lại là $t = (n-1)/F_s$ và sóng mang quay $90^\circ$ mỗi mẫu?

1. **Tại sao lại có $(n-1)$?**
   - Về mặt vật lý, trục thời gian bắt đầu từ giây thứ 0 ($t = 0\text{ s}$).
   - Nhưng MATLAB đánh số chỉ số mảng bắt đầu từ 1 (`n = 1, 2, 3...`), không có chỉ số 0.
   - Vì vậy:
     - Mẫu thứ 1 ($n=1$): thời điểm $t = (1-1)/F_s = 0\text{ s}$.
     - Mẫu thứ 2 ($n=2$): thời điểm $t = (2-1)/F_s = 1/F_s\text{ s}$.
     - Mẫu thứ $n$: thời điểm $t = (n-1)/F_s\text{ s}$.

2. **Tại sao sóng mang quay đúng $90^\circ$ mỗi mẫu?**
   - Sóng mang có tần số $F_c = 90\text{ Hz}$ (tức 1 giây nó quay 90 vòng tròn $= 90 \times 360^\circ$).
   - Tốc độ lấy mẫu $F_s = 360\text{ Hz}$ (1 giây cắt làm 360 mẫu, khoảng cách giữa 2 mẫu liên tiếp là $\Delta t = 1/F_s = 1/360\text{ s}$).
   - Cứ sau mỗi bước nhảy 1 mẫu, sóng mang quay thêm một góc là:
     $$\Delta\theta = 360^\circ \times \frac{F_c}{F_s} = 360^\circ \times \frac{90}{360} = 90^\circ$$
   - Đến mẫu thứ $n$ (đã trôi qua $n-1$ bước nhảy), sóng mang đã tích lũy một góc quay là $90^\circ \cdot (n-1)$.
   - Dưới dạng vector phức, sóng mang tại mẫu $n$ là: $1\angle(90^\circ \cdot (n-1))$.

3. **Tx phát và Rx thu:**
   - Tx đưa ký hiệu baseband lên tần số mang $F_c = 90\text{ Hz}$ và lấy phần thực truyền lên dây cáp: `real(ký_hiệu × 1∠(90°·(n−1)))`.
   - Rx muốn kéo tần số $+90\text{ Hz}$ về lại $0\text{ Hz}$ (baseband đứng yên) thì phải quay ngược chiều lại với đúng tốc độ đó: nhân với $e^{-j 2\pi F_c t} = 1\angle(-90^\circ \cdot (n-1))$, tức là **trừ $90^\circ$ sau mỗi mẫu**.

### 2b. Tính tay chi tiết qua một ví dụ: một ký hiệu 1∠45° ở mẫu 1–4

**Code thật chỉ có một dòng** (`Tx_qpsk.m` dòng 30–31):

```matlab
t = (0:length(baseband)-1)/Fs;
passband = real(baseband .* exp(1j*2*pi*Fc*t)); % I*cos - Q*sin
```

Dòng này có **hai cách đọc**, và hai cách cho ra **cùng một số**:

- **Đọc theo biên độ∠góc (dùng trong tài liệu này):** `baseband` = ký hiệu `r∠θ` (đã `repelem` ra sps mẫu giống hệt nhau), `exp(1j*2*pi*Fc*t)` = sóng mang `1∠(90°·(n−1))`. Theo (N) nhân hai số phức ra **`r∠(θ + 90°·(n−1))`** — đó là cột "passband phức" trong bảng dưới. `real(...)` ở ngoài cùng = lấy **cos của góc**: `r·cos(θ + 90°·(n−1))` — đó là cột "truyền trên dây".
- **Đọc theo comment `I*cos − Q*sin`:** viết ký hiệu thành thẳng hàng `I + jQ` với `I = r·cosθ`, `Q = r·sinθ`, và sóng mang `cosφ + j·sinφ` (φ = 90°·(n−1)). Mở ngoặc nhân: `(I + jQ)(cosφ + j sinφ)` — phần thực còn lại `I·cosφ − Q·sinφ` (phần `j·j = −1` chuyển dấu phần sin). Hai cách giống nhau đúng công thức `cos(θ+φ) = cosθ·cosφ − sinθ·sinφ` (nhân `r` cả hai vế).

**Kiểm tra bằng số, mẫu n = 2** (φ = 90°), ký hiệu 1∠45°:

| cách tính | làm | kết quả |
|---|---|---|
| biên độ∠góc | `real(1∠(45°+90°))` = cos 135° | −0.707 |
| `I·cosφ − Q·sinφ` | I = Q = 0.707: 0.707·cos 90° − 0.707·sin 90° = 0 − 0.707 | **−0.707** ✓ |

> **Mẹo:** vì `real(...)` đứng ngoài cùng, hai cách đọc hoán chỗ được cho nhau — tài liệu này chọn đọc biên độ∠góc vì cộng/trừ góc theo (N) gọn hơn nhiều so với nhân cả số phức. Comment `I*cos − Q*sin` trong code chỉ là cách viết thẳng hàng của cùng một phép tính.

> **Dễ nhầm:** `repelem` ở Tx làm cho **baseband** có cùng góc 1∠45° ở cả 4 mẫu. Nhưng thứ đi trên dây là **passband** = baseband × sóng mang, mà sóng mang tự quay thêm 90° sau mỗi mẫu. Vì vậy trên dây mỗi mẫu có một góc khác nhau. Góc chỉ giống nhau ở baseband: trước khi Tx nhân sóng mang, và sau khi Rx trừ sóng mang rồi lấy trung bình (bước 3).

*Tx tạo `rx_raw`.* Theo (N): 1∠45° × 1∠(90°·(n−1)) = 1∠(45° + 90°·(n−1)). Bảng dưới thêm cột **passband phức** (kết quả của phép nhân, thứ Tx tính ra trong máy) để thấy rõ nó "chở" cái gì, trước khi lấy phần thực để truyền:

| n | baseband (`repelem`) | × sóng mang 1∠(90°·(n−1)) | **passband phức** (trong máy) | **truyền trên dây** `rx_raw(n)` = real = cos(góc) |
|---|---|---|---|---|
| 1 | 1∠45° | × 1∠0° | 1∠(45°+0°) = **1∠45°** | cos 45° = **+0.707** |
| 2 | 1∠45° | × 1∠90° | 1∠(45°+90°) = **1∠135°** | cos 135° = **−0.707** |
| 3 | 1∠45° | × 1∠180° | 1∠(45°+180°) = **1∠225°** | cos 225° = **−0.707** |
| 4 | 1∠45° | × 1∠270° | 1∠(45°+270°) = **1∠315°** | cos 315° = **+0.707** |

- Cột baseband không đổi (đó là `repelem`). Cột passband phức quay vòng vì sóng mang được cộng vào — **đây là thứ ký hiệu "muốn nói"** (biên độ 1, góc 45°), nhưng mũi tên này chỉ nằm trong máy.
- Cột truyền trên dây là **phần thực** của cột passband phức (xem 2c): mỗi mẫu chỉ còn **một số volt**, biên độ 1 gói gọn thành ±0.707. Rx sẽ phải dựng lại cột passband phức từ cột dây này (bước 2 + bước 3).

*Rx nhân từng mẫu.* Đổi `rx_raw` sang dạng ∠ theo (Đ), rồi nhân theo (N):

| n | `rx_raw(n)` dạng ∠ | × 1∠(−90°·(n−1)) | nhân biên độ, cộng góc | `rx_bb(n)` |
|---|---|---|---|---|
| 1 | +0.707 = 0.707∠0° | × 1∠0° | (0.707×1)∠(0°+0°) | 0.707∠0° |
| 2 | −0.707 = 0.707∠180° | × 1∠−90° | (0.707×1)∠(180°−90°) | 0.707∠90° |
| 3 | −0.707 = 0.707∠180° | × 1∠−180° | (0.707×1)∠(180°−180°) | 0.707∠0° |
| 4 | +0.707 = 0.707∠0° | × 1∠−270° | (0.707×1)∠(0°−270°) = ∠−270° = ∠90° | 0.707∠90° |

`rx_bb` nhảy qua lại giữa ∠0° và ∠90°, chưa thấy ngay 45°. Muốn thấy 45° nằm ở đâu thì **đừng nhân cả số thực `rx_raw(n)`, mà tách nó ra theo (T) trước**, rồi nhân từng mũi tên.

**Làm tay mẫu n = 2:**

1. `rx_raw(2)` = cos 135° = 0.5∠135° + 0.5∠−135°   (theo (T))
2. Nhân cả hai mũi tên với 1∠−90° (theo (N), cộng góc):
   - 0.5∠135° × 1∠−90° = 0.5∠45°
   - 0.5∠−135° × 1∠−90° = 0.5∠−225° = 0.5∠135°
3. Cộng lại theo (C3): 0.5∠45° + 0.5∠135° = 0.707∠90°. Khớp với bảng trên ✓

**Làm cả 4 mẫu như vậy:**

| n | `rx_raw(n)` tách theo (T) | × | mũi tên 1 | mũi tên 2 |
|---|---|---|---|---|
| 1 | 0.5∠45° + 0.5∠−45° | 1∠0° | 0.5∠45° | 0.5∠−45° |
| 2 | 0.5∠135° + 0.5∠−135° | 1∠−90° | 0.5∠45° | 0.5∠−225° = 0.5∠135° |
| 3 | 0.5∠225° + 0.5∠−225° | 1∠−180° | 0.5∠45° | 0.5∠−405° = 0.5∠−45° |
| 4 | 0.5∠315° + 0.5∠−315° | 1∠−270° | 0.5∠45° | 0.5∠−585° = 0.5∠135° |

- **Mũi tên 1** có góc 45° + 90°·(n−1). Rx trừ đúng 90°·(n−1) nên còn lại **0.5∠45° ở mọi mẫu**: đây là ký hiệu cần lấy.
- **Mũi tên 2** có góc −45° − 90°·(n−1), đã quay ngược chiều, Rx lại trừ thêm 90°·(n−1) nên nó quay **180° mỗi mẫu** (tần số 2·Fc): đây là phần rác, lần lượt ∠−45°, ∠135°, ∠−45°, ∠135°.

Cộng mũi tên 1 với mũi tên 2 của từng hàng (theo (C3)) ra đúng 0.707∠0°, 0.707∠90°, 0.707∠0°, 0.707∠90°, là cột `rx_bb(n)` ở bảng trên.

Bước 3 cộng 4 mẫu liền nhau: mũi tên 1 cộng thành 4 × 0.5∠45° = 2∠45° (C1); mũi tên 2 là 0.5∠−45° + 0.5∠135° hai lần, mỗi cặp lệch 180° nên bằng 0 (C2). Phần rác bị khử, chỉ còn lại 45°.

### 2c. Vì sao `rx_raw(n)` = cos(góc)? (phần thực là gì, và mất thông tin không?)

**1. "Lấy phần thực" = "lấy cos của góc".** Một số phức `r∠θ` là một mũi tên. `real(...)` (phần thật) lấy **phần nằm trên trục ngang** của mũi tên đó, tức `r·cos θ`; phần dọc (`r·sin θ`, phần Ảo) bị bỏ. Kiểm tra bằng (T): `cos θ = 0.5∠θ + 0.5∠−θ` — hai mũi tên đối xứng, phần dọc triệt tiêu, phần ngang cộng lại đúng `cos θ`, nên phần thật của `r∠θ` chính là `r·cos θ`. Áp dụng: mẫu 1 của ví dụ, `1∠45° × 1∠0° = 1∠45°` → `rx_raw(1)` = cos 45° = **+0.707** (một số volt duy nhất chạy trên dây).

**2. Vì sao bắt buộc phải lấy phần thực.** Số phức chỉ là **công cụ toán học** trong máy tính (cộng/nhân bằng (N) rất tiện). Nhưng dây cáp, loa điện thoại, DAC, file `.wav` đều chỉ mang **một điện áp thực mỗi mẫu** — không có "kênh thứ hai" cho phần Ảo. Code Tx chính là `passband = real(baseband .* exp(1j*2*pi*Fc*t))` (`Tx_qpsk.m` dòng 31): `real()` là bước "đóng gói" mũi tên phức xuống một điện áp duy nhất trước khi ghi ra file.

**3. cos(θ + 90°·(n−1)) có mất thông tin ký hiệu không? Không.** Ký hiệu QPSK cần cả biên độ `r` và góc `θ`. Sóng thực `r·cos(θ + 90°·(n−1))` vẫn chứa **đủ cả hai**: `r` là biên độ của sóng, `θ` là pha so với sóng mang. Bước 2 cho thấy mắt thu (Rx nhân `1∠(−90°·(n−1))`) **tái mở gói** được: từ `0.707∠180°` (mẫu 2) nhân mắt thu ra `0.707∠90°`, rồi I&D gom về `0.5∠45°` — mũi tên ký hiệu sống lại. cos ở Tx và mắt thu I/Q ở Rx là hai nửa của cùng một phép đóng/mở gói.

**4. Vì sao không gửi luôn cả phần Ảo (sin) trên dây thứ hai?** Gửi I trên cos và Q trên sin (2 điện áp) là **truyền baseband I/Q**, không cần sóng mang — nhưng tốn một kênh dây/loa thứ hai, và tín hiệu quanh 0 Hz không qua được đường điện thoại (bộ khuếch đại và tụ điện của cáp chặn DC và dải tần số rất thấp). Đưa cả gói lên `Fc = 8000 Hz` (trong dải nghe được 20 Hz–20 kHz của điện thoại) rồi gói vào **một** sóng thực là cách vừa tốn 1 dây, vừa lách qua được đặc tuyến tần số của kênh. Sóng mang làm "xe tải" chở ký hiệu, `real()` là thùng hàng đóng kín, và mắt thu Rx là cần cẩu mở thùng.


---

## Bước 3: lọc phối hợp, `mf_out = conv(rx_bb, ones(sps,1)/sps, 'same')` (dòng 64)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | `rx_bb` (N mẫu phức) + `sps` (4 / 48 / 12) |
| **Output (lý thuyết — đồ chơi, kênh lý tưởng)** | `mf_out` = N mẫu phức; mẫu tốt = **0.5∠45°** (3b). Với kênh đồ chơi (gain 0.8, pha 20°, CFO 5 Hz): mẫu tốt = **0.4∠(ký hiệu + 20° + 5°·(n−1))** (3d). Các mẫu không tốt lẫn ký hiệu kề (3c) |
| **Output (thực tế — cáp thật)** | mẫu tốt biên độ ≈ 0.5 × gain ≈ 0.3–0.4. Với sps = 48 cửa sổ đủ dài, rác 2·Fc khử gần hết. EVM đo được: ≈ 6% ở sps = 48, ≈ 15% ở sps = 12. Phần lớn là **nhiễu + lọc analog** của điện thoại/cáp, tạo sàn EVM ≈ 10% ở 4000 baud. **Lấy mẫu nguyên mẫu** (lệch tới ½ mẫu) chỉ góp một phần: ½/48 ≈ 1% ở sps = 48. Thử nội suy phân số trên bản audio 3 s chỉ hạ EVM từ 14.6% xuống 12.7%, và chỉ ở đoạn đồng hồ trôi |

### 3a. `conv` tính gì, từng số một

`ones(4,1)/4` = `h` = [0.25 0.25 0.25 0.25]. Phép chập (conv) của dãy `u` với `h` là:

`y(k) = u(k)×h(1) + u(k−1)×h(2) + u(k−2)×h(3) + u(k−3)×h(4)`   (mẫu không tồn tại coi là 0)

Vì mọi `h` đều bằng 0.25, nên y(k) = 0.25 × (u(k−3) + u(k−2) + u(k−1) + u(k)): **cộng 4 mẫu liền nhau rồi nhân 0.25**, tức trung bình 4 mẫu.

**Thử với số thực dễ nhìn**, `u = [1 10 100 1000 10000]` (5 mẫu). Chập đầy đủ ra 5 + 4 − 1 = 8 số:

| k | các mẫu u được cộng | tổng | × 0.25 = y(k) |
|---|---|---|---|
| 1 | u(1) | 1 | 0.25 |
| 2 | u(1)+u(2) = 1+10 | 11 | 2.75 |
| 3 | u(1)+u(2)+u(3) = 1+10+100 | 111 | 27.75 |
| 4 | u(1)+u(2)+u(3)+u(4) = 1+10+100+1000 | 1111 | 277.75 |
| 5 | u(2)+…+u(5) = 10+100+1000+10000 | 11110 | 2777.5 |
| 6 | u(3)+u(4)+u(5) = 100+1000+10000 | 11100 | 2775 |
| 7 | u(4)+u(5) = 1000+10000 | 11000 | 2750 |
| 8 | u(5) | 10000 | 2500 |

Ví dụ hàng k = 4, viết đủ từng phép nhân: 1000×0.25 + 100×0.25 + 10×0.25 + 1×0.25 = 250 + 25 + 2.5 + 0.25 = 277.75.

**`'same'` làm gì:** chập đầy đủ ra 8 số, nhưng `u` chỉ có 5 mẫu. `'same'` cắt bớt để kết quả cũng dài 5, bằng `u`. MATLAB giữ **5 số ở giữa**: bỏ 2 số đầu (y(1), y(2)) và 1 số cuối (y(8)), còn y(3), y(4), y(5), y(6), y(7).

Đánh số lại từ 1: `mf_out(1)` = y(3), `mf_out(2)` = y(4), … Tức là **`mf_out(n)` = y(n+2)**. Chép từ bảng trên xuống:

| n | `mf_out(n)` = y(n+2) | các mẫu u được cộng (lấy từ bảng trên) | viết theo n |
|---|---|---|---|
| 1 | y(3) = 27.75 | u(1), u(2), u(3) | n, n+1, n+2 (thiếu n−1 = u(0), không tồn tại) |
| 2 | y(4) = 277.75 | u(1), u(2), u(3), u(4) | **n−1, n, n+1, n+2** |
| 3 | y(5) = 2777.5 | u(2), u(3), u(4), u(5) | **n−1, n, n+1, n+2** |
| 4 | y(6) = 2775 | u(3), u(4), u(5) | n−1, n, n+1 (thiếu n+2 = u(6)) |
| 5 | y(7) = 2750 | u(4), u(5) | n−1, n (thiếu u(6), u(7)) |

Hàng n = 2 và n = 3 đủ 4 mẫu, và ở cả hai hàng đều là **n−1, n, n+1, n+2**. Hàng ở hai đầu cũng theo đúng quy luật đó, chỉ thiếu những mẫu nằm ngoài `u` (coi là 0).

Vẽ ra cho dễ thấy, cửa sổ 4 mẫu của `mf_out(n)` luôn bắt đầu ở mẫu **ngay trước** n:

```
mẫu u:      1    2    3    4    5
mf_out(2): [u1   u2   u3   u4]          ← bắt đầu ở 2−1 = 1
mf_out(3):      [u2   u3   u4   u5]     ← bắt đầu ở 3−1 = 2
```

Kết luận: **`mf_out(n)` = trung bình các mẫu n−1, n, n+1, n+2**. Tổng quát với `sps` chẵn: các mẫu `n − sps/2 + 1 … n + sps/2`. Với `sps` = 4: n − 1 … n + 2 ✓. (Đã chạy thử trong MATLAB: `conv([1 10 100 1000 10000], ones(1,4)/4, 'same')*4` ra `111 1111 11110 11100 11000`, khớp cột tổng của y(3) … y(7).)

### 3b. Áp vào `rx_bb` của ký hiệu 1∠45°

mf_out(2) = 0.25 × (rx_bb(1) + rx_bb(2) + rx_bb(3) + rx_bb(4))
= 0.25 × (0.707∠0° + 0.707∠90° + 0.707∠0° + 0.707∠90°)

- Gom hai số ∠0° theo (C1): 0.707∠0° + 0.707∠0° = 1.414∠0°
- Gom hai số ∠90° theo (C1): 0.707∠90° + 0.707∠90° = 1.414∠90°
- Cộng hai kết quả theo (C3): 1.414∠0° + 1.414∠90° = (1.414×1.414)∠45° = 2∠45°
- Nhân 0.25 (= 0.25∠0°) theo (N): (0.25×2)∠(45°+0°) = **0.5∠45°** ✓

Nhìn theo hai phần của bước 2: phần ký hiệu cộng 4 lần 0.5∠45° theo (C1) ra 2∠45°. Phần rác là 0.5∠−45°, 0.5∠135°, 0.5∠−45°, 0.5∠135°, từng cặp ngược góc nên theo (C2) ra 0. Còn lại 0.25 × 2∠45° = 0.5∠45°. Biên độ giảm một nửa không quan trọng, vì bước 7 chia cho pilot.

**Các `mf_out(n)` còn lại** (chỉ có ký hiệu A ở mẫu 1–4, mẫu ngoài coi là 0; cửa sổ là n−1 … n+2):

| n | cửa sổ | cộng từng bước | × 0.25 | |
|---|---|---|---|---|
| 1 | (0), 1, 2, 3 | 0.707∠0° + 0.707∠0° = 1.414∠0° (C1); + 0.707∠90° → (C4) 1.581∠26.6° | 0.395∠26.6° | ✗ thiếu mẫu 4 |
| **2** | **1, 2, 3, 4** | như trên → 2∠45° | **0.5∠45°** | ✓ đủ 4 mẫu của A |
| 3 | 2, 3, 4, (0) | 0.707∠90° + 0.707∠90° = 1.414∠90° (C1); + 0.707∠0° → (C4) 1.581∠63.4° | 0.395∠63.4° | ✗ thiếu mẫu 1 |
| 4 | 3, 4, (0), (0) | 0.707∠0° + 0.707∠90° → (C3) 1∠45° | 0.25∠45° | ✗ thiếu mẫu 1, 2 |

Chỉ n = 2 lấy đủ cả 4 mẫu của A, nên cho giá trị lớn nhất và đúng góc 45°. Các n khác thiếu mẫu: góc lệch (26.6°, 63.4°) hoặc biên độ nhỏ (0.25). Khi có ký hiệu B ngay sau, chỗ "(0)" sẽ là mẫu của B, xem 3c.

### 3c. Vì sao mẫu tốt là `s + sps/2 − 1`

**`s`** = chỉ số của **mẫu đầu tiên** của một ký hiệu (s = start). Ví dụ: ký hiệu A chiếm mẫu 1–4 nên s = 1; ký hiệu B chiếm mẫu 5–8 nên s = 5. "Mẫu tốt" là mẫu n mà `mf_out(n)` lấy trung bình đúng `sps` mẫu của ký hiệu đó, không lẫn ký hiệu bên cạnh.

Thêm ký hiệu thứ hai B = 1∠−135° ở mẫu 5–8. Tính như bước 2:

| n | góc Tx = −135° + 90°·(n−1) | `rx_raw(n)` | dạng ∠ | × 1∠(−90°·(n−1)) | `rx_bb(n)` |
|---|---|---|---|---|---|
| 5 | −135° + 360° = 225° | cos 225° = −0.707 | 0.707∠180° | ∠(180° − 360°) = ∠−180° | 0.707∠180° |
| 6 | −135° + 450° = 315° | cos 315° = +0.707 | 0.707∠0° | ∠(0° − 450°) = ∠−450° + 720° | 0.707∠−90° |
| 7 | −135° + 540° = 405° = 45° | cos 45° = +0.707 | 0.707∠0° | ∠(0° − 540°) = ∠−540° + 720° | 0.707∠180° |
| 8 | −135° + 630° = 495° = 135° | cos 135° = −0.707 | 0.707∠180° | ∠(180° − 630°) = ∠−450° + 360° | 0.707∠−90° |

Toàn bộ `rx_bb` (biên độ đều 0.707, chỉ ghi góc):

| mẫu n | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---|---|---|---|---|---|---|
| ký hiệu | A | A | A | A | B | B | B | B |
| góc `rx_bb(n)` | 0° | 90° | 0° | 90° | 180° | −90° | 180° | −90° |

Tính `mf_out(n)` = 0.25 × (tổng mẫu n−1 … n+2) ở từng n:

| n | cửa sổ | cộng từng bước | × 0.25 | |
|---|---|---|---|---|
| 1 | (0), 1, 2, 3 | 0 + 0.707∠0° + 0.707∠90° + 0.707∠0° → (C1) 1.414∠0° + 0.707∠90° → (C4) 1.581∠26.6° | 0.395∠26.6° | ✗ thiếu mẫu |
| **2** | **1, 2, 3, 4** (toàn A) | (C1) 1.414∠0° + 1.414∠90° → (C3) 2∠45° | **0.5∠45°** | ✓ đúng A |
| 3 | 2, 3, 4, 5 (3A + 1B) | 0.707∠90° + 0.707∠90° = 1.414∠90° (C1); 0.707∠0° + 0.707∠180° = 0 (C2) → 1.414∠90° | 0.354∠90° | ✗ lẫn B |
| 4 | 3, 4, 5, 6 (2A + 2B) | 0.707∠0° + 0.707∠180° = 0 (C2); 0.707∠90° + 0.707∠−90° = 0 (C2) → 0 | 0 | ✗ triệt tiêu hết |
| 5 | 4, 5, 6, 7 (1A + 3B) | 0.707∠90° + 0.707∠−90° = 0 (C2); 0.707∠180° + 0.707∠180° = 1.414∠180° (C1) → 1.414∠180° | 0.354∠180° | ✗ lẫn A |
| **6** | **5, 6, 7, 8** (toàn B) | (C1) 1.414∠180° + 1.414∠−90° → (C3, giữa 180° và 270° là 225°) 2∠225° = 2∠−135° | **0.5∠−135°** | ✓ đúng B |

Chỉ n = 2 và n = 6 cho đúng ký hiệu, vì chỉ ở đó cửa sổ 4 mẫu nằm gọn trong một ký hiệu. Lệch 1 mẫu là lẫn sang ký hiệu bên cạnh.

- A bắt đầu ở s = 1, mẫu tốt = 2. B bắt đầu ở s = 5, mẫu tốt = 6. Tức mẫu tốt = s + 1.
- Với sps = 4: s + 1 = s + 4/2 − 1. Tổng quát: **`s + sps/2 − 1`**. Với sps = 48 (code thật) là s + 23.
- Đây là nguồn gốc của `round(sps/2) − 1` trong `p0` (xem bước 6).

### 3d. Giá trị `mf_out` ở mẫu tốt khi có kênh

Từ đây, trong ví dụ đồ chơi, mình chỉ viết giá trị `mf_out` tại mẫu tốt. Kênh đồ chơi thêm 3 thứ, mỗi thứ dùng (N):

| nguồn | nhân thêm | tác dụng |
|---|---|---|
| trung bình 4 mẫu (3b) | × 0.5∠0° | biên độ 1 → 0.5 |
| độ lợi cáp 0.8 | × 0.8∠0° | biên độ 0.5 × 0.8 = 0.4 |
| pha sóng mang lệch 20° | × 1∠20° | góc + 20° |
| CFO 5 Hz = 5° mỗi mẫu | × 1∠(5°·(n−1)) | góc + 5° mỗi mẫu, tính từ mẫu 1 (mẫu 1 là mốc, chưa trôi) |

Gộp lại: `mf_out = 0.4∠(ký_hiệu + 20° + 5°·(n−1))`, với n đếm từ mẫu đầu preamble.

Vì sao mỗi thứ là một phép nhân:

- **Độ lợi cáp 0.8**: tín hiệu trên dây nhỏ đi, mọi mẫu `rx_raw` nhân 0.8, nên kết quả cuối cũng nhân 0.8.
- **Pha lệch 20°**: bộ tạo sóng mang của Rx không bắt đầu cùng lúc với Tx, nên mọi mẫu dư ra cùng một góc 20°.
- **CFO 5 Hz**: đồng hồ điện thoại và laptop lệch nhau, nên sóng mang tới quay 95° mỗi mẫu thay vì 90°. Rx chỉ trừ 90° mỗi mẫu, nên còn dư 5° mỗi mẫu, cộng dồn theo n: mẫu 1 dư 0°, mẫu 2 dư 5°, mẫu 6 dư 25°…

> Đây là số làm tròn để tính tay. Nếu tính chính xác (có CFO thì trong 4 mẫu của cửa sổ góc đã trôi 0°, 5°, 10°, 15°, và phần rác 2·Fc không triệt tiêu hết), ba mẫu tốt của preamble ra 0.412∠28.9°, 0.415∠227.3°, 0.411∠65.8° thay vì 0.4∠25°, 0.4∠225°, 0.4∠65°. Lệch vài độ; với sps = 48 thật thì phần rác khử tốt hơn nhiều. Các bước sau dùng số làm tròn.

Ví dụ với preamble `[+1, −1, +1]`:
- ký hiệu 1: +1 = 1∠0°, mẫu tốt n = 2 → 0.4∠(0° + 20° + 5°×1) = 0.4∠25°
- ký hiệu 2: −1 = 1∠180°, mẫu tốt n = 6 → 0.4∠(180° + 20° + 5°×5) = 0.4∠(180° + 20° + 25°) = 0.4∠225°

**Tính tay cả 4 mẫu của ký hiệu 1∠45° khi kênh thêm đủ 3 thứ** (dẫn số từ bảng trên dây của 2b — cùng một ký hiệu, cùng mẫu 1–4, giờ thêm gain 0.8 + pha lệch 20° + CFO 5 Hz):

*Trên dây* — gộp 3 thứ vào: gain 0.8 nhân biên độ; pha lệch (giữa sóng mang Tx và mắt thu Rx) +20°, và CFO làm sóng mang quay **95°/mẫu** thay vì 90°, cộng vào góc:

góc trên dây = 45° + 20° + 95°·(n−1)

| n | 2b (kênh lý tưởng) cos(45° + 90°·(n−1)) | 3d (có kênh) 0.8·cos(45° + 20° + 95°·(n−1)) |
|---|---|---|
| 1 | cos 45° = +0.707 | 0.8·cos 65° = **+0.338** |
| 2 | cos 135° = −0.707 | 0.8·cos 160° = **−0.752** |
| 3 | cos 225° = −0.707 | 0.8·cos 255° = **−0.207** |
| 4 | cos 315° = +0.707 | 0.8·cos 350° = **+0.788** |

Bốn số không còn đẹp ±0.707: CFO làm các mẫu ngồi lệch 5°, 10°, 15° so với góc "đẹp" của 2b, và biên độ bị ép 0.8.

*Hạ tần* — tách mỗi mẫu theo (T) rồi nhân mắt thu theo (N), ra **mũi tên ký hiệu + mũi tên rác** (cùng cách làm với bảng "Làm cả 4 mẫu" của 2b):

| n | 0.8·cos(góc) tách (T) | × mắt thu 1∠(−90°·(n−1)) | mũi tên ký hiệu | mũi tên rác | `rx_bb(n)` (cộng 2 mũi tên) |
|---|---|---|---|---|---|
| 1 | 0.4∠65° + 0.4∠−65° | × 1∠0° | 0.4∠65° | 0.4∠−65° | 0.338∠0° |
| 2 | 0.4∠160° + 0.4∠−160° | × 1∠−90° | 0.4∠70° | 0.4∠110° | 0.752∠90° |
| 3 | 0.4∠255° + 0.4∠−255° | × 1∠−180° | 0.4∠75° | 0.4∠−75° | 0.207∠0° |
| 4 | 0.4∠350° + 0.4∠10° | × 1∠−270° | 0.4∠80° | 0.4∠100° | 0.788∠90° |

- **Mũi tên ký hiệu**: `0.4∠(65° + 5°·(n−1))` — đúng công thức "Gộp lại" `0.4∠(45° + 20° + 5°·(n−1))`: biên độ 0.4 (0.5 của 3b × 0.8), và **quay 5° mỗi mẫu** (phần CFO dư) thay vì đứng yên như 2b.
- **Mũi tên rác**: nay quay **185° mỗi mẫu** (−95° của sóng mang tới, Rx lại trừ 90°) thay vì đúng 180° như 2b — **CFO cũng áp lên phần rác**, nên 4 mẫu không còn ngược góc trọn vẹn, (C2) không triệt tiêu hết.

*I&D ở mẫu tốt n = 2* (cửa sổ 1…4, đúng 4 mẫu của ký hiệu — xem 3c):

```
mf_out(2) = 0.25 × (0.338∠0° + 0.752∠90° + 0.207∠0° + 0.788∠90°)
          = 0.25 × (0.545∠0° + 1.540∠90°)                    (C1 gom từng cặp)
          = 0.25 × √(0.545² + 1.540²) ∠ arctan(1.540/0.545)   (C4)
          = 0.25 × 1.634∠70.5°
          = 0.408∠70.5°
```

So với số làm tròn của "Gộp lại": `0.4∠(45° + 20° + 5°×1)` = **0.4∠70°**. Lệch 0.008 biên độ và 0.5° — đúng tinh thần chú thích phía trên: số tròn dùng cho các bước sau (tính tay được), số thật lệch vài độ vì (a) 4 mũi tên ký hiệu trong cửa sổ đã trôi 65° → 80°, không còn cùng góc để (C1) đúng tuyệt đối, và (b) phần rác quay 185°/mẫu nên chỉ ≈ 0 chứ không bằng 0. Với sps = 48 thật, cả hai lỗi này nhỏ hơn nhiều.

---

## Bước 4: tìm đầu khung (dòng 74–95)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | `mf_out` (N mẫu phức) + `preamble_ref` (50 ký hiệu → 2400 mẫu) + lưới `cfo_try` (−500…500 Hz, bước 15) |
| **Output (lý thuyết — đồ chơi, 3 mẫu im lặng)** | đỉnh xcorr ở lag 3 → `start_idx = 4`, tức `mf_out(4)` là mẫu đầu preamble. Nếu CFO 30 Hz mà **không** quét lưới: đỉnh đúng triệt tiêu về ≈ 0, `max` bắt nhầm lag khác (4a) |
| **Output (thực tế — cáp thật)** | `start_idx` ≈ **mẫu đầu tiên của preamble** trên bản thu thật. Có thể lệch ±1 mẫu: với `sps` chẵn, `mf_out` của một ký hiệu là hình tam giác, nên hai vị trí cửa sổ cạnh nhau cho tổng tích bằng nhau. Các bước sau tự cộng `round(sps/2) − 1` để tới mẫu tốt. Đỉnh cao chỉ có khi quét `cfo_try`, vì CFO thật −22 ÷ −24 Hz nằm ngay trong lưới quét. `cfo_try` chọn được chỉ là ước **thô** (sai vài Hz), bước 5 tinh chỉnh |

`preamble_ref` là preamble ở dạng mẫu: `[+1 +1 +1 +1  −1 −1 −1 −1  +1 +1 +1 +1]`. `xcorr` trượt nó dọc `mf_out` và tính tổng tích ở mỗi độ trễ.

**Ví dụ: không CFO, trước preamble có 3 mẫu im lặng.** Bỏ qua phần dốc ở mép ký hiệu:

| mẫu `mf_out` | 1–3 | 4–7 | 8–11 | 12–15 |
|---|---|---|---|---|
| giá trị | 0 | +0.5 | −0.5 | +0.5 |

| lag | các mẫu `mf_out` chồng lên ref | tổng tích |
|---|---|---|
| 2 | 3…14 | 3.5 |
| **3** | **4…15** | **6.0** (12 mẫu × 0.5, khớp hết) |
| 4 | 5…16 | 3.5 |

Đỉnh ở lag 3, nên `start_idx = lags(pk) + 1 = 4`: `mf_out(4)` là mẫu đầu preamble ✓.

### 4a. Vì sao phải quét `cfo_grid`: CFO làm đỉnh thật triệt tiêu về 0

Bước 4 chọn `start_idx` bằng `[~, pk] = max(tổng tích qua các lag)`: lag nào tổng tích **to nhất** thì thắng, không có luật nào bảo vệ lag đúng. Vì vậy muốn tìm đúng, lag đúng phải to hơn tất cả lag sai — đó là điều CFO phá vỡ.

**Không CFO: 3 vectơ cùng hướng → đỉnh cao.** Kênh đồ chơi (3d) chỉ còn pha lệch 20°. Lấy mẫu tốt n = 2, 6, 10 của preamble `[+1, −1, +1]`:

| ký hiệu | mẫu tốt n | `mf_out(n)` = 0.4∠(ký hiệu+20°) | × ref | kết quả |
|---|---|---|---|---|
| 1 | 2 | 0.4∠20° | ×(+1) | 0.4∠20° |
| 2 | 6 | 0.4∠200° | ×(−1) = ×1∠180° | 0.4∠380° = 0.4∠20° |
| 3 | 10 | 0.4∠20° | ×(+1) | 0.4∠20° |

Cộng 3 lần 0.4∠20° theo (C1) → **1.2∠20°**: đỉnh cao tách bạch ở đúng lag ✓.

**CFO 30 Hz: 3 vectơ cách đều 120° → triệt tiêu về 0.** Trong đồ chơi 1 Hz = 1°/mẫu, nên CFO 30 Hz = 30° mỗi mẫu. Theo 3d, mẫu tốt ký hiệu k lệch thêm `30°·(n−1)`:

| ký hiệu | mẫu tốt n | `mf_out(n)` = 0.4∠(ký hiệu+20°+30°·(n−1)) | × ref | kết quả |
|---|---|---|---|---|
| 1 | 2 | 0.4∠(0°+20°+30°) = 0.4∠50° | ×(+1) | 0.4∠50° |
| 2 | 6 | 0.4∠(180°+20°+150°) = 0.4∠350° | ×(−1) | 0.4∠530° = 0.4∠170° |
| 3 | 10 | 0.4∠(0°+20°+270°) = 0.4∠290° | ×(+1) | 0.4∠290° |

Ba kết quả có góc **50°, 170°, 290°** — cách đều nhau đúng 120°, biên độ đều 0.4 → theo (C5) triệt tiêu. Kiểm tra số: cos 50° + cos 170° + cos 290° = 0.643 − 0.985 + 0.342 = 0; sin cũng = 0. Tổng tích ở **đúng lag ≈ 0**.

Vì sao lại cách đều 120°: hai mẫu tốt kề nhau lệch 4 mẫu → lệch `4 × 30° = 120°`; ba ký hiệu → 3 × 120° = 360°, chia trọn vòng tròn. Nhìn toàn khung cũng vậy: 12 mẫu preamble, mỗi mẫu lệch 30°, 12 × 30° = 360° — 12 vectơ quanh vòng tròn, tổng ≈ 0 (phần mép cửa sổ I&D làm còn sót vài term nhỏ, nên viết "≈ 0" chứ không phải 0 tuyệt đối).

**Lag sai có thể vượt mặt lag đúng.** Giả sử lag sai (ví dụ lệch 4 mẫu) cho các tích lệch kiểu nhau 0°, 60°, 180° thay vì cách đều:

- cos 0° + cos 60° + cos 180° = 1 + 0.5 − 1 = 0.5; sin 0° + sin 60° + sin 180° = 0 + 0.866 + 0 = 0.866 → tổng = 1.0∠60°.

| lag | các tích | tổng tích (điểm) |
|---|---|---|
| **đúng** | 50°, 170°, 290° (đều 120°) | **≈ 0** |
| sai (lệch 4 mẫu) | 0°, 60°, 180° (lệch kiểu) | **1.0∠60°** |

→ `max` chọn lag sai. **Khi lag đúng bị CFO triệt tiêu về 0, lag sai chỉ cần có chút bất đối xứng trong góc là thắng**, vì bất đối xứng nghĩa là các mũi tên không triệt tiêu hết nhau, còn sót lại phần ngang (hoặc phần dọc) — tức là có số dương để khoe. Thậm chí ngay cả khi không CFO, lag sai lệch 1 mẫu cũng có tổng tích nhỏ nhưng vẫn dương (bảng 3c: lệch 1 mẫu là 0.395 thay vì 0.5, cùng dấu); có CFO, điểm lag đúng rớt về 0, chỉ cần lag sai còn sót vài phần là đủ thắng.

**Chọn nhầm lag → BER ≈ 0.5.** Giả sử lag đúng lẽ ra là 40, code chọn 36 (lệch 4 mẫu = 1 ký hiệu): khung đọc lệch, mỗi cửa sổ I&D ở mẫu tốt giờ bắt đầu giữa ký hiệu → `mf_out` là sự pha trộn của 2 ký hiệu kế nhau (bảng 3c: lệch 1 mẫu đã ra 0.395∠26.6°, lệch thêm nữa ra 0 hoặc 0.354∠90° — không còn là ký hiệu nào cả). Pilot cũng bị lấy nhầm chỗ → bước 7 chia cho sai pilot, không sửa được vì `mf` đã là hỗn hợp 2 ký hiệu chứ không phải "ký hiệu × sai số". Ký hiệu hỗn hợp chốt về 4 điểm constellation bằng cách bừa → BER ≈ 0.5. Âm thanh thu vẫn bình thường, chỉ là không biết khung bắt đầu ở đâu.

**CFO 5 Hz (kênh đồ chơi) thì vẫn bắt được.** 3 vectơ ở 25°, 45°, 65° — lệch nhau 20°, không triệt tiêu, tổng ≈ 1.15∠45° vẫn gần 1.2 → đỉnh vẫn cao. Nhưng preamble thật dài 50 ký hiệu × 1 ms = 50 ms: CFO chỉ 20 Hz đã quay chừng một vòng (20 Hz × 50 ms = 1 chu kỳ) → 50 vectơ triệt tiêu → đỉnh biến mất. Trong thực tế đã đo CFO ≈ −21 ÷ −24 Hz, tức **nếu bỏ qua bước quét `cfo_grid`, bước 4 sẽ fail ngay trên chính bản thu thật**. (Đỉnh tụt dần trước đó: ở nửa vòng, 10 Hz × 50 ms = ½ chu kỳ, đỉnh còn 64%; ở −24 Hz chỉ còn 16%.) Ở 4000 baud (`Audio_qpsk.m`, sps = 12) preamble chỉ dài 50 × 0.25 ms = 12.5 ms, nên phải tới khoảng 80 Hz mới quay hết một vòng. Code vẫn giữ lưới quét, để cùng một code chạy được ở cả hai tốc độ và với cặp thiết bị lệch đồng hồ nhiều hơn.

**Cách sửa: xoay ngược trước khi tương quan.** Trước khi `xcorr`, code nhân `mf_out` với `1∠(−cfo_try°·(n−1))`. Nếu `cfo_try` đúng bằng CFO thật (đồ chơi: 30), nó trừ đúng 30° mỗi mẫu, kéo 3 vectơ về cùng hướng:

| ký hiệu | n | sau khi xoay theo cfo_try = 30 | × ref | kết quả |
|---|---|---|---|---|
| 1 | 2 | 0.4∠(50°−30°) = 0.4∠20° | ×(+1) | 0.4∠20° |
| 2 | 6 | 0.4∠(350°−150°) = 0.4∠200° | ×(−1) | 0.4∠20° |
| 3 | 10 | 0.4∠(290°−270°) = 0.4∠20° | ×(+1) | 0.4∠20° |

→ tổng tích **1.2∠20°**: đỉnh thật quay lại, lag đúng thắng `max` ✓. Vì CFO thật chưa biết, code thử lưới `cfo_try` từ −500 đến 500 Hz, bước 15 Hz, giữ cặp (cfo_try, lag) nào có đỉnh cao nhất. `cfo_try` chỉ cần thô: bước 5 sẽ tinh chỉnh CFO chính xác bằng độ dốc pha trên preamble.

### 4b. `sync_confidence` và kiểm tra preamble nằm trọn (dòng 89–95)

**`sync_confidence = peak_val / median(abs(c))`**: đỉnh tương quan cao gấp bao nhiêu lần mức "nền" của tương quan. Ý định là: tỉ số thấp (vài lần) thì không thật sự tìm thấy preamble.

> **Dễ nhầm: con số này thường vô nghĩa, hãy tin BER.** `xcorr(derot, preamble_ref)` đệm 0 cho `preamble_ref` (2400 mẫu) bằng dài `mf_out` (N mẫu), và trả về mọi lag từ −(N−1) đến N−1. Ở các lag ≤ −2400, `preamble_ref` nằm hẳn trước mẫu 1 của bản thu, nên tổng tích **đúng bằng 0**. Như vậy gần một nửa `c` bằng 0, và median rơi đúng vào ranh giới đó. Nếu bản ghi còn có thêm im lặng bằng 0 tuyệt đối (đoạn đệm của `tx_signal` ở loopback), thì median ≈ 0 và tỉ số nhảy lên cỡ 1e16. Con số đó không có nghĩa là "chắc chắn tuyệt đối".

**`if start_idx < 1 || start_idx + length(preamble_ref) − 1 > length(mf_out)`**: preamble tìm được phải nằm trọn trong bản thu. Nếu không, code dừng bằng `error`. Hay gặp khi bấm phát trên điện thoại quá muộn so với lúc bắt đầu ghi: đỉnh `max` khi đó rơi vào nhiễu ở mép bản thu.

---

## Bước 5: ước lượng CFO từ preamble (dòng 102–110)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | `preamble_seg` = `mf_out(start_idx … start_idx + 50·sps − 1)` (2400 mẫu) + `preamble_sym` (±1) |
| **Output (lý thuyết — đồ chơi, kênh 20° + CFO 5 Hz)** | `avg_step` = 20°/ký hiệu → **`cfo_hz` = 5 Hz** (tính tay ở 5a) |
| **Output (thực tế — cáp thật)** | `cfo_hz` ≈ **−24.35 Hz** trên bản thu QPSK 1000 baud (`rx_debug_qpsk.wav`), ≈ −21 Hz trên bản audio 3 s. Để so sánh: bản thu BPSK `rx_debug.wav` của `Rx.m` cho −22.03 Hz. Dấu âm = sóng mang thực đến **thấp hơn** `Fc` giả định; −24/8000 ≈ 0.3% — đúng tỉ lệ lệch đồng hồ điện thoại/laptop |

**`idx_c = (k-1)*sps + round(sps/2)`** lấy mẫu tốt của ký hiệu thứ k, tính trong `preamble_seg`. `preamble_seg(1)` là mẫu đầu, nên mẫu tốt là `1 + sps/2 − 1 = sps/2`. Với sps = 4 ra các chỉ số **2, 6, 10**.

**`sym_val(k) = preamble_seg(idx_c) * preamble_sym(k)`**: nhân với ±1 đã biết để bỏ dấu, tức bỏ 180° của ký hiệu −1:

| k | idx | `preamble_seg(idx)` | × `preamble_sym` | `sym_val` |
|---|---|---|---|---|
| 1 | 2 | 0.4∠(0+20+5·1) = 0.4∠25° | ×(+1) | 0.4∠25° |
| 2 | 6 | 0.4∠(180+20+5·5) = 0.4∠225° | ×(−1), tức −180° | 0.4∠45° |
| 3 | 10 | 0.4∠(0+20+5·9) = 0.4∠65° | ×(+1) | 0.4∠65° |

**`diffs = sym_val(2:end) .* conj(sym_val(1:end-1))`**: nhân với liên hợp là **trừ góc**:

- 0.4∠45° · 0.4∠−25° = 0.16∠20°
- 0.4∠65° · 0.4∠−45° = 0.16∠20°

**`avg_step = angle(mean(diffs))`** = 20° mỗi ký hiệu. Trung bình theo vectơ chứ không theo góc, để hai góc +179° và −179° không trung bình ra 0°.

**`cfo_hz = avg_step / (2*pi*sps/Fs)`**: một ký hiệu dài 4 mẫu, 20°/4 = 5°/mẫu, tức **5 Hz** ✓ (vì Fs = 360).

Code chỉ so hai ký hiệu liền nhau, không `unwrap` cả chuỗi. Lý do: trên cáp thật, chỉ một điểm méo cũng có thể làm `unwrap` nhảy sai 360°, và cả ước lượng hỏng theo.

### 5a. Tính tay chi tiết bước 5: từ 0.4∠25°, 0.4∠225°, 0.4∠65° ra 5 Hz

Bước 5 trả lời một câu hỏi duy nhất: **CFO là bao nhiêu Hz**, chính xác đến từng phần Hz (bước 4 chỉ quét lưới thô, bước 15 Hz). Ý tưởng chỉ một câu:

> CFO làm góc xoay thừa **cộng dồn theo mẫu**. So góc của **hai mẫu tốt liền nhau** — phần cộng dồn lộ ra, mọi thứ hằng số tự triệt tiêu.

Nhắc lại bài toán: mỗi góc đọc được là **tổng của 3 thứ pha trộn** (theo 3d, kênh: pha 20°, CFO 5 Hz):

| ký hiệu | ký hiệu Tx | mẫu tốt n | đọc được | = 3 thứ gộp |
|---|---|---|---|---|
| 1 | +1 = 1∠0° | 2 | 0.4∠25° | 0° + 20° + 5°×1 |
| 2 | −1 = 1∠180° | 6 | 0.4∠225° | 180° + 20° + 5°×5 |
| 3 | +1 = 1∠0° | 10 | 0.4∠65° | 0° + 20° + 5°×9 |

(a) ký hiệu 0° hoặc 180°, (b) pha kênh 20° hằng số, (c) CFO `5°·(n−1)` cộng dồn. Chỉ lấy **mẫu tốt** (n = 2, 6, 10) vì mẫu khác lẫn ký hiệu kế bên, góc méo mó (bảng 3c), so sánh vô nghĩa.

**(1) Nhân `preamble_sym(k)` → loại (a), ký hiệu ±1.** Ký hiệu do Tx gửi, ta biết nó là +1 hay −1. Nhân (−1) = 1∠180° là **trừ 180°** (theo N):

| k | đọc được | × `preamble_sym` | `sym_val` | kiểm tra: 20° + 5°·(n−1) |
|---|---|---|---|---|
| 1 | 0.4∠25° | ×(+1) | 0.4∠25° | 20° + 5°×1 = 25° ✓ |
| 2 | 0.4∠225° | ×(−1), −180° | 0.4∠45° | 20° + 5°×5 = 45° ✓ |
| 3 | 0.4∠65° | ×(+1) | 0.4∠65° | 20° + 5°×9 = 65° ✓ |

Sau bước này, ba số còn **pha kênh 20° + CFO cộng dồn**, không còn dấu ký hiệu. Nhìn `sym_val`: `25°, 45°, 65°` — cách đều nhau **20°**. CFO đã lộ, chỉ còn tách khỏi pha kênh.

**(2) `diffs = sym_val(2:end) .* conj(sym_val(1:end-1))` → loại (b), pha kênh 20°.** Nhân liên hợp là **trừ góc**:

- diff(1) = `sym_val(2) × conj(sym_val(1))` = 0.4∠45° × 0.4∠(−25°) = **0.16∠20°**
- diff(2) = 0.4∠65° × 0.4∠(−45°) = **0.16∠20°**

Vì sao pha kênh biến mất: nó là **hằng số** 20° có ở cả hai số, trong phép trừ góc tự hủy: `(+20° + CFO₂) − (+20° + CFO₁) = CFO₂ − CFO₁`. Còn lại đúng **lệch CFO giữa hai mẫu tốt cách nhau 4 mẫu** = `5°×4 = 20°` ✓. Gain 0.8 cũng không ảnh hưởng: nó làm biên độ `diffs` lớn/nhỏ đi nhưng code chỉ lấy góc qua `angle()`.

**(3) `avg_step = angle(mean(diffs))` — trung bình *vectơ*, không trung bình góc.** Với 49 cặp diffs (50 ký hiệu preamble), mỗi cặp ≈ 0.16∠20°, trung bình vẫn 0.16∠20° → `angle` = 20°.

Vì sao phải trung bình vectơ: 2 góc gần ±180° (cùng hướng, lệch 2°):

- Trung bình góc số học: `(+179° + (−179°))/2 = 0°` — **sai hoàn toàn** (đáp án đúng ≈ 180°).
- Trung bình vectơ: cos 179° + cos(−179°) ≈ −2, sin triệt tiêu → ≈ 0.32∠180° → `angle` = **180°** ✓.

`mean` còn làm noise triệt tiêu một phần: 49 mũi tên nhiễu random quanh 20°, cộng về trung tâm 20°.

**(4) Đổi đơn vị, 20°/ký hiệu → 5 Hz.** `avg_step = 20°` là lệch mỗi **ký hiệu** (mỗi cặp mẫu tốt cách nhau `sps = 4` mẫu). Mỗi mẫu: `20°/4 = 5°/mẫu`. Trong đồ chơi 1 Hz = 1°/mẫu (Fs = 360):

> **5°/mẫu = 5 Hz** ✓ — đúng CFO "gieo" vào kênh.

Công thức code là bản tổng quát (radians): `cfo_hz = avg_step / (2*pi*sps/Fs)`. Mẫu số `2π·sps/Fs` là "radian thừa mỗi Hz trong một ký hiệu": CFO Δf Hz gây thừa `2π·Δf/Fs` rad mỗi mẫu, × sps mẫu = `2π·Δf·sps/Fs` rad/ký hiệu. Kiểm tra số: 20° = 0.349 rad, `2π×4/360` = 0.0698 rad/Hz → `0.349/0.0698 = 5 Hz` ✓.

**(5) Vì sao chỉ so liền kề, không `unwrap` cả chuỗi.** Mỗi diff là một phép đo **theo modulo 360°**: miễn là bước thật < 180° thì diff = đúng bước thật ± noise, không cần biết lịch sử. Code chỉ cần **trung bình** các cặp độc lập rồi mới `angle`. Ngược lại, `unwrap` cả chuỗi 50 số: một mẫu nhiễu làm nhảy sai 360° thì **cả chuỗi phía sau lệch hết**, ước lượng hỏng theo. So liền kề + trung bình vectơ: một cặp xấu chỉ là 1 trong 49, chìm trong noise.

Tóm lại: **nhân ±1 để bỏ ký hiệu → so hiệu liên để bỏ pha kênh → trung bình vectơ để bỏ noise → chia sps, đổi đơn vị ra Hz.**

---

## Bước 6: bám CFO và vị trí pilot theo từng đoạn M block (dòng 121–158)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | `mfo` = `mf_out` cắt từ `start_idx` (mfo(1) = mẫu đầu preamble) + `p0` + `M = 10` block/đoạn + `drift` suy từ CFO |
| **Output (lý thuyết — đồ chơi, drift = 0)** | `pilot_idx` = [14, 26, 38], `cfo_blk` = [5, 5, 5] Hz, `dbest` = 0 mọi đoạn (6c: đường pha nằm ngang, độ dốc 0) |
| **Output (thực tế — cáp thật)** | `block_timing` tăng dần **4 → 179 mẫu** trên bản thu 1000 baud (≈ 3.7 ký hiệu trôi trong khung); CFO **đổi giữa khung**: ≈ −24 Hz trong 2.6 s đầu rồi ≈ 0 (khung 10.6 s) → `cfo_blk` khác nhau giữa các đoạn; bản audio 3 s: pilot timing plateau ≈ 420 mẫu |

Trên cáp thật, lệch đồng hồ **thay đổi giữa khung**. Ví dụ khung 10.6 s: CFO ≈ −24 Hz trong 2.6 s đầu, rồi ≈ 0. Vì vậy một CFO chung cho cả khung là không đủ. Code chia khung thành các đoạn M = 10 block và làm 3 việc cho mỗi đoạn.

> **Vì sao không tinh chỉnh một CFO cho cả khung?** Bản trước của code đã làm vậy: tinh chỉnh CFO trên K = 20 → 80 → … pilot đầu, rồi suy drift từ CFO đó cho cả khung. Trên bản thu 10.6 s, khi đồng hồ đổi tỉ lệ giữa khung, ước lượng bị kéo từ −25 Hz lên tận −48 Hz. Vị trí pilot đoán sai cả ký hiệu và **BER = 0.499**. Chia đoạn thì mỗi ước lượng chỉ phải đúng trong 10 block (≈ 15–60 ms). Đoạn sau lấy CFO của đoạn trước làm điểm xuất phát nhưng tự đo lại độ dốc pha. Vị trí lệch thì được `dbest` của đoạn sau kéo về, nên sai số không cộng dồn qua cả khung.

`mfo = mf_out(start_idx:end)` cắt bỏ phần trước preamble, nên `mfo(1)` là mẫu đầu preamble.

### 6a. Vị trí pilot đầu tiên, `p0`

- `data_start = 12 + 1 = 13` là mẫu đầu của pilot block 1.
- `p0 = 13 + round(4/2) − 1 = 14` là mẫu tốt của pilot đó.

(Chi tiết `−1` xem bước 3.)

### 6b. Đoán vị trí m pilot, `p = p0 + (0:m-1)'*spb*(1+drift)`

- Nếu `drift = 0`: `p = [14; 26; 38]`, các pilot cách nhau 12 mẫu.
- `drift = −cfo/(Fc+cfo)` là tỉ lệ lệch đồng hồ lấy mẫu, suy ra từ CFO. Hai đại lượng này cùng sinh ra từ một độ lệch đồng hồ.
- **Trong đồ chơi, coi `drift` = 0.** Fc = 90 Hz nhỏ quá nên số drift sẽ vô lý. Với số thật, drift ≈ 0.3%, qua 10 block × 72 mẫu tích lũy ≈ 2.2 mẫu, nên bắt buộc phải bù.
- `min(..., L)` chặn để không vượt cuối bản thu.

**Kiểm tra công thức `drift` bằng số thật** (bản thu QPSK 1000 baud, sps = 48, `spb` = 288):

| đại lượng | tính | kết quả |
|---|---|---|
| CFO đo được | | −24 Hz |
| `drift = −cfo/(Fc+cfo)` | −(−24) / (8000 − 24) = 24/7976 | **+0.30%** |
| độ dài phần dữ liệu | 200 block × 288 mẫu | 57600 mẫu |
| pilot cuối trôi so với danh nghĩa | 57600 × 0.0030 | **≈ 173 mẫu** |
| `block_timing` in ra | từ 4 lên 179 | trôi **175 mẫu** ✓ |

Dấu cũng khớp: CFO âm (sóng mang tới thấp hơn `Fc`, tức đồng hồ điện thoại chậm hơn laptop) cho `drift` dương. Mỗi block thật dài hơn danh nghĩa, nên pilot đến **muộn dần** và `block_timing` tăng.

### 6c. Tinh chỉnh CFO bằng độ dốc pha pilot (chạy 2 vòng)

Tại các vị trí `p`, xoay ngược CFO hiện tại rồi chia `pilot_sym`:

| p | `mfo(p)` | xoay ngược 5°·(p−1) | / 1∠45° | `ph` |
|---|---|---|---|---|
| 14 | 0.4∠(45+20+65) = 0.4∠130° | −65° | 0.4∠20° | 20° |
| 26 | 0.4∠(45+20+125) = 0.4∠190° | −125° | 0.4∠20° | 20° |
| 38 | 0.4∠(45+20+185) = 0.4∠250° | −185° | 0.4∠20° | 20° |

`polyfit` qua 3 điểm (0, 20°), (12, 20°), (24, 20°) cho đường nằm ngang, độ dốc 0. CFO 5 Hz đã đúng, không phải chỉnh.

**Nếu CFO hiện tại chỉ là 4 Hz** (thiếu 1 Hz), xoay ngược chỉ trừ 4°·(p−1), nên còn dư 1°·(p−1):

| p | `mfo(p)` | xoay ngược 4°·(p−1) | / 1∠45° | `ph` |
|---|---|---|---|---|
| 14 | 0.4∠130° | −52° → 0.4∠78° | 0.4∠33° | 33° |
| 26 | 0.4∠190° | −100° → 0.4∠90° | 0.4∠45° | 45° |
| 38 | 0.4∠250° | −148° → 0.4∠102° | 0.4∠57° | 57° |

`polyfit` qua (0, 33°), (12, 45°), (24, 57°) cho độ dốc `pf(1)` = 12°/12 mẫu = **1°/mẫu**. Code cộng `pf(1)·Fs/(2π)` vào CFO; trong đồ chơi 1°/mẫu = 1 Hz, nên CFO thành 4 + 1 = **5 Hz** ✓. Đường thẳng ở đây là **pha theo số mẫu**, và độ dốc của nó chính là CFO còn dư. Hệ số chặn `pf(2)` = 33° là pha kênh + pha CFO tích lũy tới pilot đầu đoạn; code bỏ qua nó, vì bước 7 chia cho `g` của từng block.

**Vì sao chạy 2 vòng (`for it = 1:2`).** Vị trí đoán `p` phụ thuộc `drift`, mà `drift` lại tính từ `cfo_hz`. Vòng 1 sửa CFO, nên `drift` đổi và `p` dời đi một chút. Vòng 2 đo lại pha ở vị trí `p` mới và sửa nốt phần CFO dư. Với ±0.3% thì sau 2 vòng đã ổn định. Trong đồ chơi `drift` = 0, nên vòng 2 cho độ dốc 0.

**`if m >= 3`.** Đoạn cuối khung có thể chỉ còn 1–2 block (khi `num_blocks` không chia hết cho M). Hai điểm thì luôn nằm trên một đường thẳng, nhiễu ở pilot nào cũng thành độ dốc, nên code giữ nguyên CFO của đoạn trước.

**Vì sao ở đây dùng `unwrap` được, còn bước 5 thì tránh?** Ở đây pha đã được xoay ngược bằng CFO gần đúng. Phần còn dư nhỏ: dư 1 Hz × 10 block × 288 mẫu / 48000 = 0.06 vòng ≈ 22° cho cả đoạn, nên hai pilot liền nhau (cách 2.2°) không bao giờ lệch tới ±180° và `unwrap` không có gì để nhảy sai. Nếu có nhảy, chuỗi pha chỉ dài 10 điểm và độ dốc sai chỉ áp lên đoạn đó. Ở bước 5, pha preamble **chưa** được xoay ngược CFO nào, và chuỗi dài 50 điểm. Một mẫu méo ở đó làm `unwrap` nhảy sai 360° thì cả phần sau lệch theo (5a, mục 5), nên code dùng hiệu liền kề + trung bình vectơ.

### 6d. Chọn lệch vị trí ±2 mẫu theo độ đồng pha

Code thử dịch cả đoạn `dd` ∈ {0, −1, +1, −2, +2} mẫu. Với mỗi `dd` nó tính:

`coh = |tổng các z| / tổng các |z|`

trong đó z là giá trị pilot sau khi xoay ngược CFO. Nếu mọi pilot cùng pha thì `coh` = 1. Nếu lấy mẫu lệch sang ký hiệu bên cạnh thì các pilot bị kéo lệch mỗi cái một kiểu và `coh` < 1.

Độ lợi 0.4 và pha chung 20° không làm đổi `coh`, nên tính với biên độ 1:

| | block 1 (ký hiệu sau = 1∠135°) | block 2 (sau = 1∠45°) | block 3 (sau = 1∠−45°) | \|tổng\| | tổng \|z\| | **coh** |
|---|---|---|---|---|---|---|
| dd = 0 | 1∠45° | 1∠45° | 1∠45° | 3.0 | 3.0 | **1.000** |
| dd = +1 (3 mẫu pilot + 1 mẫu ký hiệu sau) | 0.79∠63.4° | 1∠45° | 0.79∠26.6° | 2.50 | 2.58 | **0.969** |

→ chọn `dd = 0`.

Ở **block 2**, lệch +1 mẫu vẫn cho đúng 1∠45°, vì ký hiệu sau trùng pilot. Nhìn riêng một block thì không phân biệt được lệch hay không. Đó là lý do code không dùng `max|mf|` từng block mà lấy độ đồng pha của cả đoạn.

**Lệch về phía trước, `dd = −1`** (1 mẫu của ký hiệu *trước* + 3 mẫu pilot). Ký hiệu trước pilot block 1 là ký hiệu cuối preamble, +1 = 1∠0°; trước block 2 là 1∠−135°; trước block 3 là 1∠−45°:

| | block 1 (trước = 1∠0°) | block 2 (trước = 1∠−135°) | block 3 (trước = 1∠−45°) | \|tổng\| | tổng \|z\| | **coh** |
|---|---|---|---|---|---|---|
| dd = −1 | (3∠45° + 1∠0°)/4 = 0.943∠34.2° | (3∠45° + 1∠−135°)/4 = 0.5∠45° | (3∠45° + 1∠−45°)/4 = 0.79∠26.6° | 2.22 | 2.23 | **0.993** |

Ở block 2, ký hiệu trước **ngược hẳn** pilot (lệch 180°), nên theo (C2) nó chỉ trừ bớt biên độ (1 → 0.5) mà **không làm lệch pha**. Đây thêm một kiểu "nhìn một block không thấy lệch". `coh` = 0.993 sát 1 hơn `dd = +1`, vì lần này hai block lệch pha cùng một phía (34°, 27°), ít tản hơn. Nhưng vẫn < 1, nên `dd = 0` thắng. Càng nhiều block trong đoạn (M = 10 ở code thật), dữ liệu ngẫu nhiên càng làm các pha lệch tản ra, và khoảng cách giữa `coh` của vị trí đúng và vị trí sai càng rõ.

### 6e. Sang đoạn sau

`p0 = p0 + m*spb*(1+drift) + dbest` dời tới pilot đầu của đoạn kế tiếp. Nó giữ phần lẻ (số thực) và mang theo phần chỉnh `dbest`.

Kết quả của bước 6: `pilot_idx` (vị trí mẫu pilot từng block) và `cfo_blk` (CFO từng block).

---

## Bước 7: cân bằng bằng pilot và quyết định bit (dòng 163–187)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | `mfo(idx_c)` từng ký hiệu dữ liệu + `g` = `mfo(p)/pilot_sym` + `cb` = `cfo_blk` của đoạn |
| **Output (lý thuyết — đồ chơi, block 1)** | `g` = 0.4∠85°; `eq_sym` = **1∠135°** và **1∠−135°** → bit `0 1`, `0 0` (bảng ở bước 7) |
| **Output (thực tế — cáp thật)** | `eq_sym` rơi gần đúng 4 điểm constellation, độ tản ≈ 6% RMS (1000 baud) hoặc ≈ 15% (4000 baud, sps = 12). BER: **0/2000** (1000 baud), **0/64000** (audio 1 s), **2/192000** (audio 3 s, EVM 14.6%) |

Xét **block 1** trong đồ chơi, `p = 14`, `cb = 5 Hz`.

**`g = mfo(p) / pilot_sym`** = 0.4∠130° / 1∠45° = **0.4∠85°**. Đây là "hệ số kênh" tại pilot: gồm độ lợi 0.4, pha kênh 20°, và pha CFO tích lũy tới mẫu 14 (65°).

Với từng ký hiệu dữ liệu b = 1, 2:

- **`idx_c = p + b*sps + round(drift*b*sps)`**: ký hiệu thứ b nằm sau pilot `b·sps` mẫu. Phần drift ≈ 0 trong đồ chơi. Với số thật, ở 4000 baud (sps = 12) ký hiệu xa nhất là b = 5, tức 60 mẫu sau pilot: 0.3% × 60 ≈ 0.18, làm tròn về 0. Nhưng ở 1000 baud (sps = 48) thì 0.3% × 5 × 48 = 0.72, `round` ra **1 mẫu**. Tức ký hiệu thứ 5 của mỗi block được lấy mẫu muộn hơn 1 mẫu so với `p + 5·sps`. `min(..., L)` chặn để không vượt cuối bản thu.
- **`eq_sym = mfo(idx_c) * exp(-1j*2*pi*cb*(idx_c-p)/Fs) / g`**: xoay ngược phần CFO **từ pilot tới ký hiệu này**, rồi chia g.

| b | idx_c | `mfo(idx_c)` | xoay ngược 5°·(idx_c−14) | / 0.4∠85° | bit (I>0, Q>0) |
|---|---|---|---|---|---|
| 1 | 18 | 0.4∠(135+20+85) = 0.4∠240° | −20° → 0.4∠220° | **1∠135°** ✓ | 0 1 ✓ |
| 2 | 22 | 0.4∠(−135+20+105) = 0.4∠−10° | −40° → 0.4∠−50° | **1∠−135°** ✓ | 0 0 ✓ |

Phép chia cho g vừa đưa biên độ về 1, vừa xóa mọi pha chung (pha kênh 20° và pha CFO tới pilot). QPSK cần điều này vì bit nằm trong pha. Quyết định bit rất đơn giản: `real > 0` cho bit 1 của cặp, `imag > 0` cho bit 2.

`block_timing` chỉ dùng để in: vị trí pilot tìm được trừ vị trí danh nghĩa khi không lệch đồng hồ. Trên cáp thật con số này tăng dần (ví dụ 4 → 179 mẫu), cho thấy trực tiếp đồng hồ đang trôi.

---

## Bước 8: đánh giá (dòng 195–218)

**Input → Output** của bước này:

| | |
|---|---|
| **Input** | `rx_bits` (bit chốt) + `data_bits` (bit gốc từ `.mat`) + `eq_all` (tất cả ký hiệu đã cân bằng) + `ideal` (4 điểm QPSK chuẩn) |
| **Output (lý thuyết — đồ chơi)** | **BER = 0/12**; EVM ≈ 0%. Ví dụ có nhiễu (mục 8): một điểm lệch 0.130 → EVM ≈ 9.2% |
| **Output (thực tế — cáp thật)** | in ra BER, EVM, `block_timing`: 1000 baud → BER 0/2000, EVM 6.2%; audio 1 s → 0/64000; audio 3 s → 2/192000, EVM 14.6%; loopback → BER 0, EVM ≈ 0%. Pattern `block_err` phân biệt lỗi nhiễu (rải đều) vs lỗi lệch đồng hồ (tăng về cuối) |

**`biterr(data_bits, rx_bits)`** đếm số bit sai so với bit gốc trong `.mat`. Đồ chơi: 0/12.

**BER = 0 không có nghĩa là BER thật bằng 0.** Nó chỉ nói BER thật nhỏ hơn khoảng **3 / số bit** (quy tắc "3 trên n", độ tin cậy 95%):

| lần chạy | số bit | BER = 0 chỉ nói được |
|---|---|---|
| đồ chơi | 12 | BER < 0.25 (gần như không nói gì) |
| `Tx_qpsk.m` 200 block | 2000 | BER < 1.5·10⁻³ |
| audio 1 s | 64000 | BER < 4.7·10⁻⁵ |

Vì thế bản audio 3 s ra 2/192000 (≈ 1·10⁻⁵) không mâu thuẫn với hai bản 1 s ra 0/64000: với BER ≈ 1·10⁻⁵, trung bình cứ 64000 bit mới sai 0.6 bit.

**EVM** đo độ tản của chòm sao. Mỗi điểm được so với điểm QPSK gần nhất. Ví dụ, thêm nhiễu làm điểm thứ hai lệch:

| `eq_all` | `ideal` | \|sai lệch\| |
|---|---|---|
| 1∠135° | 1∠135° | 0 |
| 0.9∠50° | 1∠45° | 0.130 |

\|sai lệch\| của hàng 2 tính bằng định lý cos (hai mũi tên dài 0.9 và 1, kẹp góc 5°): √(0.9² + 1² − 2·0.9·1·cos 5°) = √(1.81 − 1.793) = √0.0169 = **0.130**.

EVM = rms(0, 0.130) / rms(1, 1) = √(0.130²/2) = **9.2%**, tức SNR ≈ −20·log10(0.092) ≈ **20.7 dB**.

EVM có ích hơn BER khi BER = 0: nó cho biết còn cách ngưỡng lỗi bao xa. Số thật: loopback ≈ 0%, cáp ở 1000 baud ≈ 6%, ở 4000 baud ≈ 15%.

> **Dễ nhầm:** `ideal = (sign(real) + j·sign(imag))/√2` là điểm chòm sao **gần nhất**, không phải điểm Tx đã gửi. Một ký hiệu bị nhiễu đẩy qua trục (bit sai) được so với điểm *sai* gần nó, nên sai lệch tính ra nhỏ hơn thật. Ví dụ: gửi 1∠45° nhận 0.3∠−10° thì `ideal` = 1∠−45°. Vì vậy khi có nhiều bit sai, EVM in ra đánh giá thấp độ tản thật. Khi BER ≈ 0 (trường hợp thường gặp ở đây) thì không ảnh hưởng.

**In kết quả theo độ dài khung.** Khung ≤ 300 block (`Tx_qpsk.m`, 200 block): code in `block_timing` và `block_err` của **từng block**. Khung dài hơn (audio 6400 / 19200 block): chỉ in `block_timing` ở đầu / giữa / cuối, và số block có lỗi kèm block lỗi đầu tiên.

**`block_err`** là số bit sai trong từng block:
- lỗi rải đều các block → do nhiễu;
- lỗi tăng dần về cuối khung → do lệch đồng hồ chưa bù được.

---

## Đồ thị (dòng 221–223)

Code vẽ 2 hình. Cách đọc:

**`scatterplot(eq_all)`**: chòm sao các ký hiệu dữ liệu sau cân bằng.

| thấy gì | nghĩa là |
|---|---|
| 4 cụm gọn ở 1∠45°, 1∠135°, 1∠−135°, 1∠−45° | tốt. Độ rộng mỗi cụm chính là EVM |
| 4 cụm gọn nhưng **xoay** lệch khỏi 45° | còn pha chưa sửa. Khó gặp, vì chia `g` đã xóa pha chung từng block |
| mỗi cụm kéo thành **cung tròn** | CFO dư: ký hiệu càng xa pilot trong block càng xoay nhiều |
| cụm **nhòe** về phía gốc tọa độ / lẫn sang cụm bên | lấy mẫu lệch sang ký hiệu kề (timing sai, xem bảng 3c) |
| một đám tròn không có cụm | mất đồng bộ (bước 4) hoặc ghép nhầm `.mat` với `.wav` → BER ≈ 0.5 |

**`plot(real(rx_bb))`**: thành phần I của baseband theo mẫu, **trước** lọc phối hợp. Dùng để nhìn bằng mắt: đoạn im lặng ở đầu/cuối, chỗ khung bắt đầu, biên độ thu có đủ lớn không. Không dùng để đọc ký hiệu, vì rác 2·Fc (bước 2) còn nguyên trong hình.

---

## Tóm tắt chuỗi

```
rx_raw (thực, Fs)
 └─ × 1∠(−2π·Fc·t)          → rx_bb     ký hiệu ở 0 Hz + rác ở 2Fc
    └─ trung bình sps mẫu   → mf_out    rác bị khử; mẫu tốt = đầu ký hiệu + sps/2 − 1
       └─ xcorr + quét CFO  → start_idx đầu preamble
          └─ pha preamble   → cfo_hz    (bước giữa 2 ký hiệu liền nhau)
             └─ mỗi đoạn 10 block: đoán p, chỉnh CFO (độ dốc pha pilot), chọn ±2 mẫu (coh)
                                → pilot_idx, cfo_blk
                └─ mỗi block: g = pilot/pilot_sym; ký hiệu = mf·(xoay ngược CFO)/g → dấu I, Q → bit
                   └─ BER, EVM, lỗi từng block
```
