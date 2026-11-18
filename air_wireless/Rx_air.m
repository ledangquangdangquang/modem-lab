%% Rx_air.m - Fork cua tx_rx_basic/Rx.m cho kenh khong khi (khong day cap)
% Can chay Tx_air.m truoc. Neu workspace bi mat thi nap lai tu tx_air_params.mat.
%
% Khac Rx.m goc: qua khong khi co da duong that (tia truc tiep + phan xa
% tuong/ban), be mat tuong quan co the co vai dinh gan nhau thay vi 1 dinh
% sach nhu qua cap. Neu lay max(abs(c)) nhu ban cap, co the khoa nham vao
% mot phan xa manh hon nhung den sau, lam start_idx tre di vai mau va keo
% lech het cac buoc sau (CFO tu preamble, dinh pilot...). Sua: sau khi quet
% CFO tho de tim dinh cuc dai (van dung vi hinh dang/tan so tin hieu khong
% doi theo duong truyen), chon dinh SOM NHAT vuot nguong (thay vi dinh cao
% nhat) de khoa vao tia truc tiep - xem buoc dong bo ben duoi.
if ~exist('Fs', 'var')
    load(fullfile(fileparts(mfilename('fullpath')), 'tx_air_params.mat'));
end

RX_SOURCE = 'record'; % 'loopback' = tu-kiem-tra khong can dien thoai/mic that
                        % 'record'   = thu that qua khong khi (loa dien thoai -> mic laptop)
                        % 'file'     = doc lai rx_air_debug.wav da thu truoc do

if strcmp(RX_SOURCE, 'loopback')
    rx_raw = tx_signal(:);
elseif strcmp(RX_SOURCE, 'file')
    rx_raw = audioread(fullfile(fileparts(mfilename('fullpath')), 'rx_air_debug.wav'));
else
    % ponytail: tx_air.wav dai ~3.3s (1.5s lang + 0.27s khung + 1.5s lang);
    % ghi 8s de co du dem cho tre bam nut phat/thu qua khong khi
    record_time = 8;
    input_device_id = -1; % -1 = thiet bi mac dinh he thong; neu bi thu nham thiet bi,
                           % chay audiodevinfo(1) de xem danh sach ID roi gan vao day
    if input_device_id >= 0
        rec = audiorecorder(Fs, 16, 1, input_device_id);
    else
        rec = audiorecorder(Fs, 16, 1);
    end
    disp('Bat dau phat tx_air.wav tren dien thoai ngay bay gio...');
    recordblocking(rec, record_time);
    rx_raw = getaudiodata(rec);
    fprintf('Muc tin hieu thu duoc: peak=%.4f, rms=%.4f (gan 0 nghia la thu nham thiet bi hoac mic qua xa loa)\n', ...
        max(abs(rx_raw)), rms(rx_raw));
    audiowrite(fullfile(fileparts(mfilename('fullpath')), 'rx_air_debug.wav'), rx_raw, Fs); % de soi lai neu decode sai
end

% Ha tan xuong baseband phuc (I/Q)
t = (0:length(rx_raw)-1)'/Fs;
rx_bb = rx_raw .* exp(-1j*2*pi*Fc*t);

% Loc phoi hop (integrate-and-dump ~ trung binh truot do dai 1 ky hieu)
mf_out = conv(rx_bb, ones(sps,1)/sps, 'same');

% Dong bo: tuong quan cheo voi preamble da biet, quet qua luoi CFO ung vien truoc
% (giu nguyen ly do nhu ban cap - xem tx_rx_basic/README.md phan "Dong bo + quet CFO tho").
preamble_sym = 2*preamble_bits - 1;
preamble_ref = repelem(preamble_sym, sps).';
n_full = (0:length(mf_out)-1)';
cfo_grid = -500:15:500;
best_peak = -1;
for cfo_try = cfo_grid
    derot = mf_out .* exp(-1j*2*pi*cfo_try*n_full/Fs);
    [c_try, lags_try] = xcorr(derot, preamble_ref);
    [pv, pk_try] = max(abs(c_try));
    if pv > best_peak
        best_peak = pv; c = c_try; lags = lags_try;
    end
end
peak_val = best_peak;

