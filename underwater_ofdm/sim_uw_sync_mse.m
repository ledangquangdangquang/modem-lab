%% sim_uw_sync_mse.m - Mo phong thuan MATLAB (khong can phan cung) de kiem
% tra uw_sync.m / uw_sync_reference.m dung cong thuc trong bai bao truoc
% khi dung am thanh that. Muc tieu: tai lap dang hinh Fig.8 cua bai bao
% (MSE vi tri dong bo theo SNR, scheme de xuat vs scheme tham chieu).
%
% ponytail: ban dau chi cong AWGN (khong co h(k)) thi ca 2 scheme thanh
% cong 100% ngay ca o SNR=1dB - khong khop voi ty le that bai 16-30% bai
% bao bao cao cho scheme tham chieu. Ly do nhieu kha nang: cong thuc (1)
% cua bai bao la y(k)=h(k)*x(k)+n(k) - CO kenh da duong h(k), khong chi la
% nhieu cong. Da duong lam GI dau va GI cuoi trong tin hieu thu KHONG CON
% GIONG HET nhau nua (bi nhoe khac nhau do cac tia phan xa), pha dung gia
% dinh cot loi ma P(i)/R(i) dua vao - day moi la thu pha vo scheme tham
% chieu, khong phai chi rieng nhieu trang. Ham lam_kenh_da_duong() duoi
% day them buoc nay; bat/tat qua USE_MULTIPATH de so sanh truc tiep.

NFFT = 1024;
nGI = 512;
K = 2*NFFT + nGI + 1; % do dai 1 ky hieu OFDM ke ca GI (~2561 mau nhu bai bao)

SNR_list_db = 1:0.5:4;      % giong khoang SNR bai bao khao sat
num_symbols_in_frame = 4;   % 4 ky hieu OFDM lien tiep (nhu bai bao)
noise_pre_syms = 3;         % truoc do la khoang tuong duong 3 ky hieu toan nhieu
num_trials = 200;
fail_tol = K/2;             % ponytail: |loi| > nua ky hieu tinh la "that bai dong bo"
USE_MULTIPATH = true;       % tat de so sanh lai truong hop AWGN thuan (ban dau)
max_delay_frac = 1.0;       % do tre da duong toi da = max_delay_frac * nGI (mau)

mse_proposed = zeros(size(SNR_list_db));
mse_reference = zeros(size(SNR_list_db));
fail_rate_proposed = zeros(size(SNR_list_db));
fail_rate_reference = zeros(size(SNR_list_db));

for si = 1:numel(SNR_list_db)
    snr_db = SNR_list_db(si);
    err_p = zeros(num_trials, 1);
    err_r = nan(num_trials, 1);
    n_fail_p = 0;
    n_fail_r = 0;

    for t = 1:num_trials
        sig = [];
        for s = 1:num_symbols_in_frame
            c = qammod(randi([0 3], 1, NFFT), 4) / sqrt(2); % QPSK, chuan hoa cong suat
            sig = [sig, build_ofdm_symbol(c, nGI)]; %#ok<AGROW>
        end
        true_start = noise_pre_syms*K + 1; % vi tri GI dau tien (tia truc tiep) trong y

        if USE_MULTIPATH
            h = lam_kenh_da_duong(nGI, max_delay_frac);
            sig_ch = conv(sig, h); % dai hon sig do duoi phan xa - tia truc tiep van o dung true_start
        else
            sig_ch = sig;
        end

        pre_noise = zeros(1, noise_pre_syms*K);
        y_clean = [pre_noise, sig_ch];

        sig_power = mean(sig_ch.^2);
        snr_lin = 10^(snr_db/10);
        noise_power = sig_power / snr_lin;
        y = y_clean + sqrt(noise_power) * randn(size(y_clean));

        idx_p = uw_sync(y, NFFT, nGI, 0.05);
        idx_r = uw_sync_reference(y, NFFT, nGI);

        err_p(t) = (idx_p - true_start)^2;
        if abs(idx_p - true_start) > fail_tol
            n_fail_p = n_fail_p + 1;
        end

        if isnan(idx_r)
            n_fail_r = n_fail_r + 1;
        else
            err_r(t) = (idx_r - true_start)^2;
            if abs(idx_r - true_start) > fail_tol
                n_fail_r = n_fail_r + 1;
            end
        end
    end

    mse_proposed(si) = mean(err_p);
    mse_reference(si) = mean(err_r, 'omitnan');
    fail_rate_proposed(si) = 100 * n_fail_p / num_trials;
    fail_rate_reference(si) = 100 * n_fail_r / num_trials;
end

figure;
plot(SNR_list_db, mse_proposed, '-ks', SNR_list_db, mse_reference, '-ro');
xlabel('SNR (dB)'); ylabel('MSE');
legend('Proposed scheme', 'Reference scheme', 'Location', 'best');
title('Tai lap Fig.8: MSE vi tri dong bo theo SNR');
grid on;

fprintf('USE_MULTIPATH = %d, max_delay_frac = %.2f\n', USE_MULTIPATH, max_delay_frac);
fprintf('SNR (dB):            %s\n', mat2str(SNR_list_db));
fprintf('MSE proposed:         %s\n', mat2str(mse_proposed, 4));
fprintf('MSE reference:        %s\n', mat2str(mse_reference, 4));
fprintf('Ty le that bai (%%) proposed:  %s\n', mat2str(fail_rate_proposed, 3));
fprintf('Ty le that bai (%%) reference: %s\n', mat2str(fail_rate_reference, 3));
fprintf(['Ky vong (theo bai bao): reference that bai manh duoi ~3dB (bai bao ' ...
    'bao cao 16-30%% that bai o 3-4dB); proposed van khoa duoc o 1-2dB (MSE ' ...
    'cao hon) nhung hoi kem hon reference o SNR cao (danh doi do tre tich luy ' ...
    'qua cac buoc tuong quan).\n']);

function h = lam_kenh_da_duong(nGI, max_delay_frac)
%LAM_KENH_DA_DUONG Kenh da duong tong hop: 1 tia truc tiep (h(1)=1, do tre 0)
% + 1-3 tia phan xa co do tre ngau nhien trong [1, max_delay_frac*nGI] mau
% va bien do 0.3-0.7 lan tia truc tiep, dau ngau nhien. Chuan hoa nang
% luong tong ve 1 de SNR sau kenh van co nghia so sanh giua cac trial.
% ponytail: day la kenh TONG HOP don gian de kiem tra gia thuyet "da duong
% pha vo scheme tham chieu", KHONG phai kenh am hoc duoi nuoc do dac trung
% (chua co so lieu do dac thuc te de hieu chinh cac tham so nay).
max_delay = max(1, round(max_delay_frac * nGI));
n_reflect = randi([1 3]);
h = zeros(1, max_delay + 1);
h(1) = 1;
for k = 1:n_reflect
    delay = randi([1, max_delay]);
    gain = (0.3 + 0.4*rand()) * sign(randn());
    h(delay + 1) = h(delay + 1) + gain;
end
h = h / sqrt(sum(h.^2));
end
