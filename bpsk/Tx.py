"""Tx.py - ban Python cua Tx.m: sinh khung 2-PAM (preamble + pilot moi 10 bit), ghi tx_cable.wav + tx_params.mat.

Khac Tx.m: ghi file canh file .py (khong phai thu muc hien tai). .mat doc duoc bang ca Rx.m lan Rx.py.
Chu y: ghi de tx_params.mat -> ban thu rx_debug.wav cu khong giai ma duoc nua (BER~0.5).
"""
import os
import numpy as np
from scipy.io import wavfile, savemat

D = os.path.dirname(os.path.abspath(__file__))

Fs = 48000.0        # sample rate (float: .mat luu double nhu MATLAB)
Fc = 8000.0         # tan so mang
baud_rate = 1000.0  # toc do ky hieu
sps = int(Fs / baud_rate)  # mau/ky hieu (48)

bits_per_block = 10
num_blocks = 20
pilot_val = 1.0     # bit pilot da biet, co dinh o dau moi block

rng = np.random.default_rng()
preamble_bits = rng.integers(0, 2, 50).astype(float)  # chuoi biet truoc de dong bo + uoc luong CFO
data_bits = rng.integers(0, 2, num_blocks * bits_per_block).astype(float)

frame_bits = np.hstack([np.full((num_blocks, 1), pilot_val),
                        data_bits.reshape(num_blocks, bits_per_block)]).ravel()  # [pilot, 10 bit] x num_blocks
tx_bits = np.concatenate([preamble_bits, frame_bits])

symbols = 2 * tx_bits - 1             # 0->-1, 1->+1
baseband = np.repeat(symbols, sps)    # xung vuong, integrate-and-dump o Rx se khop
t = np.arange(len(baseband)) / Fs
passband = baseband * np.cos(2 * np.pi * Fc * t)

pad = np.zeros(round(0.5 * Fs))       # khoang lang dau/cuoi cho de bat dau ghi am
tx_signal = np.concatenate([pad, passband, pad])
tx_signal = 0.9 * tx_signal / np.max(np.abs(tx_signal))

wavfile.write(os.path.join(D, 'tx_cable.wav'), int(Fs), np.round(tx_signal * 32768).astype(np.int16))  # 16 bit nhu audiowrite
savemat(os.path.join(D, 'tx_params.mat'), dict(
    Fs=Fs, Fc=Fc, baud_rate=baud_rate, sps=float(sps), bits_per_block=float(bits_per_block),
    num_blocks=float(num_blocks), pilot_val=pilot_val, preamble_bits=preamble_bits,
    data_bits=data_bits, tx_bits=tx_bits, tx_signal=tx_signal))
print(f'Da ghi tx_cable.wav: {len(data_bits)} bit du lieu trong {num_blocks} block (preamble {len(preamble_bits)} bit).')
print('Copy file sang dien thoai, phat, roi chay Rx.py (hoac Rx.m).')
