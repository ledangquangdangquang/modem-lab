%% Rx_qpsk.m - Ghi am / doc lai tin hieu va giai dieu che QPSK 4000 bit/s
% Ban QPSK cua Rx.m (khong dong vao Rx.m). Can chay Tx_qpsk.m truoc.
% Luon nap lai tx_params_qpsk.mat (khong dung bien con lai trong workspace) de
% khong ghep nham voi tx_signal/data_bits cua Tx.m (BPSK) -> BER~0.5.
% Audio_qpsk.m goi file nay trong workspace cua ham va dat san params_file/rx_wav/
% record_time/audio_src; chay tay thi cac bien nay lay mac dinh (hang so, khong lech).
%
% Tong quan chuoi xu ly (thu tu KHONG doi cho duoc):
%   1. Lay tin hieu thu rx_raw (loopback / thu am / doc file)
%   2. Ha tan: nhan e^{-j2*pi*Fc*t} -> baseband phuc rx_bb (I + jQ)
%   3. Loc phoi hop (integrate-and-dump) -> mf_out
%   4. Dong bo: tuong quan cheo voi preamble (quet luoi CFO) -> start_idx
%   5. Uoc luong CFO tu preamble -> cfo_hz
%   6. Bam CFO + vi tri pilot theo tung doan M block -> pilot_idx, cfo_blk
%   7. Can bang zero-forcing bang pilot tung block, cat quyet dinh QPSK -> rx_bits
%   8. Tinh BER, EVM, loi tung block; ve do thi
%
% Bien nap tu .mat (do Tx_qpsk.m luu): Fs (tan so lay mau), Fc (song mang), sps (mau/ky hieu),
% preamble_bits, pilot_sym, syms_per_block, num_blocks, data_bits, tx_signal, ...

% Neu chua co params_file (chay tay) thi dung file mac dinh cua QPSK; rx_wav = file luu ban thu
if ~exist('params_file','var'), params_file = 'tx_params_qpsk.mat'; rx_wav = 'rx_debug_qpsk.wav'; end
% Nap moi tham so Tx (Fs, Fc, sps, preamble_bits, data_bits, ...) tu thu muc chua file .m nay
load(fullfile(fileparts(mfilename('fullpath')), params_file));

%% ===== 1. Chon nguon tin hieu thu =====
RX_SOURCE = 'record'; % 'loopback' = tu-kiem-tra khong can dien thoai/cap that
                        % 'record'   = thu that qua cap tai nghe
                        % 'file'     = doc lai rx_debug_qpsk.wav da thu truoc do (chan doan lai
                        %              khong can thu lai lan nua)
if exist('audio_src','var'), RX_SOURCE = audio_src; end % Audio_qpsk.m ghi de lua chon nay

if strcmp(RX_SOURCE, 'loopback')
    rx_raw = tx_signal(:); % loopback: lay thang tin hieu phat lam tin hieu thu (kenh ly tuong), (:) -> vector cot
elseif strcmp(RX_SOURCE, 'file')
    rx_raw = audioread(fullfile(fileparts(mfilename('fullpath')), rx_wav)); % doc ban thu cu tu .wav
else
    if ~exist('record_time','var'), record_time = 5; end % mac dinh 5s; Audio_qpsk.m dat theo do dai khung
    input_device_id = -1; % ponytail: -1 = thiet bi mac dinh he thong; neu bi thu nham
                           % mic laptop thay vi cap tai nghe, chay audiodevinfo(1) de
                           % xem danh sach ID roi gan so do vao day
    if input_device_id >= 0
        rec = audiorecorder(Fs, 16, 1, input_device_id); % bo thu am: tan so Fs, 16 bit, 1 kenh (mono), thiet bi chi dinh
    else
        rec = audiorecorder(Fs, 16, 1); % nhu tren nhung dung thiet bi mac dinh
    end
    disp('Bat dau phat file .wav (tx_cable_qpsk.wav hoac tx_cable_audio.wav) tren dien thoai ngay bay gio...');
    recordblocking(rec, record_time); % thu am record_time giay (chan cho den khi xong)
    rx_raw = getaudiodata(rec); % lay mau da thu ra vector cot (double, trong [-1, 1])
    fprintf('Muc tin hieu thu duoc: peak=%.4f, rms=%.4f (gan 0 nghia la thu nham thiet bi hoac chua cam cap)\n', ...
        max(abs(rx_raw)), rms(rx_raw)); % in muc dinh va rms de kiem tra cap/am luong
    audiowrite(fullfile(fileparts(mfilename('fullpath')), rx_wav), rx_raw, Fs); % ponytail: de soi lai neu decode sai
