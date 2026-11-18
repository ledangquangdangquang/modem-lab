"""Tx_qpsk.py - ban Python cua Tx_qpsk.m (dich tung dong, cung khung, cung ten file ra).

Sinh khung QPSK (preamble +-1 + pilot moi 5 ky hieu), ghi tx_cable_qpsk.wav + tx_params_qpsk.mat.
Khac Tx_qpsk.m: ghi file canh file .py (khong phai thu muc hien tai), nen chay tu dau cung duoc.
.mat ghi ra doc duoc bang ca Rx_qpsk.m lan Rx_qpsk.py.
Chu y: ghi de tx_params_qpsk.mat -> ban thu rx_debug_qpsk.wav cu khong giai ma duoc nua (BER~0.5).
"""
import os
import numpy as np
from scipy.io import wavfile, savemat

D = os.path.dirname(os.path.abspath(__file__))

Fs = 48000.0        # sample rate (float: .mat luu double nhu MATLAB, int lam MATLAB chia nguyen)
Fc = 8000.0         # tan so mang
baud_rate = 1000.0  # toc do ky hieu (2 bit/ky hieu -> 2 kbps)
sps = int(Fs / baud_rate)  # mau/ky hieu (48)

syms_per_block = 5  # 5 ky hieu QPSK = 10 bit du lieu moi block
num_blocks = 200    # 2000 bit, khung ~1.25 s
pilot_sym = (1 + 1j) / np.sqrt(2)  # ky hieu pilot da biet, co dinh o dau moi block

rng = np.random.default_rng()
preamble_bits = rng.integers(0, 2, 50).astype(float)  # giu +-1 (BPSK) de Rx dong bo + uoc luong CFO
data_bits = rng.integers(0, 2, num_blocks * syms_per_block * 2).astype(float)

# Anh xa Gray: cap bit (b1,b2) -> I=2*b1-1, Q=2*b2-1, chia sqrt(2) cho |s|=1
data_syms = ((2 * data_bits[0::2] - 1) + 1j * (2 * data_bits[1::2] - 1)) / np.sqrt(2)
frame_syms = np.hstack([np.full((num_blocks, 1), pilot_sym),
                        data_syms.reshape(num_blocks, syms_per_block)]).ravel()  # [pilot, 5 ky hieu] x num_blocks
symbols = np.concatenate([2 * preamble_bits - 1, frame_syms])
tx_bits = np.concatenate([preamble_bits, data_bits])  # chi de tham khao, Rx dung data_bits

baseband = np.repeat(symbols, sps)  # xung vuong, integrate-and-dump o Rx se khop
t = np.arange(len(baseband)) / Fs
passband = np.real(baseband * np.exp(1j * 2 * np.pi * Fc * t))  # I*cos - Q*sin

pad = np.zeros(round(0.5 * Fs))  # khoang lang dau/cuoi cho de bat dau ghi am
tx_signal = np.concatenate([pad, passband, pad])
tx_signal = 0.9 * tx_signal / np.max(np.abs(tx_signal))

# wav 16 bit PCM nhu audiowrite (wav float nhieu dien thoai khong phat duoc)
wavfile.write(os.path.join(D, 'tx_cable_qpsk.wav'), int(Fs), np.round(tx_signal * 32768).astype(np.int16))
savemat(os.path.join(D, 'tx_params_qpsk.mat'), dict(
    Fs=Fs, Fc=Fc, baud_rate=baud_rate, sps=float(sps), syms_per_block=float(syms_per_block),
    num_blocks=float(num_blocks), pilot_sym=pilot_sym, preamble_bits=preamble_bits,
    data_bits=data_bits, tx_bits=tx_bits, tx_signal=tx_signal))
print(f'Da ghi tx_cable_qpsk.wav: {len(data_bits)} bit du lieu ({len(data_syms)} ky hieu QPSK) '
      f'trong {num_blocks} block (preamble {len(preamble_bits)} ky hieu).')
print('Copy file sang dien thoai, phat, roi chay Rx_qpsk.py (hoac Rx_qpsk.m).')
