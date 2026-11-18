"""Tx_qam.py - ban Python cua Tx_qam.m: khung M-QAM co doan 0 (ZP) theo bang sang che FSK.

Khung (ky hieu): [preamble +-1 | 0 | tieu de | 0 | du lieu | 0 | tieu de | 0 | du lieu | 0 | ...]
(giai thich tung phan xem Tx_qam.m). Ghi tx_cable_qam.wav + tx_params_qam.mat canh file .py;
.mat doc duoc bang ca Rx_qam.m lan Rx_qam.py.
"""
import os
import numpy as np
from scipy.io import wavfile, savemat

D = os.path.dirname(os.path.abspath(__file__))


def qam_const(M):
    """= qammod(0:M-1, M, 'gray', 'UnitAveragePower', true) cua MATLAB (da so voi MATLAB, M = 4/16/64).
    Nua bit dau (MSB) -> I, nua sau -> Q; moi nua ma Gray; Q lon nhat o so 0."""
    m = int(round(np.sqrt(M)))
    k = np.arange(M)

    def gray_dec(g):
        s = g >> 1
        while s.any():
            g, s = g ^ s, s >> 1
        return g
    i, q = gray_dec(k >> int(np.log2(m))), gray_dec(k & (m - 1))
    return ((2 * i - (m - 1)) + 1j * ((m - 1) - 2 * q)) / np.sqrt(2 * (M - 1) / 3)


def qammod_bits(bits, M):
    k = int(np.log2(M))
    return qam_const(M)[np.asarray(bits, int).reshape(-1, k) @ (1 << np.arange(k - 1, -1, -1))]


def qamdemod_bits(x, M):
    """quyet dinh cung = diem chom sao gan nhat (nhu qamdemod), tra ve bit MSB truoc."""
    k = int(np.log2(M))
    idx = np.argmin(np.abs(np.asarray(x)[:, None] - qam_const(M)[None, :]), axis=1)
    return ((idx[:, None] >> np.arange(k - 1, -1, -1)) & 1).ravel()


if __name__ == '__main__':
    Fs = 48000.0        # sample rate (float: .mat luu double nhu MATLAB)
    Fc = 8000.0         # tan so mang
    baud_rate = 1000.0  # toc do ky hieu
    sps = int(Fs / baud_rate)  # mau/ky hieu (48)

    M_qam = 16          # 4 / 16 / 64 ... -> log2(M_qam) bit moi ky hieu
    Lh = 31             # do dai tieu de (ky hieu)
    Lz = 8              # doan 0 (ky hieu); phai > trai tre kenh + mg (xem Rx_qam.m)
    syms_per_sub = 5    # ky hieu du lieu sau moi pilot
    n_sub = 10          # so nhom [pilot, 5 ky hieu] trong 1 block
    Ld = n_sub * (syms_per_sub + 1)
    num_blocks = 20
    pilot_sym = (1 + 1j) / np.sqrt(2)
    n = np.arange(Lh)
    hdr_sym = np.exp(-1j * np.pi * n * (n + 1) / Lh)  # Zadoff-Chu goc 1

    k_bits = int(np.log2(M_qam))
    rng = np.random.default_rng()
    preamble_bits = rng.integers(0, 2, 50).astype(float)
    data_bits = rng.integers(0, 2, num_blocks * n_sub * syms_per_sub * k_bits).astype(float)
    data_syms = qammod_bits(data_bits, M_qam)

    z = np.zeros(Lz)
    frame = []
    for d in data_syms.reshape(num_blocks, n_sub, syms_per_sub):
        d = np.hstack([np.full((n_sub, 1), pilot_sym), d]).ravel()  # moi nhom = [pilot, 5 ky hieu]
        frame += [hdr_sym, z, d, z]
    symbols = np.concatenate([2 * preamble_bits - 1, z] + frame)

    baseband = np.repeat(symbols, sps)
    t = np.arange(len(baseband)) / Fs
    passband = np.real(baseband * np.exp(1j * 2 * np.pi * Fc * t))
    pad = np.zeros(round(0.5 * Fs))
    tx_signal = np.concatenate([pad, passband, pad])
    tx_signal = 0.9 * tx_signal / np.max(np.abs(tx_signal))

    wavfile.write(os.path.join(D, 'tx_cable_qam.wav'), int(Fs), np.round(tx_signal * 32768).astype(np.int16))
    savemat(os.path.join(D, 'tx_params_qam.mat'), dict(
        Fs=Fs, Fc=Fc, baud_rate=baud_rate, sps=float(sps), M_qam=float(M_qam), Lh=float(Lh), Lz=float(Lz),
        Ld=float(Ld), syms_per_sub=float(syms_per_sub), n_sub=float(n_sub), num_blocks=float(num_blocks),
        pilot_sym=pilot_sym, hdr_sym=hdr_sym, preamble_bits=preamble_bits, data_bits=data_bits,
        tx_signal=tx_signal))
    print(f'Da ghi tx_cable_qam.wav: {M_qam}-QAM, {len(data_bits)} bit du lieu trong {num_blocks} block, '
          f'khung {len(baseband) / Fs:.2f} s (hieu suat {100 * n_sub * syms_per_sub / (Lh + Lz + Ld + Lz):.0f} %).')
    print('Copy file sang dien thoai, phat, roi chay Rx_qam.py (hoac Rx_qam.m).')
