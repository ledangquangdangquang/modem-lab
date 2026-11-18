%% Demo: minh hoa quet tho CFO tren luoi va dinh tuong quan
% Chay truc tiep tren MATLAB/Octave. Khong can Tx.m/Rx.m that.
% a+jb = Acos(phi) +jsin(phi)
clear; clc; close all;

%% Tham so gia lap
Fs = 44100;
sps = 20;                 % mau/ky hieu (dat lon hon 1 de giong thuc te)
cfo_true = 47;             % CFO "that" gia lap (Hz) - so khong tron de thay ro sai so luoi
preamble_bits = [1 0 1 1 0 1 0 0 1 1 0 1 0 0 0 1 1 0 1 0]; % preamble 20 bit gia lap
preamble_sym = 2*preamble_bits - 1;

%% Tao tin hieu preamble baseband ly tuong (chua CFO), roi ap CFO that vao
preamble_ref = repelem(preamble_sym, sps).'; % tin hieu preamble sach, dung de tuong quan
n = (0:length(preamble_ref)-1)';
rx_clean = preamble_ref .* exp(1j*2*pi*cfo_true*n/Fs); % gia lap tin hieu THU duoc, da bi CFO lam xoay pha

% Nhieu nen it, de thay ro hieu ung CFO chu khong bi nhieu che lap
noise = 0.05*(randn(size(rx_clean)) + 1j*randn(size(rx_clean)));
rx_bb = rx_clean + noise;

%% Quet tho CFO tren luoi, luu lai dinh tuong quan cua TUNG gia tri thu
cfo_grid = -500:15:500;
peak_per_cfo = zeros(size(cfo_grid));

for i = 1:length(cfo_grid)
    cfo_try = cfo_grid(i);
    derot = rx_bb .* exp(-1j*2*pi*cfo_try*n/Fs); % gia dinh CFO = cfo_try, xoay nguoc lai
    c = xcorr(derot, preamble_ref);
    peak_per_cfo(i) = max(abs(c));
end

[best_peak, idx_best] = max(peak_per_cfo);
best_cfo_grid = cfo_grid(idx_best);

fprintf('CFO that (gia lap)      = %.2f Hz\n', cfo_true);
fprintf('CFO gan nhat tren luoi   = %d Hz (buoc luoi 15Hz)\n', best_cfo_grid);
fprintf('Sai so do gioi han luoi  = %.2f Hz\n', abs(best_cfo_grid - cfo_true));
fprintf('Dinh tuong quan cao nhat = %.3f (tai CFO = %d Hz)\n', best_peak, best_cfo_grid);

%% Ve do thi: dinh tuong quan thay doi the nao theo tung gia tri CFO thu trong luoi
figure('Position',[100 100 900 400]);

subplot(1,2,1);
plot(cfo_grid, peak_per_cfo, '-o', 'LineWidth', 1.5);
hold on;
xline(cfo_true, 'r--', 'CFO that', 'LineWidth', 1.5);
xline(best_cfo_grid, 'g:', 'CFO chon tren luoi', 'LineWidth', 1.5);
xlabel('CFO thu (Hz)'); ylabel('Dinh tuong quan |xcorr|');
title('Do thi dinh tuong quan theo tung CFO thu trong luoi');
grid on; legend('Dinh tuong quan','CFO that','CFO chon');

% So sanh truc quan: tuong quan tot nhat (dung CFO gan dung) vs tuong
% quan khi khong bu gi ca (cfo_try = 0) de thay ro CFO lam hong tuong quan
derot_best = rx_bb .* exp(-1j*2*pi*best_cfo_grid*n/Fs);
[c_best, lags_best] = xcorr(derot_best, preamble_ref);

derot_zero = rx_bb; % khong bu CFO (cfo_try = 0)
[c_zero, lags_zero] = xcorr(derot_zero, preamble_ref);

subplot(1,2,2);
plot(lags_zero, abs(c_zero), 'r-', 'LineWidth', 1.2); hold on;
plot(lags_best, abs(c_best), 'b-', 'LineWidth', 1.2);
xlabel('Do tre (lag, mau)'); ylabel('|Tuong quan|');
title('So sanh dinh tuong quan: khong bu CFO vs bu bang luoi');
legend('Khong bu CFO (cfo=0)', sprintf('Bu CFO=%d Hz (tot nhat tren luoi)', best_cfo_grid));
grid on;

sgtitle('Minh hoa quet tho CFO tren luoi: tim CFO gan dung nhat de dinh tuong quan cao nhat');
