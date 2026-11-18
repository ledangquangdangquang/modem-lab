# Bài học rút ra: bản QPSK (`Tx_qpsk.m` / `Rx_qpsk.m`)

## Đã làm gì

Bản QPSK là file mới, `Tx.m`/`Rx.m` giữ nguyên. Mỗi ký hiệu mang 2 bit (Gray, `(±1±j)/√2`), block = `[pilot phức, 5 ký hiệu dữ liệu]`. Preamble giữ ±1 nên phần đồng bộ và ước lượng CFO không phải đổi. Thay đổi thuật toán duy nhất cần thiết là pilot phức: `g = mf/pilot_sym` bù được cả biên độ lẫn pha quay sóng mang. Với BPSK chỉ cần đúng dấu, còn với QPSK lệch pha là sai bit.

## Kết quả qua cáp thật (khung 20 block, 200 bit)

BER 0/200. CFO -18.4 Hz (~0,23% lệch đồng hồ, cùng bậc với ~3000 ppm ở bản BPSK). Lệch timing pilot trôi 3 → 18 mẫu qua 20 block, gần 40% một ký hiệu (`sps` = 48), và bộ bù drift bám đúng. Thiếu bộ bù này thì lấy mẫu sang ký hiệu bên cạnh.

## Bài học

1. BER = 0 trên ít bit không nói nhiều. 200 bit chỉ cho biết BER < ~1,5% (độ tin cậy 95%). Cần thêm thước đo mịn hơn: EVM (độ tản cụm) và khung dài hơn. Lúc đó tôi ghi sàn EVM ở loopback không nhiễu là ~4% (~28 dB) và dùng nó làm mốc so với cáp thật. Về sau hóa ra sàn này là do lỗi chọn timing pilot (xem bài học 6 ở phần audio), không phải giới hạn của modem.
2. Nghi ngờ chưa phải lỗi, nên dựng mô phỏng xem có hỏng thật không trước khi sửa. Dự đoán ban đầu "khung dài sẽ hỏng vì `search_win = ±3` không cộng dồn" không tái hiện khi SNR tốt: khung 6000 ký hiệu, lệch 0,23%, timing trôi ~670 mẫu vẫn BER 0. Chỉ hỏng khi preamble nhiễu (σ=0,6): CFO sai ~1 Hz → BER 15%. Mô phỏng kênh ngay trong loopback (nội suy spline theo `(1+e)` cộng nhiễu) rẻ hơn nhiều so với chờ thu thật.
3. Ngưỡng hỏng là ~nửa ký hiệu, không phải ±3 mẫu (suy luận, khớp mô phỏng). Lệch 14 mẫu vẫn giữ đúng dấu vì ký hiệu đúng chiếm ~70% mẫu MF, và chỉ hỏng khi lệch vượt ~24 mẫu. Ca σ=0,6 lệch ~36 mẫu ở cuối khung.
4. Nguyên nhân gốc: `drift` suy ra từ `cfo_hz`, mà `cfo_hz` chỉ đo trên 50 ký hiệu preamble. Sai số CFO nhân với vị trí (chục nghìn mẫu cuối khung dài). Cách sửa lúc đó là tinh chỉnh CFO bằng pha pilot trên cả khung (pha pilot đã biết tăng tuyến tính theo CFO dư, đường cơ sở dài nên chính xác hơn nhiều). Ca σ=0,6: preamble ra 15,85 / -19,58 Hz, sau tinh chỉnh ra đúng 18,40 Hz (giá trị thật), BER từ 15% xuống 0,03% / 0%. Bước này về sau được thay bằng bộ bám theo đoạn (xem phần audio).
5. Tinh chỉnh phải làm dần (K block đầu, tăng ×4), không dùng cả khung ngay. Khi CFO thô còn lệch, vị trí pilot ở cuối khung đã trôi sang ký hiệu khác, pha ở đó là rác, `unwrap` hỏng và độ dốc sai. Bắt đầu từ vài block đầu (vị trí còn đúng), CFO được chỉnh dần rồi mới mở rộng.
6. Hai chế độ dùng chung tên biến (`tx_signal`, `data_bits`) giữa BPSK và QPSK. Đổi qua lại trong một phiên MATLAB phải `clear`, không thì giải mã với bit sai và ra BER ~0,5, trông y như lỗi kênh. `Rx_qpsk.m` luôn nạp lại `tx_params_qpsk.mat` để tránh.

