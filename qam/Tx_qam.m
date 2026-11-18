%% Tx_qam.m - Sinh khung M-QAM co doan bao ve chen 0 (ZP) theo bang sang che FSK, ghi ra tx_cable_qam.wav
% Ban M-QAM cua Tx_qpsk.m (khong dong vao Tx_qpsk.m). Chay file nay truoc, roi Rx_qam.m
% (RX_SOURCE = 'sim' de thu kenh da duong mo phong, khong can dien thoai).
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
baud_rate = 1000;   % toc do ky hieu
sps = Fs/baud_rate; % mau/ky hieu (48)

M_qam = 16;         % 4 / 16 / 64 ... -> log2(M_qam) bit moi ky hieu
Lh = 31;            % do dai tieu de (ky hieu)
Lz = 8;             % doan 0 (ky hieu) = 8 ms o 1000 baud; phai > trai tre kenh + mg (xem Rx_qam.m)
syms_per_sub = 5;   % ky hieu du lieu sau moi pilot
n_sub = 10;         % so nhom [pilot, 5 ky hieu] trong 1 block
Ld = n_sub*(syms_per_sub+1); % 60 ky hieu du lieu+pilot moi block
num_blocks = 20;    % 20 block * 50 ky hieu * 4 bit = 4000 bit (16-QAM), khung ~2.2 s
pilot_sym = (1+1j)/sqrt(2); % pilot = 1∠45°
hdr_sym = exp(-1j*pi*(0:Lh-1).*(1:Lh)/Lh); % Zadoff-Chu goc 1: x(n) = 1∠(-pi*n*(n+1)/Lh)

k_bits = log2(M_qam);
preamble_bits = randi([0 1], 1, 50); % giu +-1 (BPSK) de Rx dong bo + uoc luong CFO nhu cu
data_bits = randi([0 1], 1, num_blocks*n_sub*syms_per_sub*k_bits);
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

pad = zeros(1, round(0.5*Fs));        % khoang lang dau/cuoi cho de bat dau ghi am
tx_signal = [pad, passband, pad];
tx_signal = 0.9 * tx_signal / max(abs(tx_signal));

audiowrite('tx_cable_qam.wav', tx_signal(:), Fs);
save('tx_params_qam.mat', 'Fs', 'Fc', 'baud_rate', 'sps', 'M_qam', 'Lh', 'Lz', 'Ld', ...
    'syms_per_sub', 'n_sub', 'num_blocks', 'pilot_sym', 'hdr_sym', 'preamble_bits', ...
    'data_bits', 'tx_signal');
fprintf('Da ghi tx_cable_qam.wav: %d-QAM, %d bit du lieu trong %d block, khung %.2f s (hieu suat %.0f %%).\n', ...
    M_qam, numel(data_bits), num_blocks, numel(baseband)/Fs, ...
    100*n_sub*syms_per_sub/(Lh+Lz+Ld+Lz));
fprintf('Copy file sang dien thoai, phat, roi chay Rx_qam.m.\n');
