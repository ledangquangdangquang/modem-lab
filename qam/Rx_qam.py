"""Rx_qam.py - ban Python cua Rx_qam.m (dich tung dong; giai thich chi tiet tung buoc xem Rx_qam.m).

    uv run Rx_qam.py [loopback|sim|record|file]   # mac dinh = RX_SOURCE; record can: uv sync

Chuoi xu ly: ha tan -> FIR + integrate-and-dump -> dong bo preamble -> CFO tho -> tung block:
CFO du tu 2 nua tieu de, H = FFT(tieu de+0)/FFT(tieu de), MMSE, pilot -> cat quyet dinh M-QAM.
Vi tri mau giu CHI SO 1 nhu MATLAB; chi tru 1 khi lay phan tu mang numpy (x[q-1]).
"""
import os
import sys
import numpy as np
from scipy.io import loadmat, wavfile
from scipy.signal import correlate, firwin, resample_poly
from Tx_qam import qammod_bits, qamdemod_bits

D = os.path.dirname(os.path.abspath(__file__))
RX_SOURCE = 'sim'  # 'loopback' / 'sim' / 'record' / 'file' (nhu Rx_qam.m)


def mround(x):
    """round cua MATLAB (.5 lam tron ra xa 0); np.round lam tron ve so chan -> lech 1 mau."""
    return (np.sign(x) * np.floor(np.abs(x) + 0.5)).astype(int)


