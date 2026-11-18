- Bên phát

  1. Khối tạo khung truyền, mỗi khung gồm 3 phần **Tiêu đề - các số 0 và dữ liệu** 
  
  2. Khối điều chế BFSK bit 0 -> tần số F0, bit 1 -> tần số F1

  3. Khối DAC dùng biến đổi tín hiệu số thành tín hiệu tuơng tự để truyền đi.

  4. Khối đưa đến bộ chuyển đổi điện cơ (Transducer) để đưa sóng cơ học truyền dẫn trên kênh truyền thuỷ âm.

  Sóng cơ học là sóng đựoc giao động trong vùng tần số sóng âm hoặc siêu âm để có lan truyền trong môi truờng nuớc.

  5. Khối kênh truyền thuỷ âm

- Bên thu

  6. Thu nhận lại bộ biến đổi cơ điện (Transducer)

  7. Khối ADC

  8. Khối lọc thông dải BPF1 
    - Loại bớt nhiễu ngoài băng cho tín hiệu bit 0 có dải tần từ [2F0 - Fc, Fc] 

  9. Khối lọc thông dải BPF2
    - Loại bớt nhiễu ngoài băng cho tín hiệu bit 1 có dải tần từ [Fc, 2F1 - Fc] 
    
  10. Tạo dao động tần số **F1** 
    - Tạo thành 2 thành phần sóng trực giao theo hàm sin và cos phục vụ cho bộ giải điều chế I/Q cho tín hiệu **bit 0**

  11. Tạo dao động tần số **F2**
    - Tạo thành 2 thành phần sóng trực giao theo hàm sin và cos phục vụ cho bộ giải điều chế I/Q cho tín hiệu **bit 1**

  12. Bộ lọc thông thắp LPF: tần số cắt Fc - F1
    - Phục vụ cho giải điều chế tín hiệu I/Q

  13. Thực hiện phép nhân phần ảo để tạo nguồn tín hiệu phức sau bộ tổng

  14. Thực hiện tách phần tiêu đề và phần chèn không của khung dữ liệu thu đuợc. 

  15. Tách phần dữ liệu trong khung truyền thu đựoc

  16. Thêm Ld-Lh-Lz số 0 vào phần tiêu đề và phần chèn 0 để đảm bảo độ dài của phần tiêu và chèn không bằng độ dài của phần dữ liệu. 

  17. Trong truờng hợp độ dài của phần dữ liệu nhỏ hơn tổng độ dài của phần tiêu đề và chèn không Ld < Lh +Lz thì chèn thêm Lh+Lz-Ld số 0 vào sau phần dữ liệu

  18. Thực hiện tính giá trị của kênh vô tuyến duới nứoc.

  19. Thực hiện biến đổi dữ liệu từ miền thời gian sang miền tần số FFT

  20. Thực hiện khôi phục lại dữ liệu trong miền tần số bằng cách lấy tín hiệu thu chia cho giá trị kênh truyền trong miền tần số

  21. Thực hiện biến đổi nguợc lại IFFT và cắt bỏ tín hiệu thừa.

  22. Thực hiện phép trừ hai tín hiệu thu đuợc từ 2 nhánh giải mã bit 0 1

  23. Thực hiện tính toán và hiệu chỉnh góc pha của tín hiệu.

  24. Thực hiện giải điều chế tín hiệu dựa trên so sánh nguỡng: >= 0 -> 1, < 0 -> 0
