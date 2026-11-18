# Bài học rút ra: modem audio 2-PAM qua cáp

## Triệu chứng ban đầu

Chạy `Rx.m` với `baud_rate = 1000` (sps = 48), thu qua cáp tai nghe thật:

- Đồng bộ preamble rất chắc chắn (peak/median tương quan ~48000).
- CFO ước lượng ổn định quanh -24 Hz giữa nhiều lần chạy khác nhau.
- BER tổng = 0.21, nhưng lỗi không rải đều: block 1-12 sạch 100%, lỗi chỉ xuất hiện và tăng dần từ block 13 trở đi.

Lỗi tăng dần về cuối khung trong khi đồng bộ và CFO đều tốt. Điều này gợi ý một sai số tích lũy theo thời gian chưa được bù, không phải nhiễu ngẫu nhiên hay khóa nhầm preamble.

## Chẩn đoán: CFO dư hay lệch đồng hồ lấy mẫu?

Hai giả thuyết khả dĩ cho "lỗi tăng dần":

1. CFO dư (pha sóng mang trôi dư): ước lượng CFO từ preamble không tuyệt đối chính xác, sai số nhỏ còn lại làm pha quay lệch dần theo thời gian tuyệt đối.
2. Lệch đồng hồ lấy mẫu: DAC điện thoại và ADC laptop chạy tự do, không chung tham chiếu, nên số mẫu thực tế mỗi ký hiệu trôi dần so với `sps` danh nghĩa dùng ở Rx.

Hai giả thuyết dự đoán khác nhau khi đổi `baud_rate`. Hạ `baud_rate` (tăng `sps`) làm chu kỳ ký hiệu dài gấp đôi theo thời gian thực. Nếu là CFO dư, sai số pha tích lũy theo thời gian sẽ tăng nhanh gấp đôi tính trên cùng số ký hiệu/block, nên lỗi phải xuất hiện ở block sớm hơn. Nếu là lệch đồng hồ lấy mẫu, lệch tính bằng số mẫu tỉ lệ với `sps × số block` như nhau, nên vị trí lỗi theo chỉ số block gần như không đổi khi đổi `baud_rate`.

Thử nghiệm: hạ `baud_rate` xuống 500. BER gần như không đổi (0.21 → 0.18), lỗi vẫn bắt đầu quanh block 13-14 như cũ. Kết quả khớp dự đoán của giả thuyết 2 và loại giả thuyết 1: đây là lệch đồng hồ lấy mẫu, không phải CFO dư.

Khi một triệu chứng có nhiều nguyên nhân khả dĩ, cách rẻ nhất để phân biệt là đổi một tham số hệ thống (ở đây là `baud_rate`) theo hướng mà các giả thuyết dự đoán khác nhau, thay vì đoán mò hoặc sửa cả hai cùng lúc.

## Giải pháp: theo dõi trôi pilot kiểu early-late

Kiến trúc cũ giả định vị trí mẫu mỗi block cố định theo công thức `data_start + (blk-1)*(bits_per_block+1)*sps`. Công thức đúng về lý thuyết nhưng sai dần theo thực tế phần cứng.

Sửa trong `Rx.m`: mỗi block, tìm lại đỉnh pilot (biên độ `|mf_corr|` lớn nhất) trong một cửa sổ nhỏ (`search_win = round(sps/4)`) quanh vị trí dự đoán, tức vị trí danh nghĩa cộng lệch tích lũy từ block trước, rồi mang lệch tìm được sang block kế tiếp. Cách này không cần mô hình hóa đầy đủ tỉ lệ drift hay resample lại cả tín hiệu, và dùng luôn hạ tầng pilot zero-forcing đã có.

## Kết quả

| baud_rate | Trước khi sửa | Sau khi sửa |
|---|---|---|
| 1000 | BER 0.2100 (lỗi tăng dần cuối khung) | BER 0.0000 |
| 500  | BER 0.1800 (lỗi tăng dần cuối khung) | BER 0.0000 |

Lệch tích lũy đo được tăng đều theo block ở cả hai baud_rate. Quy ra ppm (lệch mẫu chia tổng số mẫu đã trôi qua kể từ preamble), hai lần chạy độc lập cho kết quả nhất quán, ~3000-3100 ppm. Điều đó củng cố thêm rằng đây là tỉ lệ lệch đồng hồ cố định của cặp thiết bị, không phải nhiễu ngẫu nhiên mỗi lần đo.

CFO đo được cũng ổn định quanh -24 Hz giữa các lần chạy, gợi ý đây là lệch tần số danh nghĩa cố định của phần cứng. Bù CFO (qua `cfo_hz`) là bù pha sóng mang, còn bù thời điểm lấy mẫu làm qua pilot tracking. Khung sườn hiện tại cần cả hai, thiếu một trong hai thì BER không về 0.

## Tham số cần tinh chỉnh nếu đổi thiết bị (điện thoại/cáp khác)

- `search_win = round(sps/4)` trong `Rx.m`: cửa sổ tìm pilot mỗi block. Nếu cặp thiết bị mới trôi nhanh hơn ~3000 ppm hoặc block dài hơn (nhiều bit hơn giữa 2 pilot), cần tăng số này. Nếu không, tracker bắt hụt đỉnh pilot khi lệch giữa 2 block liền kề vượt quá cửa sổ.
- `record_time` trong `Rx.m`: vẫn đặt cứng, chỉnh nếu đổi độ dài khung hoặc baud rate làm tổng thời lượng phát thay đổi.