def conv_same(x, h):
    """conv(x, h, 'same') cua MATLAB (np.convolve 'same' lech 1 mau khi len(h) chan)."""
    return np.convolve(x, h)[len(h) // 2: len(h) // 2 + len(x)]


def wav_read(path):
    """nhu audioread: so thuc trong [-1, 1], kenh dau tien."""
    _, x = wavfile.read(path)
    if x.ndim > 1:
        x = x[:, 0]
    if x.dtype == np.uint8:
        return (x - 128.0) / 128.0
    if np.issubdtype(x.dtype, np.integer):
        return x / float(-np.iinfo(x.dtype).min)
    return x.astype(float)


def mat2str(a):
    return '[' + ' '.join(str(int(v)) for v in a) + ']'


def rx_qam(source=RX_SOURCE, params_file='tx_params_qam.mat', rx_wav='rx_debug_qam.wav'):
    P = loadmat(os.path.join(D, params_file), squeeze_me=True)
    Fs, Fc = float(P['Fs']), float(P['Fc'])
    sps, M_qam, Lh, Lz, Ld = (int(P[k]) for k in ('sps', 'M_qam', 'Lh', 'Lz', 'Ld'))
    syms_per_sub, n_sub, num_blocks = (int(P[k]) for k in ('syms_per_sub', 'n_sub', 'num_blocks'))
    pilot_sym = complex(P['pilot_sym'])
    hdr_sym = np.atleast_1d(P['hdr_sym']).astype(complex)
    preamble_bits = np.atleast_1d(P['preamble_bits']).astype(float)
    data_bits = np.atleast_1d(P['data_bits']).astype(int)
    tx_signal = np.atleast_1d(P['tx_signal']).astype(float)

    # ===== 1. Chon nguon tin hieu thu =====
    if source == 'loopback':
        rx_raw = tx_signal.copy()
    elif source == 'sim':
        # ponytail: kenh tong hop de thu bo can bang, KHONG phai kenh thuy am do that (xem Rx_qam.m)
        sim_delay_ms = np.array([0, 1.3, 3.7])  # tre cac tia (ms)
        sim_gain = np.array([1, 0.6, -0.4])     # bien do cac tia
        sim_snr_db = 12                          # SNR dai thong
        h_sim = np.zeros(mround(sim_delay_ms.max() * Fs / 1000) + 1)
        np.add.at(h_sim, mround(sim_delay_ms * Fs / 1000), sim_gain)
        rx_raw = resample_poly(np.convolve(tx_signal, h_sim), 1003, 1000)  # lech dong ho 0.3%
        p_sig = np.mean(tx_signal[tx_signal != 0] ** 2) * np.sum(h_sim ** 2)  # cong suat luc co tin hieu
        rx_raw = rx_raw + np.sqrt(p_sig / 10 ** (sim_snr_db / 10)) * np.random.randn(len(rx_raw))
    elif source == 'file':
        rx_raw = wav_read(os.path.join(D, rx_wav))
    else:
        import sounddevice as sd  # chi can khi thu that: uv sync
        record_time = len(tx_signal) / Fs + 2  # do dai khung + 2 s du tre khi bam phat
        print('Bat dau phat tx_cable_qam.wav tren dien thoai ngay bay gio...')
        rx_raw = sd.rec(int(round(record_time * Fs)), samplerate=int(Fs), channels=1, dtype='float64')
        sd.wait()
        rx_raw = rx_raw[:, 0]
        print(f'Muc tin hieu thu duoc: peak={np.max(np.abs(rx_raw)):.4f}, rms={np.sqrt(np.mean(rx_raw**2)):.4f} '
              '(gan 0 nghia la thu nham thiet bi hoac chua cam cap)')
        wavfile.write(os.path.join(D, rx_wav), int(Fs),
                      np.round(np.clip(rx_raw, -1, 32767 / 32768) * 32768).astype(np.int16))

    # ===== 2-3. Ha tan + loc FIR bo anh 2*Fc + integrate-and-dump =====
    t = np.arange(len(rx_raw)) / Fs
    rx_bb = rx_raw * np.exp(-1j * 2 * np.pi * Fc * t)
    rx_bb = conv_same(rx_bb, firwin(sps + 1, Fc / (Fs / 2)))  # = fir1(sps, Fc/(Fs/2)): Hamming, DC = 1
    mf_out = conv_same(rx_bb, np.ones(sps) / sps)

    # ===== 4. Dong bo khung: tuong quan preamble, quet luoi CFO =====
    preamble_sym = 2 * preamble_bits - 1
    preamble_ref = np.repeat(preamble_sym, sps)
    N = len(mf_out)
    if N < len(preamble_ref):
        raise RuntimeError('Khong tim thay preamble trong tin hieu thu duoc.')
    ref_pad = np.zeros(N)
    ref_pad[:len(preamble_ref)] = preamble_ref  # dem 0 nhu xcorr: lag -(N-1)..N-1
    n_full = np.arange(N)
    best_peak = -1
    for cfo_try in np.arange(-500, 501, 15):
        derot = mf_out * np.exp(-1j * 2 * np.pi * cfo_try * n_full / Fs)
        c_try = np.abs(correlate(derot, ref_pad, 'full'))
        pk_try = int(np.argmax(c_try))
        if c_try[pk_try] > best_peak:
            best_peak, pk = c_try[pk_try], pk_try
    start_idx = pk - (N - 1) + 1  # mau dau preamble trong mf_out (chi so 1)
    if start_idx < 1 or start_idx + len(preamble_ref) - 1 > N:
        raise RuntimeError('Khong tim thay preamble trong tin hieu thu duoc.')

    # ===== 5. CFO tho tu preamble =====
    Np = len(preamble_bits)
    preamble_seg = mf_out[start_idx - 1: start_idx - 1 + len(preamble_ref)]
    sym_val = preamble_seg[np.arange(Np) * sps + mround(sps / 2) - 1] * preamble_sym
    cfo_hz = np.angle(np.mean(sym_val[1:] * np.conj(sym_val[:-1]))) / (2 * np.pi * sps / Fs)
    cfo_pre = cfo_hz

    # ===== 6. Tung block: CFO du -> uoc luong kenh FFT -> MMSE -> pilot =====
    Lb = Lh + Lz + Ld + Lz           # ky hieu/block
    mg = 2                           # ky hieu lui cua so
    win = 2                          # do lech vi tri toi da thu moi block (+-mau)
    Lf = max(Lh, Ld) + Lz            # do dai FFT
    XP = np.fft.fft(hdr_sym, Lf)     # tieu de da biet, dem 0 len Lf
    n_win = np.arange(Lb)
    h2 = Lh // 2
    ip = 1 + np.arange(n_sub) * (syms_per_sub + 1)  # vi tri pilot trong phan du lieu (chi so 1)
    idat = np.setdiff1d(np.arange(1, Ld + 1), ip)   # vi tri ky hieu du lieu (chi so 1)
    n_dsym = n_sub * syms_per_sub
    hq = np.arange(mg, mg + Lh)

    mfo = mf_out[start_idx - 1:]
    Lm = len(mfo)  # mfo[0] = mau dau preamble
    p0 = (Np + Lz - mg) * sps + mround(sps / 2)  # mau giua ky hieu dau cua cua so block 1 (chi so 1)
    eq_all = np.zeros(num_blocks * n_dsym, dtype=complex)
    cfo_blk = np.zeros(num_blocks)
    block_timing = np.zeros(num_blocks, dtype=int)
    for blk in range(num_blocks):
        for it in range(3):  # 0: CFO du tu tieu de; 1-2: can bang + CFO du tu pilot
            drift = -cfo_hz / (Fc + cfo_hz)
            sp = sps * (1 + drift)  # khoang cach mau thuc giua 2 ky hieu
            best_c = -1
            for dd in (0, -1, 1, -win, win):  # chinh vi tri theo tuong quan tieu de
                q = np.clip(mround(p0 + dd + hq * sp), 1, Lm)
                c = abs(np.sum(mfo[q - 1] * np.exp(-1j * 2 * np.pi * cfo_hz * (q - q[0]) / Fs) * np.conj(hdr_sym)))
                if c > best_c:
                    best_c, dbest = c, dd
            # a. mau giua ky hieu ca block, xoay nguoc CFO
            q = np.clip(mround(p0 + dbest + n_win * sp), 1, Lm)
            r = mfo[q - 1] * np.exp(-1j * 2 * np.pi * cfo_hz * (q - q[0]) / Fs)
            if it == 0:
                # b. CFO du tu lech pha giua 2 nua tieu de
                c1 = np.sum(r[mg: mg + h2] * np.conj(hdr_sym[:h2]))
                c2 = np.sum(r[mg + h2: mg + 2 * h2] * np.conj(hdr_sym[h2: 2 * h2]))
                cfo_hz = cfo_hz + np.angle(c2 * np.conj(c1)) / (2 * np.pi * h2 * sp / Fs)
                continue
            rh, rd = r[:Lh + Lz], r[Lh + Lz:]           # tieu de+0 | du lieu+0
            H = np.fft.fft(rh, Lf) / XP                 # H = HP/XP
            hh = np.fft.ifft(H); hh[Lz:] = 0; H = np.fft.fft(hh)  # kenh khong dai hon Lz
            res = rh - np.fft.ifft(XP * H)[:Lh + Lz]    # phan du cua tieu de = nhieu
            nv = np.mean(np.abs(res) ** 2) + np.finfo(float).eps
            xd = np.fft.ifft(np.conj(H) * np.fft.fft(rd, Lf) / (np.abs(H) ** 2 + nv))[:Ld]  # MMSE, cat duoi
            # e. pilot sau can bang: g(n) = A∠(phi0 + w*n)
            g = xd[ip - 1] / pilot_sym
            pf = np.polyfit(ip - 1, np.unwrap(np.angle(g)), 1)  # pf[0] = rad/ky hieu
            cfo_hz = cfo_hz + pf[0] / (2 * np.pi * sp / Fs)
        xe = xd / (np.mean(np.abs(g)) * np.exp(1j * (pf[1] + pf[0] * np.arange(Ld))))
        eq_all[blk * n_dsym: (blk + 1) * n_dsym] = xe[idat - 1]
        cfo_blk[blk] = cfo_hz
        block_timing[blk] = mround(p0 + dbest - ((Np + Lz - mg + blk * Lb) * sps + mround(sps / 2)))
        p0 = p0 + dbest + Lb * sp  # cua so block sau
    print(f'CFO preamble {cfo_pre:.2f} Hz -> bam theo block (min / median / max): '
          f'{cfo_blk.min():.2f} / {np.median(cfo_blk):.2f} / {cfo_blk.max():.2f} Hz')
    print(f'Lech vi tri block so voi danh nghia (mau): dau {block_timing[0]}, '
          f'giua {block_timing[(num_blocks + 1) // 2 - 1]}, cuoi {block_timing[-1]}')

    # ===== 7. Cat quyet dinh M-QAM, BER, EVM =====
    rx_bits = qamdemod_bits(eq_all, M_qam)
    num_err = int(np.sum(rx_bits != data_bits))
    print(f'{M_qam}-QAM: so bit loi {num_err} / {len(data_bits)}, BER = {num_err / len(data_bits):.2e}')
    ideal = qammod_bits(rx_bits, M_qam)  # diem chom sao gan nhat
    evm = np.sqrt(np.mean(np.abs(eq_all - ideal) ** 2) / np.mean(np.abs(ideal) ** 2))
    print(f'EVM = {100 * evm:.1f} % (SNR ky hieu ~ {-20 * np.log10(evm):.1f} dB)')
    block_err = (rx_bits != data_bits).reshape(num_blocks, -1).sum(axis=1)
    print(f'Loi tung block: {mat2str(block_err)}')
    return locals()


if __name__ == '__main__':
    r = rx_qam(sys.argv[1] if len(sys.argv) > 1 else RX_SOURCE)
    import matplotlib.pyplot as plt
    plt.figure(); plt.plot(r['eq_all'].real, r['eq_all'].imag, '.', ms=3); plt.axis('equal'); plt.grid(True)
    plt.title(f"{r['M_qam']}-QAM sau can bang MMSE + pilot")
    plt.figure(); plt.stem(np.arange(r['Lz']), np.abs(r['hh'][:r['Lz']]))
    plt.xlabel('tre (ky hieu, tinh tu dau cua so = tia manh nhat - mg)'); plt.ylabel('|h|')
    plt.title('Dap ung kenh uoc luong tu tieu de (block cuoi)')
    plt.show()