end

%% ===== 2. Ha tan xuong baseband phuc (I/Q) =====
t = (0:length(rx_raw)-1)'/Fs; % truc thoi gian (giay) cua tung mau
rx_bb = rx_raw .* exp(-1j*2*pi*Fc*t); % nhan voi 1∠(-2*pi*Fc*t): dich pho tu Fc ve 0 Hz
% (thanh phan 2*Fc con lai se bi bo loc phoi hop ben duoi loc bo)

%% ===== 3. Loc phoi hop =====
% Loc phoi hop (integrate-and-dump ~ trung binh truot do dai 1 ky hieu)
% 'same' giu do dai bang rx_bb; mf_out(n) = trung binh sps mau quanh mau n,
% nen dat gia tri lon nhat khi cua so trung khit 1 ky hieu (giua ky hieu).
mf_out = conv(rx_bb, ones(sps,1)/sps, 'same');

%% ===== 4. Dong bo khung =====
% Dong bo: tuong quan cheo voi preamble da biet (+-1, thuc), quet qua luoi CFO
% ung vien truoc. Ly do: tuong quan coherent tren ca 50 ky hieu preamble se tu
% trieu tieu khi CFO that > ~1/(2*50ms) = 10Hz (pha troi het mot vong qua cua so),
% lam khoa nham dinh cham du "do tin cay" bao cao van cao. Quet tho +-500Hz (buoc
% 15Hz) roi lay cap (do tre, CFO) cho dinh tuong quan cao nhat; CFO chinh xac
% duoc tinh lai ben duoi sau khi da khoa dung.
% 52:72 tim index cua `preamble` trong `mf_out`
preamble_sym = 2*preamble_bits - 1; % bit cua preamble -> ky hieu preamble
preamble_ref = repelem(preamble_sym, sps).';% ky hieu preamble -> mau preamble
n_full = (0:length(mf_out)-1)';% vector index cua tin hieu thu duoc
cfo_grid = -500:15:500;% Đây là danh sách các giá trị lệch tần số thử, từ −500 Hz đến +500 Hz với bước 15 Hz (67 giá trị);
best_peak = -1; % dinh tuong quan tot nhat den gio (-1 de lan dau chac chan duoc cap nhat)
for cfo_try = cfo_grid % thu cac gia tri cfo trong cfo_grid
    derot = mf_out .* exp(-1j*2*pi*cfo_try*n_full/Fs);% xoay nguoc pha lai cua tung mau trong mf_out
    [c_try, lags_try] = xcorr(derot, preamble_ref);% [tong tich, cac gia tri dich tuong ung voi tong tich]
    [pv, pk_try] = max(abs(c_try)); % Tim max cua tong tich [gia tri max, index max]
    if pv > best_peak % neu gia tri lon hon gia tri max
        best_peak = pv; c = c_try; lags = lags_try; pk = pk_try; % cap nhat cac gia tri max
    end