## Chưa làm lúc đó (cả hai mục dưới đã xong ở phần audio bên dưới)

- Chạy khung 200 block qua cáp thật (mới xác nhận trên mô phỏng/loopback).
- Payload audio: 1000 baud × 2 bit = 2 kbps, trong khi audio 8 kHz × 8-bit cần 64 kbps. Phải tăng baud hoặc hạ mạnh chất lượng audio, và gửi nhiều hơn thời lượng thật (không phải truyền trực tiếp).

# Bài học rút ra: audio qua QPSK (`Audio_qpsk.m`)

## Đã làm gì

`Audio_qpsk.m` gửi 1 s âm thanh (8 kHz, 8 bit/mẫu = 64000 bit) qua đúng modem QPSK, baud 4000 (sps = 12), khung 10,6 s. Modem không biết payload là gì: phần riêng của audio chỉ là lượng tử hóa ở Tx và ghép bit lại thành mẫu ở Rx. Bản này gửi cả khung rồi mới phát lại, không truyền trực tiếp, nên bit rate chỉ quyết định khung dài bao lâu (1 s âm thanh ≈ 10 s khung) và không cần đạt 64 kbps.

## Lần thu thật đầu tiên hỏng (BER 0,4991)

Loopback và mô phỏng đều BER 0, nhưng qua cáp thật:

- CFO preamble -25,52 Hz, sau tinh chỉnh bằng pilot ra -48,00 Hz. Ở các lần 1000 baud trước, hai số này chỉ lệch 0,05 Hz.
- 12 block đầu đúng, sau đó lỗi ngẫu nhiên (~5/10 bit mỗi block), EVM 171%.
- Sync rất chắc (peak/median ~3e5), tín hiệu đủ lớn, phổ đúng (dải 4-12 kHz qua sạch).

## Chẩn đoán: dựng lại từ bản thu đã lưu

`rx_debug_audio.wav` giữ nguyên bản thu nên phân tích được offline nhiều vòng:

1. Quét CFO theo độ đồng pha pilot toàn khung: đỉnh ở -24,4 Hz, không phải -48. Vậy bước tinh chỉnh bị phân kỳ, còn CFO thật vẫn như các lần trước.
2. In từng giai đoạn tinh chỉnh (K = 20, 80, 320, 1280, 5120, 6400): hội tụ đúng đến -24,38 Hz ở K = 1280, chỉ hỏng ở K = 5120 (bước pha giữa hai pilot đạt π, `unwrap` nhảy sai, dcfo = -9 Hz). Con số cuối (-48) là rác; các giai đoạn giữa mới cho biết chuyện xảy ra ở đâu.
3. Độ đồng pha theo nhóm block ở CFO -24,38: đúng 1,00 (offset 0) đến block ~1715, sau đó sụp và không offset nào trong ±8 mẫu cứu được.
4. Pha từng pilot quanh block 1720: biên độ và pha đứng yên (∠-0,68 rad) rồi quay đều +0,27 rad/block, tức ≈ +28 Hz so với -24,4 Hz. Tín hiệu vẫn còn (RMS phẳng 0,255). Vậy tốc độ lệch đồng hồ đổi giữa khung, CFO nhảy từ ≈ -24 Hz về ≈ 0.

Sau khi sửa, bộ bám cho quỹ đạo CFO trên bản thu này: min / median / max = -26 / -0,2 / +1,5 Hz, lệch timing pilot tăng đến ~433 mẫu rồi phẳng. Lần thu thứ hai qua cáp ra đúng cùng hình dạng (433 → 432 mẫu), nên hiện tượng lặp lại được và không phải trục trặc ngẫu nhiên. Nguồn gốc (điện thoại, PulseAudio, hay cả hai) chưa xác định.

## Nguyên nhân gốc và cách sửa

`Rx_qpsk.m` gộp cả khung thành một CFO rồi suy tốc độ trôi (`drift`) và vị trí pilot dự đoán từ nó. Cách này đúng khi lệch đồng hồ cố định (khung 1,25 s trước đây) và sai khi nó đổi giữa khung. `Audio_qpsk.m` không sai; nó làm khung dài lên 8 lần nên giả định này lộ ra.

