%% Tx_qpsk_air.m - Khung QPSK truyen qua KHONG KHI (loa dien thoai -> mic laptop, khong cap)
% Ban sao cua qam/Tx_qam.m voi M_qam = 4 (QPSK), 500 baud, khoang lang 1.5 s (khong dong vao Tx_qam.m).
% Vi sao khong fork Tx_qpsk.m: trong phong co tieng vang (da duong), can bang 1 he so bang pilot cua
% Rx_qpsk.m khong go duoc -> dung khung chen 0 + can bang mien tan so cua qam/ (xem docs/huong_dan.md).
% Chay file nay truoc (cd vao qpsk_air/), phat tx_air_qpsk.wav bang loa dien thoai, roi Rx_qpsk_air.m.
%
% Khung (don vi: ky hieu):
%   [preamble +-1 | 0 | tieu de | 0 | du lieu | 0 | tieu de | 0 | du lieu | 0 | ...]
%   - preamble (50): giong Tx_qpsk -> Rx_qam dung lai nguyen code dong bo + CFO tho.
%   - tieu de (Lh): da biet o Rx, dung uoc luong kenh H (buoc 4-6 bang sang che).
%     Chon Zadoff-Chu (chirp roi rac, |x| = 1, pho gan phang) thay vi bit ngau nhien:
%     Rx chia cho FFT(tieu de), bit ngau nhien co tan so ~0 -> chia no tung.
%   - doan 0 (Lz) >= trai tre kenh: duoi da duong cua tieu de/du lieu roi vao doan 0,
%     khong de len phan sau -> tich chap tuyen tinh = tich chap vong -> chia FFT chinh xac.
%   - du lieu (Ld): n_sub nhom [pilot, syms_per_sub ky hieu M-QAM]. Pilot KHONG co trong
%     bang sang che: them de bam pha du (CFO doi giua khung tren dien thoai that) va bien do
%     (M-QAM can dung bien do, QPSK chi can pha).

Fs = 48000;         % sample rate
Fc = 8000;          % tan so mang
baud_rate = 500;    % toc do ky hieu; thap hon ban cap: ky hieu 2 ms, doan 0 dai 16 ms che duoc vang xa hon
sps = Fs/baud_rate; % mau/ky hieu (96)

M_qam = 4;          % 4 = QPSK (2 bit/ky hieu); 16 / 64 chi khi EVM do duoc du thap
Lh = 31;            % do dai tieu de (ky hieu)
Lz = 8;             % doan 0 (ky hieu) = 16 ms o 500 baud; phai > trai tre kenh + mg (xem Rx_qpsk_air.m)
syms_per_sub = 5;   % ky hieu du lieu sau moi pilot
n_sub = 10;         % so nhom [pilot, 5 ky hieu] trong 1 block
Ld = n_sub*(syms_per_sub+1); % 60 ky hieu du lieu+pilot moi block
num_blocks = 20;    % 20 block * 50 ky hieu * 2 bit = 2000 bit (QPSK), khung ~4.4 s
pilot_sym = (1+1j)/sqrt(2); % pilot = 1∠45°
hdr_sym = exp(-1j*pi*(0:Lh-1).*(1:Lh)/Lh); % Zadoff-Chu goc 1: x(n) = 1∠(-pi*n*(n+1)/Lh)

k_bits = log2(M_qam);
preamble_bits = randi([0 1], 1, 50); % giu +-1 (BPSK) de Rx dong bo + uoc luong CFO nhu cu
% Ma sua loi Reed-Solomon tren GF(256) (1 ky hieu RS = 1 byte): rs_k byte tin -> rs_n byte phat,
% sua duoc (rs_n - rs_k)/2 byte sai bat ky. Ca khung la 1 tu ma (rut gon tu RS(255, .)).
% rs_k = 186 -> sua 32 byte; ban thu that tot nhat sai 11-12 byte / 250, ban xau 85 (khong cuu duoc).
rs_n = num_blocks*n_sub*syms_per_sub*k_bits / 8; % so byte khung cho duoc (250 voi QPSK)
rs_k = 186;                                      % so byte tin; giam di de sua duoc nhieu hon
assert(rs_n == floor(rs_n) && rs_n <= 255 && rs_k < rs_n, ...
    'RS: khung phai chua so byte nguyen <= 255 (doi num_blocks/M_qam thi phai chia thanh nhieu tu ma)');
msg_bits = randi([0 1], 1, rs_k*8);              % bit tin goc (Rx so sanh sau khi giai ma RS)
msg_bytes = 2.^(7:-1:0) * reshape(msg_bits, 8, []);             % 8 bit -> 1 byte, MSB truoc
code = rsenc(gf(msg_bytes, 8), rs_n, rs_k);      % tu ma = [byte tin | byte kiem tra]
code_bytes = double(code.x);
data_bits = reshape(rem(floor(code_bytes ./ 2.^(7:-1:0)'), 2), 1, []);  % byte -> bit, day la bit len song
% Gray, cong suat trung binh 1 (16-QAM: diem goc 1.34∠45°, diem trong 0.45∠45°)
data_syms = qammod(data_bits(:), M_qam, 'gray', 'InputType', 'bit', 'UnitAveragePower', true).';

z = zeros(1, Lz);
frame_syms = [];
for k = 1:num_blocks
    d = reshape(data_syms((k-1)*n_sub*syms_per_sub+1 : k*n_sub*syms_per_sub), syms_per_sub, n_sub);
    d = [pilot_sym*ones(1, n_sub); d]; % moi cot = [pilot; 5 ky hieu du lieu]
    frame_syms = [frame_syms, hdr_sym, z, d(:).', z]; %#ok<AGROW>
end
symbols = [2*preamble_bits - 1, z, frame_syms];

baseband = repelem(symbols, sps);     % xung vuong, integrate-and-dump o Rx se khop
t = (0:length(baseband)-1)/Fs;
passband = real(baseband .* exp(1j*2*pi*Fc*t)); % I*cos - Q*sin

pad = zeros(1, round(1.5*Fs));        % khoang lang dau/cuoi: bam phat/thu bang tay qua khong khi can dem dai hon cap
tx_signal = [pad, passband, pad];
tx_signal = 0.9 * tx_signal / max(abs(tx_signal));

audiowrite('tx_air_qpsk.wav', tx_signal(:), Fs);
save('tx_params_qpsk_air.mat', 'Fs', 'Fc', 'baud_rate', 'sps', 'M_qam', 'Lh', 'Lz', 'Ld', ...
    'syms_per_sub', 'n_sub', 'num_blocks', 'pilot_sym', 'hdr_sym', 'preamble_bits', ...
    'data_bits', 'tx_signal', 'msg_bits', 'rs_n', 'rs_k');
fprintf('Da ghi tx_air_qpsk.wav: %d-QAM, %d bit du lieu trong %d block, khung %.2f s (hieu suat %.0f %%).\n', ...
    M_qam, numel(data_bits), num_blocks, numel(baseband)/Fs, ...
    100*n_sub*syms_per_sub/(Lh+Lz+Ld+Lz));
fprintf('Copy file sang dien thoai, phat bang LOA NGOAI cach mic laptop 10-30 cm, roi chay Rx_qpsk_air.m.\n');
