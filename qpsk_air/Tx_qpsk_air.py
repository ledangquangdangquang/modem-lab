"""Tx_qpsk_air.py - ban Python cua Tx_qpsk_air.m: QPSK qua KHONG KHI (loa dien thoai -> mic laptop).

Ban sao Tx_qam.py voi M_qam = 4, 500 baud, khoang lang 1.5 s, + ma Reed-Solomon (giai thich xem Tx_qpsk_air.m).
Ghi tx_air_qpsk.wav + tx_params_qpsk_air.mat canh file .py; .mat doc duoc bang ca Rx_qpsk_air.m lan .py.
Can: uv sync (cung ma voi rsenc cua MATLAB: GF(256) poly 0x11d, nghiem alpha^1.., da so tung byte).
"""
import os
import numpy as np
from scipy.io import wavfile, savemat

D = os.path.dirname(os.path.abspath(__file__))


def qam_const(M):
    """= qammod(0:M-1, M, 'gray', 'UnitAveragePower', true) cua MATLAB (nhu qam/Tx_qam.py)."""
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
    k = int(np.log2(M))
    idx = np.argmin(np.abs(np.asarray(x)[:, None] - qam_const(M)[None, :]), axis=1)
    return ((idx[:, None] >> np.arange(k - 1, -1, -1)) & 1).ravel()


def rs_codec(rs_n, rs_k):
    """= rsenc/rsdec(gf(.,8), rs_n, rs_k) cua MATLAB (ma rut gon tu RS(255, .))."""
    import reedsolo  # uv sync
    return reedsolo.RSCodec(rs_n - rs_k, nsize=255, fcr=1, prim=0x11d, generator=2)


if __name__ == '__main__':
    Fs = 48000.0        # sample rate (float: .mat luu double nhu MATLAB)
    Fc = 8000.0         # tan so mang
    baud_rate = 500.0   # thap hon ban cap: ky hieu 2 ms, doan 0 dai 16 ms che duoc vang xa hon
    sps = int(Fs / baud_rate)  # mau/ky hieu (96)

    M_qam = 4           # 4 = QPSK
    Lh = 31             # do dai tieu de (ky hieu)
    Lz = 8              # doan 0 (ky hieu) = 16 ms o 500 baud
    syms_per_sub = 5
    n_sub = 10
    Ld = n_sub * (syms_per_sub + 1)
    num_blocks = 20     # 20 block * 50 ky hieu * 2 bit = 2000 bit, khung ~4.4 s
    pilot_sym = (1 + 1j) / np.sqrt(2)
    n = np.arange(Lh)
    hdr_sym = np.exp(-1j * np.pi * n * (n + 1) / Lh)  # Zadoff-Chu goc 1

    k_bits = int(np.log2(M_qam))
    rng = np.random.default_rng()
    preamble_bits = rng.integers(0, 2, 50).astype(float)
    # Reed-Solomon tren GF(256): rs_k byte tin -> rs_n byte, sua duoc (rs_n - rs_k)/2 byte sai
    rs_n = num_blocks * n_sub * syms_per_sub * k_bits / 8  # 250 voi QPSK
    rs_k = 186
    assert rs_n == int(rs_n) and rs_n <= 255 and rs_k < rs_n, \
        'RS: khung phai chua so byte nguyen <= 255 (doi num_blocks/M_qam thi phai chia thanh nhieu tu ma)'
    rs_n = int(rs_n)
    msg_bits = rng.integers(0, 2, rs_k * 8).astype(float)  # bit tin goc (Rx so sanh sau khi giai ma RS)
    code = rs_codec(rs_n, rs_k).encode(np.packbits(msg_bits.astype(np.uint8)).tobytes())  # [byte tin | byte kiem tra]
    data_bits = np.unpackbits(np.frombuffer(bytes(code), np.uint8)).astype(float)  # bit len song, MSB truoc
    data_syms = qammod_bits(data_bits, M_qam)

    z = np.zeros(Lz)
    frame = []
    for d in data_syms.reshape(num_blocks, n_sub, syms_per_sub):
        d = np.hstack([np.full((n_sub, 1), pilot_sym), d]).ravel()
        frame += [hdr_sym, z, d, z]
    symbols = np.concatenate([2 * preamble_bits - 1, z] + frame)

    baseband = np.repeat(symbols, sps)
    t = np.arange(len(baseband)) / Fs
    passband = np.real(baseband * np.exp(1j * 2 * np.pi * Fc * t))
    pad = np.zeros(round(1.5 * Fs))  # bam phat/thu bang tay qua khong khi can dem dai hon cap
    tx_signal = np.concatenate([pad, passband, pad])
    tx_signal = 0.9 * tx_signal / np.max(np.abs(tx_signal))

    wavfile.write(os.path.join(D, 'tx_air_qpsk.wav'), int(Fs), np.round(tx_signal * 32768).astype(np.int16))
    savemat(os.path.join(D, 'tx_params_qpsk_air.mat'), dict(
        Fs=Fs, Fc=Fc, baud_rate=baud_rate, sps=float(sps), M_qam=float(M_qam), Lh=float(Lh), Lz=float(Lz),
        Ld=float(Ld), syms_per_sub=float(syms_per_sub), n_sub=float(n_sub), num_blocks=float(num_blocks),
        pilot_sym=pilot_sym, hdr_sym=hdr_sym, preamble_bits=preamble_bits, data_bits=data_bits,
        tx_signal=tx_signal, msg_bits=msg_bits, rs_n=float(rs_n), rs_k=float(rs_k)))
    print(f'Da ghi tx_air_qpsk.wav: {M_qam}-QAM, {len(data_bits)} bit du lieu trong {num_blocks} block, '
          f'khung {len(baseband) / Fs:.2f} s (hieu suat {100 * n_sub * syms_per_sub / (Lh + Lz + Ld + Lz):.0f} %).')
    print('Copy file sang dien thoai, phat bang LOA NGOAI cach mic laptop 10-30 cm, roi chay Rx_qpsk_air.py.')
