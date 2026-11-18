"""Plot_qpsk.py - ban Python cua Plot_qpsk.m: ve cac buoc trung gian theo thoi gian.

    uv run Plot_qpsk.py [loopback|file|record]   # chay Rx_qpsk.py (mac dinh 'file') roi ve 3 hinh

Khac Plot_qpsk.m: Python khong co workspace chung, nen file nay tu goi rx_qpsk() truoc.
"""
import sys
import numpy as np
import matplotlib.pyplot as plt
from scipy.signal import welch
from Rx_qpsk import rx_qpsk

r = rx_qpsk(sys.argv[1] if len(sys.argv) > 1 else 'file')
Fs, tx_signal, rx_raw, rx_bb, mf_out, eq_all, data_bits = \
    (r[k] for k in ('Fs', 'tx_signal', 'rx_raw', 'rx_bb', 'mf_out', 'eq_all', 'data_bits'))
tt_tx = np.arange(len(tx_signal)) / Fs  # tx co pad 0.5 s dau/cuoi, do dai khac rx -> truc rieng
tt_rx = np.arange(len(rx_raw)) / Fs

# Hinh 1: tu song thu den sau loc phoi hop
fig, ax = plt.subplots(4, 1)
ax[0].plot(tt_tx, tx_signal); ax[0].set_title('Bên phát: tx_signal')
ax[1].plot(tt_rx, rx_raw); ax[1].set_title('Bên thu: rx_raw')
ax[2].plot(tt_rx, rx_bb.real, tt_rx, mf_out.real, lw=1.2)
ax[2].set_title('Phần thực: rx_bb (I/2 + gợn 2Fc) và mf_out (gợn đã triệt)'); ax[2].legend(['rx_bb', 'mf_out'])
ax[3].plot(tt_rx, rx_bb.imag, tt_rx, mf_out.imag, lw=1.2)
ax[3].set_title('Phần ảo: rx_bb (Q/2 + gợn 2Fc) và mf_out'); ax[3].legend(['rx_bb', 'mf_out'])
ax[3].set_xlabel('Thời gian (s)')
ax[2].sharex(ax[1]); ax[3].sharex(ax[1])  # zoom 3 hinh thu cung luc
fig.tight_layout()

# Hinh 2: ky hieu sau pilot ZF so voi ky hieu Tx ly tuong
ideal = ((2 * data_bits[0::2] - 1) + 1j * (2 * data_bits[1::2] - 1)) / np.sqrt(2)
k = np.arange(1, min(60, len(eq_all)) + 1)  # 60 ky hieu dau
fig, ax = plt.subplots(3, 1)
ax[0].plot(k, ideal[k - 1].real, 'o-', k, eq_all[k - 1].real, 'x-'); ax[0].set_title('I: Tx lý tưởng và Rx sau ZF'); ax[0].legend(['Tx', 'Rx'])
ax[1].plot(k, ideal[k - 1].imag, 'o-', k, eq_all[k - 1].imag, 'x-'); ax[1].set_title('Q: Tx lý tưởng và Rx sau ZF'); ax[1].legend(['Tx', 'Rx'])
ax[2].plot(k, np.abs(eq_all[k - 1] - ideal[k - 1]), '.-'); ax[2].set_title('Sai số |Rx − Tx| từng ký hiệu (EVM)')
ax[2].set_xlabel('Ký hiệu dữ liệu số')
fig.tight_layout()

# Hinh 3: pho (nhu pwelch(..., 4096, [], 4096, Fs, 'centered'): Hamming, chong 50%, hai phia)
names = ['tx_signal (đỉnh ±Fc)', 'rx_raw (đỉnh ±Fc)', 'rx_bb (I/Q ở 0 Hz, ảnh ở −2Fc)', 'mf_out (ảnh −2Fc đã giảm)']
fig, ax = plt.subplots(2, 2, sharex=True)
for a, s, name in zip(ax.ravel(), (tx_signal, rx_raw, rx_bb, mf_out), names):
    f, Pxx = welch(s, Fs, window='hamming', nperseg=4096, nfft=4096, detrend=False, return_onesided=False)
    a.plot(np.fft.fftshift(f), 10 * np.log10(np.fft.fftshift(Pxx) + np.finfo(float).eps)); a.grid(True)
    a.set_title(name); a.set_xlabel('Tần số (Hz)'); a.set_ylabel('dB/Hz'); a.set_xlim(-Fs / 2, Fs / 2)
fig.tight_layout()
plt.show()
