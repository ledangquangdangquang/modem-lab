%% Rx_qpsk_air.m - Thu QPSK qua KHONG KHI (loa dien thoai -> mic laptop), can bang mien tan so (ZP)
% Ban sao cua qam/Rx_qam.m (khong dong vao Rx_qam.m). Can chay Tx_qpsk_air.m truoc.
% Luon nap lai tx_params_qpsk_air.mat (khong dung bien con trong workspace).
%
% Chuoi xu ly:
%   1-5. lay rx_raw -> ha tan -> integrate-and-dump -> dong bo preamble + CFO tho (luoi CFO min, xem buoc 4)
%   6. Tung block (bang sang che, Hinh 4, nhung 1 nhanh phuc thay vi 2 nhanh F0/F1):
%      a. lay mau giua ky hieu cua ca block (bu lech dong ho), xoay nguoc CFO
%      b. CFO du tho: lech pha giua 2 nua tieu de (bat ca CFO nhay giua khung)
%      c. H = FFT(tieu de + 0 thu duoc) / FFT(tieu de)          (buoc 4-6)
%         + chi giu Lz he so dau cua h = ifft(H) (bo nhieu, them so voi bang sang che)
%      d. du lieu = IFFT( FFT(du lieu + 0) * conj(H) / (|H|^2 + nhieu) ), cat duoi (buoc 6-7)
%         MMSE thay cho chia thang Y/H: o tan so kenh bi lom (|H| ~ 0) chia thang khuech dai nhieu
%      e. pilot: do doc pha -> CFO du, bien do trung binh -> chia ra (thay buoc 9)
%      (b-e lap: b mot lan, c-e hai lan, moi lan CFO tot hon)
%   7. Cat quyet dinh M-QAM, BER, EVM, ve do thi
%
% Truoc khi thu that: doi RX_SOURCE thanh 'loopback' (BER phai = 0) roi 'sim'.

load(fullfile(fileparts(mfilename('fullpath')), 'tx_params_qpsk_air.mat'));
rx_wav = 'rx_air_qpsk.wav';

%% ===== 1. Chon nguon tin hieu thu =====
RX_SOURCE = 'record'; % 'loopback' = tin hieu phat lam tin hieu thu (BER phai = 0)
                   % 'sim'      = phong mo phong: vang + lech dong ho + nhieu (tham so ngay duoi)
                   % 'record'   = thu that bang mic laptop (loa dien thoai phat tx_air_qpsk.wav)
                   % 'file'     = doc lai rx_air_qpsk.wav da thu truoc do

if strcmp(RX_SOURCE, 'loopback')
    rx_raw = tx_signal(:);