Sửa: bám theo từng đoạn 10 block. Mỗi đoạn có 2 vòng tinh chỉnh CFO bằng độ dốc pha pilot, với vị trí neo tại đầu đoạn (sai số CFO chỉ nhân với 10 block chứ không nhân với cả khung), rồi chọn lệch timing ±2 mẫu theo độ đồng pha pilot của cả đoạn. Bộ tinh chỉnh dần K = 20 → 80 → … (bài học 5 ở phần QPSK) và `movmedian` timing không còn cần nữa.

## Kết quả

| Trường hợp | BER |
|---|---|
| Bản thu thật 10,6 s (lỗi trước đó) | 0 / 64000, 0 / 8000 mẫu sai |
| Thu thật lại lần 2 qua cáp | 0 / 64000, 0 / 8000 mẫu sai |
| Bản thu thật 1,25 s (200 block, 1000 baud) | 0 / 2000, EVM 6,2% |
| Loopback | 0 / 64000, EVM 0% |
| Mô phỏng lệch 0,3% cố định | 0 / 64000 |
| Mô phỏng lệch 0,3% rồi -0,05% ở giây thứ 3 | 0 / 64000 |

## Bài học

1. Kéo dài khung hay tăng baud là đổi giả định, không chỉ đổi tham số. "Một CFO cho cả khung" đúng ở 1,25 s nhưng sai ở 10,6 s. Trước khi cho chạy thật phải kiểm giả định đó, đừng chỉ kiểm BER trên mô phỏng dựng theo chính giả định ấy.
2. Mô phỏng phải chứa đúng loại sai lệch có thể gặp. Mô phỏng ban đầu chỉ có lệch đồng hồ cố định nên không thể lộ lỗi này. Bộ kiểm giờ có thêm ca lệch đổi giữa khung (nội suy spline theo tỉ lệ `r(t)` từng đoạn, giữ liên tục pha sóng mang).
3. Luôn giữ bản thu thô (`rx_debug_*.wav`) và phân tích offline. Một bản thu hỏng cho ra cả chẩn đoán lẫn bộ kiểm hồi quy. Đừng ghi đè bản thu thật bằng bản mô phỏng.
4. In các giai đoạn trung gian của bộ ước lượng, đừng chỉ nhìn kết quả cuối. Con số -48 Hz trông như "CFO thật khác đi", nhưng các giai đoạn K cho thấy 4 giai đoạn đầu đúng và chỗ hỏng nằm ở phía sau.
5. Quét offset rộng trên tín hiệu tuần hoàn cho đỉnh giả. Pilot lặp mỗi 72 mẫu, nên quét ±4000 mẫu rơi vào bội của 72 và độ đồng pha ra 1,00 ở khắp nơi. Cần thu hẹp dải quét hoặc kiểm bằng cách khác trước khi tin.
6. Chọn timing pilot bằng `max|mf|` từng block là mơ hồ với QPSK. Pilot trùng 1 trong 4 điểm chòm sao, nên khi ký hiệu kề bằng pilot thì |mf| phẳng trên nhiều mẫu và `max` chọn bừa (loopback không nhiễu vẫn nhảy ±3 mẫu). Đây chính là "sàn EVM 4% ở loopback" mà phần QPSK ghi là vốn có: 4% ở sps = 48, 15% ở sps = 12, và về 0% khi chọn timing theo độ đồng pha cả đoạn.
7. Vặt: `cp` bị alias thành hỏi xác nhận và treo lệnh nền, dùng `command cp -f`. In danh sách từng block cho khung 6400 block ra cả megabyte, nên chỉ in tóm tắt khi `num_blocks` > 300.

## Chưa làm

- EVM ~15-17% ở sps = 12 (lấy mẫu ở vị trí nguyên, lệch tối đa nửa mẫu): BER vẫn 0 nhưng biên dự phòng mỏng. Cần nội suy phân số mẫu nếu tăng baud hoặc dùng 16-QAM.
- Chưa thử âm thanh của người dùng (`AUDIO_FILE`) hay đoạn dài hơn 1 s (khung càng dài càng dễ gặp thêm lần đổi tốc độ lệch).
- Chưa biết vì sao lệch đồng hồ đổi ở khoảng 2,6 s vào khung.