end
peak_val = best_peak; % Gia tri tong tich max
start_idx = lags(pk) + 1; % can dich lags(pk) de duoc gia tri max do (do cung la vi tri bat dau cua preamble
sync_confidence = peak_val / median(abs(c)); % thap (~vai lan) nghia la khong that su tim thay preamble
fprintf('Dong bo: peak/median tuong quan = %.1f (cang cao cang chac chan tim dung preamble)\n', sync_confidence);

% Preamble tim duoc phai nam tron trong tin hieu thu, neu khong thi dung han
if start_idx < 1 || start_idx + length(preamble_ref) - 1 > length(mf_out)
    error('Khong tim thay preamble trong tin hieu thu duoc.');
end

%% ===== 5. Uoc luong CFO tu preamble =====
% Uoc luong CFO tu do troi pha cua preamble
% ponytail: dung do lech pha GIUA HAI KY HIEU LIEN TIEP (moi buoc tu wrap ve +-pi),
% khong unwrap tich luy ca 50 diem nua - 1 mau nhieu/meo (rat de gap tren cap that)
% co the lam unwrap nhay sai 2*pi va polyfit doc ra ca mot CFO gia rat lon.
preamble_seg = mf_out(start_idx : start_idx + length(preamble_ref) - 1);% cac mau preamble tu start_idx den vi tri cuoi cua preamble
sym_val = zeros(length(preamble_bits), 1);% Khoi tao mang ky hieu preamble
for k = 1:length(preamble_bits)% lap theo mang ky hieu
    idx_c = (k-1)*sps + round(sps/2);% index cua mau o giua cua 1 ky hieu thu duoc cua Rx
    sym_val(k) = preamble_seg(idx_c) * preamble_sym(k); % Nhan no voi ky hieu preamble o Tx (bu dau +-1)
end
diffs = sym_val(2:end) .* conj(sym_val(1:end-1));% Nhan nhu nay de tru tim goc lech giua 2 mau lien tiep
avg_step = angle(mean(diffs)); %trung binh goc lech giua 2 mau lien tiep (trung binh vector, ben vung voi wraparound hon trung binh goc truc tiep)
cfo_hz = avg_step / (2*pi*sps/Fs); % lay gia tri trung binh do tinh ra lech tan cfo
% (moi ky hieu dai sps/Fs giay, pha quay 2*pi*cfo*sps/Fs rad -> chia nguoc lai ra Hz)

%% ===== 6. Bam CFO + vi tri pilot theo tung doan =====
% Bam CFO + timing pilot theo doan ngan (M block), KHONG gia dinh 1 CFO/toc do troi co dinh
% ca khung. Tren cap that + dien thoai, ty le lech dong ho DOI giua khung (quan sat khung 10 s:
% CFO -24 Hz suot 2.6 s roi nhay sang ~+4 Hz) -> CFO toan khung + drift suy tu no lech qua
% ca ky hieu o cuoi khung, bat dau mat pilot hang loat. Moi doan: tinh chinh CFO bang do doc
% pha pilot (vi tri pilot neo tai dau doan nen sai so CFO chi nhan voi M block, khong nhan voi
% ca khung), roi chinh vi tri +-win mau theo do dong pha pilot cua ca doan (trung binh qua M
% block nen khong nhap nhang khi ky hieu ke bang pilot, khac max() |mf| tung block).
data_start = length(preamble_ref) + 1; % mau dau tien cua phan du lieu (ngay sau preamble), tinh tu dau preamble
spb = (syms_per_block+1)*sps; % mau/block danh nghia (1 pilot + syms_per_block ky hieu du lieu)
mfo = mf_out(start_idx:end); L = numel(mfo); % cat bo phan truoc preamble: mfo(1) = mau dau preamble; L = so mau con lai
M = 10; win = 2; % M = so block moi doan; win = do lech vi tri toi da thu (+-2 mau)
pilot_idx = zeros(1, num_blocks); cfo_blk = zeros(1, num_blocks); % ket qua: vi tri mau cua pilot va CFO cua tung block
cfo_pre = cfo_hz; % giu lai CFO uoc luong tu preamble de in so sanh
p0 = data_start + round(sps/2) - 1; % vi tri pilot block 1 (so thuc, cong don qua cac doan)
for b0 = 1:M:num_blocks % b0 = block dau tien cua moi doan: 1, 11, 21, ...
    m = min(M, num_blocks - b0 + 1); % so block trong doan nay (doan cuoi co the < M)
    for it = 1:2 % cfo -> vi tri pilot -> cfo
        % Lech tan CFO va lech dong ho mau cung sinh ra tu 1 ty le lech dong ho: song mang
        % Fc den thanh Fc+cfo thi moi khoang thoi gian cung bi co gian theo Fc/(Fc+cfo) = 1+drift.
        drift = -cfo_hz / (Fc + cfo_hz); % ty le lech dong ho mau suy tu CFO (vd -0.003 = -0.3%)
        p = min(round(p0 + (0:m-1)'*spb*(1+drift)), L); % du doan vi tri m pilot trong doan (co bu drift), khong vuot L
        if m >= 3 % can it nhat 3 diem de uoc luong do doc pha tin cay
            % pha tung pilot sau khi: xoay nguoc CFO hien tai, chia pilot_sym (bo pha da biet cua pilot);
            % unwrap noi pha lien tuc (khong nhay 2*pi) de fit duong thang
            ph = unwrap(angle(mfo(p) .* exp(-1j*2*pi*cfo_hz*(p-1)/Fs) / pilot_sym));
            pf = polyfit(p - p(1), ph, 1); % fit ph = pf(1)*(so mau ke tu pilot dau) + pf(2); pf(1) = rad/mau con du
            cfo_hz = cfo_hz + pf(1)*Fs/(2*pi); % pha du +2*pi*d/Fs moi mau -> CFO that = cfo_hz + d
        end
    end
    drift = -cfo_hz / (Fc + cfo_hz); % drift tinh lai tu CFO da tinh chinh
    p = round(p0 + (0:m-1)'*spb*(1+drift)); % vi tri du doan cuoi cung cua m pilot
    best_coh = -1; dbest = 0; % do dong pha tot nhat va do dich tuong ung
    for dd = [0 -1 1 -win win] % 0 truoc: hoa thi giu nguyen vi tri du doan
        pd = min(max(p + dd, 1), L); % dich ca doan di dd mau, kep trong [1, L]
        z = mfo(pd) .* exp(-1j*2*pi*cfo_hz*(pd-1)/Fs); % gia tri pilot da xoay nguoc CFO
        % do dong pha: |tong vector| / tong do dai. = 1 khi moi pilot cung pha (lay mau dung giua
        % ky hieu), nho hon khi lay mau lech lan sang ky hieu ke ben (pha/bien do tan ra)
        coh = abs(sum(z)) / sum(abs(z));
        if coh > best_coh, best_coh = coh; dbest = dd; end % giu do dich cho dong pha lon nhat
    end
    pilot_idx(b0:b0+m-1) = min(max(p + dbest, 1), L); % luu vi tri pilot da chinh cua ca doan
    cfo_blk(b0:b0+m-1) = cfo_hz; % moi block trong doan dung chung CFO cua doan
    p0 = p0 + m*spb*(1+drift) + dbest; % vi tri pilot dau doan sau = tien m block + mang theo phan chinh dbest
end
cfo_hz = median(cfo_blk); % CFO dai dien ca khung (chi de in, giai ma dung cfo_blk)
fprintf('CFO preamble %.2f Hz -> bam theo pilot (min / median / max): %.2f / %.2f / %.2f Hz\n', ...
    cfo_pre, min(cfo_blk), cfo_hz, max(cfo_blk));

%% ===== 7. Can bang pilot + giai dieu che QPSK =====
rx_bits = zeros(1, num_blocks*syms_per_block*2); % 2 bit moi ky hieu QPSK
bit_ptr = 1; % vi tri ghi bit tiep theo trong rx_bits
eq_all = []; % gom moi ky hieu da can bang (de ve chom sao va tinh EVM)
% Lay mau tung ky hieu, can bang kenh tren tung block bang pilot (zero-forcing).
% Pilot la so phuc nen g = bien do * pha kenh; chia eq_sym = mf/g sua ca hai,
% ke ca pha quay do lech pha mang (dieu QPSK can, BPSK chi can dau). CFO cua block
% (cfo_blk) chi con dung de quay not pha tu pilot den tung ky hieu trong block.
block_timing = pilot_idx - (data_start + (0:num_blocks-1)*spb + round(sps/2) - 1); % ponytail: chi de in chan doan
% (block_timing = vi tri pilot tim duoc tru vi tri danh nghia khi khong co lech dong ho)
for blk = 1:num_blocks
    p = pilot_idx(blk); cb = cfo_blk(blk); % vi tri pilot va CFO cua block nay
    drift = -cb / (Fc + cb); % lech dong ho mau cua block
    g = mfo(p) / pilot_sym; % pilot o dau block
    % g = he so kenh r∠θ: mfo(p) = g*pilot_sym, chia pilot_sym (da biet) ra g
    for b = 1:syms_per_block
        idx_c = min(p + b*sps + round(drift*b*sps), L); % drift trong block
        % (ky hieu du lieu thu b nam sau pilot b*sps mau, co gian them theo drift)
        eq_sym = mfo(idx_c) * exp(-1j*2*pi*cb*(idx_c-p)/Fs) / g;
        % ^ xoay nguoc pha CFO tich luy tu pilot den mau nay, roi chia g: bo bien do va pha kenh
        eq_all(end+1) = eq_sym; % chi de ve scatterplot
        rx_bits(bit_ptr)   = real(eq_sym) > 0; % b1 -> I
        rx_bits(bit_ptr+1) = imag(eq_sym) > 0; % b2 -> Q
        bit_ptr = bit_ptr + 2; % sang cap bit tiep theo
    end
end
if num_blocks <= 300 % khung ngan: in lech vi tri pilot tung block
    fprintf('Lech dinh pilot so voi danh nghia tung block (mau): %s\n', mat2str(block_timing));
else % khung dai: chi in dau / giua / cuoi cho gon
    fprintf('Lech dinh pilot so voi danh nghia (mau): dau %d, giua %d, cuoi %d\n', block_timing(1), block_timing(ceil(end/2)), block_timing(end));
end

%% ===== 8. Danh gia: BER, EVM, loi tung block =====
[num_err, ber] = biterr(data_bits, rx_bits); % so bit sai va ty le bit sai so voi bit goc cua Tx
fprintf('CFO uoc luong: %.2f Hz. So bit loi: %d / %d, BER = %.4f\n', ...
    cfo_hz, num_err, numel(data_bits), ber);

% EVM: do do tan cua cac cum sau can bang, min hon BER khi so bit it (BER=0 chi
% noi duoc BER < ~3/so bit). SNR uoc luong = -20*log10(EVM).
ideal = (sign(real(eq_all)) + 1j*sign(imag(eq_all))) / sqrt(2); % diem chom gan nhat
evm = rms(eq_all - ideal) / rms(ideal); % do lech rms so voi diem chom sao ly tuong, chuan hoa theo bien do
fprintf('EVM = %.1f %% (SNR ky hieu ~ %.1f dB)\n', 100*evm, -20*log10(evm));

% ponytail: chan doan - loi trai deu tren cac block hay tang dan ve cuoi frame?
% Tang dan = lech dong ho mau (clock drift) chua duoc bu, chu khong phai CFO/nhieu.
bits_per_block = 2*syms_per_block; % so bit du lieu moi block
block_err = zeros(1, num_blocks); % so bit sai trong tung block
for blk = 1:num_blocks
    idxs = (blk-1)*bits_per_block+1 : blk*bits_per_block; % chi so bit cua block blk
    block_err(blk) = sum(rx_bits(idxs) ~= data_bits(idxs)); % dem bit sai trong block
end
if num_blocks <= 300
    fprintf('Loi tung block (block 1..%d): %s\n', num_blocks, mat2str(block_err));
else
    bad = find(block_err > 0); % cac block co it nhat 1 bit sai
    fprintf('Block co loi: %d / %d (block loi dau tien: %s)\n', numel(bad), num_blocks, mat2str(bad(1:min(1,end))));
end

%% ===== Do thi =====
scatterplot(eq_all); % chom sao sau can bang: tot thi 4 cum gon
title('Ky hieu du lieu sau can bang pilot (mong doi 4 cum o (+-1+-j)/sqrt(2))');
figure; plot(real(rx_bb)); title('Baseband I sau ha tan'); % thanh phan I cua baseband theo mau