elseif strcmp(RX_SOURCE, 'sim')
    % shortcut: phong TU DAT, khong phai do that - chi de thu bo can bang truoc khi co ban thu.
    % Tia truc tiep + phan xa mat ban + duoi vang ngau nhien giam dan; lech dong ho 0.3%
    % (1003/1000) nhu dien thoai that. Co ban thu that thi tin ban thu, khong tin mo phong nay.
    sim_echo_ms  = 0.8;  sim_echo_gain = 0.5; % phan xa mat ban: tre (ms), bien do so voi tia truc tiep
    sim_rt60     = 0.3;           % thoi gian vang cua phong (s): duoi vang giam 60 dB
    sim_drr_db   = 10;            % tia truc tiep manh hon tong duoi vang bao nhieu dB (loa cang gan mic cang lon)
    sim_snr_db   = 15;            % SNR dai thong (ca dai 0..Fs/2)
    n_tail = round(sim_rt60*Fs);
    h_sim = randn(n_tail,1) .* 10.^(-3*(0:n_tail-1)'/n_tail); % duoi vang: nhieu trang * duong bao mu
    h_sim(1:round(0.002*Fs)) = 0;                             % 2 ms dau chi co tia truc tiep + phan xa ban
    h_sim = h_sim/norm(h_sim) * 10^(-sim_drr_db/20);
    h_sim(1) = 1; h_sim(round(sim_echo_ms*Fs/1000) + 1) = sim_echo_gain;
    rx_raw = resample(conv(tx_signal(:), h_sim), 1003, 1000);
    p_sig = mean(tx_signal(tx_signal ~= 0).^2); % cong suat tia truc tiep luc co tin hieu (bo khoang lang)
    rx_raw = rx_raw + sqrt(p_sig / 10^(sim_snr_db/10)) * randn(size(rx_raw));
elseif strcmp(RX_SOURCE, 'file')
    rx_raw = audioread(fullfile(fileparts(mfilename('fullpath')), rx_wav));
else
    record_time = numel(tx_signal)/Fs + 3; % do dai file phat + 3 s du tre khi bam phat
    rec = audiorecorder(Fs, 16, 1); % thiet bi mac dinh; sai thiet bi thi xem audiodevinfo(1) (nhu Rx_qpsk.m)
    disp('Bat dau phat tx_air_qpsk.wav bang loa dien thoai ngay bay gio...');
    recordblocking(rec, record_time);
    rx_raw = getaudiodata(rec);
    fprintf('Muc tin hieu thu duoc: peak=%.4f, rms=%.4f (gan 0 nghia la thu nham thiet bi hoac loa qua xa mic; peak ~1 = bi cat dinh, giam am luong)\n', ...
        max(abs(rx_raw)), rms(rx_raw));
    audiowrite(fullfile(fileparts(mfilename('fullpath')), rx_wav), rx_raw, Fs); % ponytail: de soi lai neu decode sai
end

%% ===== 2-3. Ha tan + loc phoi hop (giong Rx_qpsk.m) =====
t = (0:length(rx_raw)-1)'/Fs;
rx_bb = rx_raw .* exp(-1j*2*pi*Fc*t);              % dich pho tu Fc ve 0 Hz
% Loc bo anh o 2*Fc. Rx_qpsk.m de I&D lam viec nay, nhung I&D chi triet tieu 2*Fc khi cua so
% trung khit 1 ky hieu; tia tre / lech dong ho lam cua so vat qua bien ky hieu -> anh lot qua
% thanh thanh phan conj(x) ma bo can bang khong go duoc (san EVM ~4% du khong nhieu).
% Loc FIR doi xung + 'same' -> khong tre; meo cua no nam trong H, bo can bang tu bu.
% ponytail: loopback con EVM ~1%: xung vuong co pho rat rong, duoi sinc cua anh 2*Fc roi vao
% 0..Fc, khong loc duoc (khong loc thi I&D triet tieu dung trong loopback ly tuong, nhung kenh co
% tia tre thi san ~4%). Sua tan goc: dang xung gioi han bang (RRC) o Tx.
rx_bb = conv(rx_bb, fir1(sps, Fc/(Fs/2)).', 'same'); % dai sps+1 mau = +-0.5 ky hieu, ngan hon mg
mf_out = conv(rx_bb, ones(sps,1)/sps, 'same');     % integrate-and-dump

%% ===== 4. Dong bo khung + CFO tho (tuong quan preamble, quet luoi CFO) =====
% Khac Rx_qam.m: buoc luoi tinh theo do dai preamble, khong co dinh 15 Hz. Tuong quan ca preamble
% (T = 50 ky hieu = 100 ms o 500 baud) mat ~36% bien do khi CFO lech 1/(2T) = 5 Hz va trieu tieu khi
% lech 1/T = 10 Hz -> luoi 15 Hz lot mat CFO that. Ban thu that dau tien (CFO ~ 0 Hz) da khoa nham
% vao giua khung vi vay (BER 0.5). Buoc = 1/(4T) -> lech toi da 1/(8T), mat <= 3% bien do.
% Pham vi +-60 Hz = lech dong ho +-0.75% (dien thoai da do: 0.3% -> 24 Hz).
preamble_sym = 2*preamble_bits - 1;
preamble_ref = repelem(preamble_sym, sps).';
n_full = (0:length(mf_out)-1)';
cfo_step = baud_rate / (4*numel(preamble_bits)); % 2.5 Hz o 500 baud
best_peak = -1;
for cfo_try = -60:cfo_step:60
    derot = mf_out .* exp(-1j*2*pi*cfo_try*n_full/Fs);
    [c_try, lags_try] = xcorr(derot, preamble_ref);
    [pv, pk_try] = max(abs(c_try));
    if pv > best_peak
        best_peak = pv; lags = lags_try; pk = pk_try; cfo_hz = cfo_try;
    end
end
start_idx = lags(pk) + 1; % mau dau preamble trong mf_out
if start_idx < 1 || start_idx + length(preamble_ref) - 1 > length(mf_out)
    error('Khong tim thay preamble trong tin hieu thu duoc.');
end
% CFO tho = diem luoi thang (sai <= cfo_step/2), tieu de tung block tinh chinh tiep o buoc 6b.
% Khong dung lech pha giua 2 ky hieu preamble lien tiep nhu Rx_qpsk.m: qua khong khi cac ky hieu
% preamble chong len nhau do da duong, pha tung ky hieu tan +-40 do -> ra 13 Hz khi CFO that ~ 0.
cfo_pre = cfo_hz;
fprintf('Dong bo: khung bat dau tai %.3f s, CFO tho %.1f Hz\n', (start_idx-1)/Fs, cfo_hz);

%% ===== 6. Tung block: CFO du -> uoc luong kenh FFT -> can bang MMSE -> pilot =====
% Cua so 1 block (ky hieu, tinh tu dau cua so): [mg ky hieu 0 truoc | tieu de | 0 | du lieu | 0]
% cat lui mg ky hieu: dong bo khoa vao tia MANH nhat, tia den som hon no (neu co) van nam trong
% cua so. Doi lai trai tre cho phep con [-mg, Lz-mg-1] ky hieu quanh tia manh nhat.
% Vi cua so tieu de va du lieu cung lui mg, H tu tieu de da chua san do lech nay -> ifft ra
% du lieu bat dau dung tai phan tu 1.
Np = numel(preamble_bits);
Lb = Lh + Lz + Ld + Lz;          % ky hieu/block
mg = 2;                          % ky hieu lui cua so
win = 2;                         % do lech vi tri toi da thu moi block (+-mau), nhu Rx_qpsk.m
Lf = max(Lh, Ld) + Lz;           % do dai FFT (buoc 1 bang sang che)
XP = fft(hdr_sym(:), Lf);        % buoc 4-5: tieu de da biet, dem 0 len Lf
n_win = (0:Lb-1)';               % chi so ky hieu trong cua so
h2 = floor(Lh/2);                % nua tieu de (cho buoc 6b)
ip = 1 + (0:n_sub-1)'*(syms_per_sub+1); % vi tri pilot trong phan du lieu
idat = setdiff((1:Ld)', ip);            % vi tri ky hieu du lieu
k_bits = log2(M_qam);
n_dsym = n_sub*syms_per_sub;     % ky hieu du lieu moi block

mfo = mf_out(start_idx:end); Lm = numel(mfo); % mfo(1) = mau dau preamble
p0 = (Np + Lz - mg)*sps + round(sps/2);       % mau giua ky hieu dau cua cua so block 1
eq_all = zeros(num_blocks*n_dsym, 1);
cfo_blk = zeros(1, num_blocks); block_timing = zeros(1, num_blocks);
for blk = 1:num_blocks
    for it = 1:3 % 1: CFO du tu tieu de; 2-3: can bang + CFO du tu pilot
        drift = -cfo_hz / (Fc + cfo_hz); % lech dong ho mau suy tu CFO (giai thich o Rx_qpsk.m)
        sp = sps*(1 + drift);            % khoang cach mau thuc giua 2 ky hieu
        best_c = -1;
        for dd = [0 -1 1 -win win] % chinh vi tri theo tuong quan tieu de (0 truoc: hoa thi giu)
            q = min(max(round(p0 + dd + (mg:mg+Lh-1)'*sp), 1), Lm);
            c = abs(sum(mfo(q) .* exp(-1j*2*pi*cfo_hz*(q-q(1))/Fs) .* conj(hdr_sym(:))));
            if c > best_c, best_c = c; dbest = dd; end
        end
        % a. mau giua ky hieu ca block, xoay nguoc CFO (pha tinh tu dau cua so; pha co dinh H tu bu)
        q = min(max(round(p0 + dbest + n_win*sp), 1), Lm);
        r = mfo(q) .* exp(-1j*2*pi*cfo_hz*(q-q(1))/Fs);
        if it == 1
            % b. tuong quan tung nua tieu de voi ban da biet: 2 so phuc cung kenh, lech pha nhau
            % do CFO du trong h2 ky hieu -> bat duoc |CFO du| < baud/(2*h2) (~ 33 Hz o 1000 baud)
            c1 = sum(r(mg+(1:h2)) .* conj(hdr_sym(1:h2).'));
            c2 = sum(r(mg+h2+(1:h2)) .* conj(hdr_sym(h2+1:2*h2).'));
            cfo_hz = cfo_hz + angle(c2*conj(c1)) / (2*pi*h2*sp/Fs);
            continue
        end
        rh = r(1:Lh+Lz); rd = r(Lh+Lz+1:end);   % buoc 2: tieu de+0 | du lieu+0
        H = fft(rh, Lf) ./ XP;                   % buoc 6: H = HP/XP
        hh = ifft(H); hh(Lz+1:end) = 0; H = fft(hh); % kenh khong dai hon Lz -> bo phan con lai (chi la nhieu)
        res = ifft(XP .* H); res = rh - res(1:Lh+Lz); % phan du cua tieu de = nhieu
        nv = mean(abs(res).^2) + eps;                 % ponytail: phuong sai nhieu, du lieu co cong suat ~1
        xd = ifft(conj(H) .* fft(rd, Lf) ./ (abs(H).^2 + nv)); % MMSE
        xd = xd(1:Ld);                           % buoc 7: cat duoi
        % e. pilot sau can bang: g(n) = A∠(phi0 + w*n). w = CFO du, A = bien do (MMSE lam nho bien do)
        g = xd(ip) / pilot_sym;
        pf = polyfit(ip - 1, unwrap(angle(g)), 1); % pf(1) = rad/ky hieu
        cfo_hz = cfo_hz + pf(1) / (2*pi*sp/Fs);
    end
    xe = xd ./ (mean(abs(g)) * exp(1j*(pf(2) + pf(1)*((1:Ld)' - 1))));
    eq_all((blk-1)*n_dsym + (1:n_dsym)) = xe(idat);
    cfo_blk(blk) = cfo_hz;
    block_timing(blk) = round(p0 + dbest - ((Np + Lz - mg + (blk-1)*Lb)*sps + round(sps/2)));
    p0 = p0 + dbest + Lb*sp; % cua so block sau
end
fprintf('CFO preamble %.2f Hz -> bam theo block (min / median / max): %.2f / %.2f / %.2f Hz\n', ...
    cfo_pre, min(cfo_blk), median(cfo_blk), max(cfo_blk));
fprintf('Lech vi tri block so voi danh nghia (mau): dau %d, giua %d, cuoi %d\n', ...
    block_timing(1), block_timing(ceil(end/2)), block_timing(end));

%% ===== 7. Cat quyet dinh M-QAM, BER, EVM =====
rx_bits = qamdemod(eq_all, M_qam, 'gray', 'OutputType', 'bit', 'UnitAveragePower', true).';
[num_err, ber] = biterr(data_bits, rx_bits);
fprintf('%d-QAM: so bit loi (truoc sua loi) %d / %d, BER = %.2e\n', M_qam, num_err, numel(data_bits), ber);
% Giai ma Reed-Solomon (Tx_qpsk_air.m da ma hoa: rs_k byte tin -> rs_n byte). So "bit loi" o tren la
% TRUOC sua loi (bit len song); dong duoi la SAU sua loi, so voi bit tin goc msg_bits.
% .mat cu (truoc khi co ma sua loi, xem truoc_fec/) khong co rs_k -> bo qua.
if exist('rs_k', 'var')
    rx_bytes = 2.^(7:-1:0) * reshape(rx_bits, 8, []);
    [dec, n_fix] = rsdec(gf(rx_bytes, 8), rs_n, rs_k); % n_fix = so byte da sua, -1 = qua kha nang sua
    dec_bits = reshape(rem(floor(double(dec.x) ./ 2.^(7:-1:0)'), 2), 1, []);
    msg_err = sum(dec_bits ~= msg_bits);
    if n_fix < 0
        fprintf('Reed-Solomon(%d,%d): QUA %d byte sai, khong sua duoc. Bit tin sai: %d / %d\n', ...
            rs_n, rs_k, (rs_n-rs_k)/2, msg_err, numel(msg_bits));
    else
        fprintf('Reed-Solomon(%d,%d): da sua %d byte (toi da %d). Bit tin sai sau sua: %d / %d\n', ...
            rs_n, rs_k, n_fix, (rs_n-rs_k)/2, msg_err, numel(msg_bits));
    end
end
ideal = qammod(rx_bits(:), M_qam, 'gray', 'InputType', 'bit', 'UnitAveragePower', true); % diem chom sao gan nhat
evm = rms(eq_all - ideal) / rms(ideal);
fprintf('EVM = %.1f %% (SNR ky hieu ~ %.1f dB)\n', 100*evm, -20*log10(evm));
block_err = sum(reshape(rx_bits ~= data_bits, [], num_blocks), 1); % bit sai tung block
fprintf('Loi tung block: %s\n', mat2str(block_err));

%% ===== Do thi =====
scatterplot(eq_all);
title(sprintf('%d-QAM sau can bang MMSE + pilot', M_qam));
figure; stem(0:Lz-1, abs(hh(1:Lz)));
xlabel('tre (ky hieu, tinh tu dau cua so = tia manh nhat - mg)'); ylabel('|h|');
title('Dap ung kenh uoc luong tu tieu de (block cuoi)');
