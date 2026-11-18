%% Plot_qpsk.m - Ve cac buoc trung gian theo thoi gian (chay SAU Rx_qpsk.m)
% Can trong workspace: tx_signal, rx_raw, rx_bb, mf_out, eq_all, data_bits, Fs (Rx_qpsk.m de lai het).
tt_tx = (0:numel(tx_signal)-1)/Fs;   % tx co pad 0.5 s dau/cuoi, do dai khac rx -> truc rieng
tt_rx = (0:numel(rx_raw)-1)/Fs;

%% Hinh 1: tu song thu den sau loc phoi hop (cung truc thoi gian, cung do dai rx_raw)
figure;
ax(1) = subplot(4,1,1); plot(tt_tx, tx_signal);   title('Bên phát: tx\_signal');
ax(2) = subplot(4,1,2); plot(tt_rx, rx_raw);      title('Bên thu: rx\_raw');
ax(3) = subplot(4,1,3); plot(tt_rx, real(rx_bb), tt_rx, real(mf_out), 'LineWidth', 1.2);
title('Phần thực: rx\_bb (I/2 + gợn 2Fc) và mf\_out (gợn đã triệt)'); legend('rx\_bb', 'mf\_out');
ax(4) = subplot(4,1,4); plot(tt_rx, imag(rx_bb), tt_rx, imag(mf_out), 'LineWidth', 1.2);
title('Phần ảo: rx\_bb (Q/2 + gợn 2Fc) và mf\_out'); legend('rx\_bb', 'mf\_out');
xlabel('Thời gian (s)');
linkaxes(ax(2:4), 'x');   % zoom 3 hinh thu cung luc; tx co truc rieng vi do tu luc bat dau phat

%% Hinh 2: ky hieu sau pilot ZF so voi ky hieu Tx ly tuong (theo thu tu ky hieu du lieu)
ideal = ((2*data_bits(1:2:end)-1) + 1j*(2*data_bits(2:2:end)-1)) / sqrt(2);  % cung anh xa Gray voi Tx_qpsk.m
k = 1:min(60, numel(eq_all));         % xem 60 ky hieu dau cho ro
figure;
subplot(3,1,1); plot(k, real(ideal(k)), 'o-', k, real(eq_all(k)), 'x-'); title('I: Tx lý tưởng và Rx sau ZF'); legend('Tx', 'Rx');
subplot(3,1,2); plot(k, imag(ideal(k)), 'o-', k, imag(eq_all(k)), 'x-'); title('Q: Tx lý tưởng và Rx sau ZF'); legend('Tx', 'Rx');
subplot(3,1,3); plot(k, abs(eq_all(k) - ideal(k)), '.-'); title('Sai số |Rx − Tx| từng ký hiệu (EVM)'); xlabel('Ký hiệu dữ liệu số');

%% Hinh 3: pho tan so (pwelch, hai phia, tam o 0 Hz) cua tx_signal, rx_raw, rx_bb, mf_out
sigs  = {tx_signal(:), rx_raw(:), rx_bb(:), mf_out(:)};
names = {'tx\_signal (đỉnh ±Fc)', 'rx\_raw (đỉnh ±Fc)', 'rx\_bb (I/Q ở 0 Hz, ảnh ở −2Fc)', 'mf\_out (ảnh −2Fc đã giảm)'};
figure;
for i = 1:4
    [P, f] = pwelch(sigs{i}, 4096, [], 4096, Fs, 'centered');
    axf(i) = subplot(2,2,i); plot(f, 10*log10(P + eps)); grid on;
    title(names{i}); xlabel('Tần số (Hz)'); ylabel('dB/Hz'); xlim([-Fs/2 Fs/2]);
end
linkaxes(axf, 'x');