% ponytail: chon DINH CUC BO SOM NHAT vuot 70% dinh cuc dai, thay vi
% max(abs(c)), de khoa vao tia truc tiep chu khong phai phan xa manh hon
% nhung den sau. Chu y: phai la dinh cuc bo (local max), khong phai mau
% dau tien vuot nguong - vi sau loc phoi hop, canh len cua dinh tuong quan
% la mot doc thoai chu khong dung, lay mau dau tien vuot 70% se rung vao
% giua doc do (som hon dinh that vai mau, khong tron ky hieu) va lam sai
% toan bo cac buoc lay mau sau nay. Nguong 70% la kinh nghiem (cao qua bo
% sot tia truc tiep yeu, thap qua de bat nham nen nhieu).
early_thresh_frac = 0.7;
c_abs = abs(c);
is_local_max = [false; c_abs(2:end-1) >= c_abs(1:end-2) & c_abs(2:end-1) >= c_abs(3:end); false];
above = find(is_local_max & c_abs >= early_thresh_frac * peak_val);
if isempty(above)
    [~, pk] = max(c_abs); % ponytail: fallback neu khong dinh cuc bo nao qua nguong
else
    pk = above(1);
end
start_idx = lags(pk) + 1;
sync_confidence = peak_val / median(abs(c)); % thap (~vai lan) nghia la khong that su tim thay preamble
fprintf('Dong bo: peak/median tuong quan = %.1f (cang cao cang chac chan tim dung preamble)\n', sync_confidence);

if start_idx < 1 || start_idx + length(preamble_ref) - 1 > length(mf_out)
    error('Khong tim thay preamble trong tin hieu thu duoc.');
end

% Uoc luong CFO tu do troi pha cua preamble (giu nguyen nhu ban cap)
preamble_seg = mf_out(start_idx : start_idx + length(preamble_ref) - 1);
sym_val = zeros(length(preamble_bits), 1);
for k = 1:length(preamble_bits)
    idx_c = (k-1)*sps + round(sps/2);
    sym_val(k) = preamble_seg(idx_c) * preamble_sym(k); % bu dau +-1
end
diffs = sym_val(2:end) .* conj(sym_val(1:end-1));
avg_step = angle(mean(diffs));
cfo_hz = avg_step / (2*pi*sps/Fs);

% Bu CFO tu vi tri preamble tro di
n = (0:length(mf_out)-start_idx)';
mf_corr = mf_out(start_idx:end) .* exp(-1j*2*pi*cfo_hz*n/Fs);

% Lay mau tung ky hieu, can bang kenh tren tung block bang pilot (zero-forcing),
% bam troi dong ho mau (giu nguyen thuat toan nhu ban cap)
data_start = length(preamble_ref) + 1;
pilot_sym = 2*pilot_val - 1;
rx_bits = zeros(1, num_blocks*bits_per_block);
bit_ptr = 1;
drift = -cfo_hz / (Fc + cfo_hz);
search_win = 3;
block_timing = zeros(1, num_blocks);
for blk = 1:num_blocks
    blk_off_nom = data_start + (blk-1)*(bits_per_block+1)*sps;
    pilot_nom = blk_off_nom + round(sps/2) - 1;
    pilot_idx_nom = pilot_nom + round(drift * pilot_nom);
    cand = pilot_idx_nom + (-search_win:search_win);
    cand = cand(cand >= 1 & cand <= length(mf_corr));
    [~, best_k] = max(abs(mf_corr(cand)));
    pilot_idx = cand(best_k);
    timing_off = pilot_idx - pilot_nom;
    block_timing(blk) = timing_off;
    blk_off = blk_off_nom + timing_off;
    g = mf_corr(blk_off + round(sps/2) - 1) / pilot_sym;
    for b = 1:bits_per_block
        idx_c = blk_off + b*sps + round(sps/2) - 1 + round(drift*b*sps);
        eq_sym = mf_corr(idx_c) / g;
        rx_bits(bit_ptr) = real(eq_sym) > 0;
        bit_ptr = bit_ptr + 1;
    end
end
fprintf('Lech dinh pilot tich luy tung block (mau, +-%d la cua so tim): %s\n', search_win, mat2str(block_timing));

[num_err, ber] = biterr(data_bits, rx_bits);
fprintf('CFO uoc luong: %.2f Hz. So bit loi: %d / %d, BER = %.4f\n', ...
    cfo_hz, num_err, numel(data_bits), ber);

block_err = zeros(1, num_blocks);
for blk = 1:num_blocks
    idxs = (blk-1)*bits_per_block+1 : blk*bits_per_block;
    block_err(blk) = sum(rx_bits(idxs) ~= data_bits(idxs));
end
fprintf('Loi tung block (block 1..%d): %s\n', num_blocks, mat2str(block_err));

scatterplot(mf_corr(data_start:end));
title('Ky hieu du lieu sau can bang pilot (kenh khong khi)');
figure; plot(real(rx_bb)); title('Baseband I sau ha tan (kenh khong khi)');
