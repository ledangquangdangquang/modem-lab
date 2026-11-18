"""Rx_qpsk_air.py - ban Python cua Rx_qpsk_air.m: thu QPSK qua KHONG KHI (loa dien thoai -> mic laptop).

    uv run Rx_qpsk_air.py [loopback|sim|record|file]   # mac dinh = RX_SOURCE
    (record can: uv sync; giai ma Reed-Solomon can: uv sync)

Ban sao Rx_qam.py (giai thich chi tiet xem Rx_qpsk_air.m). Khac: phong mo phong o 'sim', luoi CFO
-60:baud/(4*Np):60 Hz va CFO tho = diem luoi thang (khong dung lech pha preamble), giai ma Reed-Solomon.
Truoc khi thu that: chay 'loopback' (BER phai = 0) roi 'sim'.
Vi tri mau giu CHI SO 1 nhu MATLAB; chi tru 1 khi lay phan tu mang numpy (x[q-1]).
"""
import os
import sys
import numpy as np
from scipy.io import loadmat, wavfile
from scipy.signal import correlate, firwin, resample_poly
from Tx_qpsk_air import qammod_bits, qamdemod_bits, rs_codec

D = os.path.dirname(os.path.abspath(__file__))
RX_SOURCE = 'record'  # 'loopback' / 'sim' / 'record' / 'file' (nhu Rx_qpsk_air.m)


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


def rx_qpsk_air(source=RX_SOURCE, params_file='tx_params_qpsk_air.mat', rx_wav='rx_air_qpsk.wav'):
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
        # shortcut: phong TU DAT, khong phai do that - chi de thu bo can bang truoc khi co ban thu.
        sim_echo_ms, sim_echo_gain = 0.8, 0.5  # phan xa mat ban: tre (ms), bien do so voi tia truc tiep
        sim_rt60 = 0.3     # thoi gian vang cua phong (s)
        sim_drr_db = 10    # tia truc tiep manh hon tong duoi vang bao nhieu dB
        sim_snr_db = 15    # SNR dai thong
        n_tail = mround(sim_rt60 * Fs)
        h_sim = np.random.randn(n_tail) * 10.0 ** (-3 * np.arange(n_tail) / n_tail)  # duoi vang: nhieu trang * bao mu
        h_sim[:mround(0.002 * Fs)] = 0  # 2 ms dau chi co tia truc tiep + phan xa ban
        h_sim = h_sim / np.linalg.norm(h_sim) * 10 ** (-sim_drr_db / 20)
        h_sim[0] = 1
        h_sim[mround(sim_echo_ms * Fs / 1000)] = sim_echo_gain
        rx_raw = resample_poly(np.convolve(tx_signal, h_sim), 1003, 1000)  # lech dong ho 0.3%
        p_sig = np.mean(tx_signal[tx_signal != 0] ** 2)  # cong suat tia truc tiep luc co tin hieu
        rx_raw = rx_raw + np.sqrt(p_sig / 10 ** (sim_snr_db / 10)) * np.random.randn(len(rx_raw))
    elif source == 'file':
        rx_raw = wav_read(os.path.join(D, rx_wav))
    else:
        import sounddevice as sd  # chi can khi thu that: uv sync
        record_time = len(tx_signal) / Fs + 3  # do dai file phat + 3 s du tre khi bam phat
        print('Bat dau phat tx_air_qpsk.wav bang loa dien thoai ngay bay gio...')
        rx_raw = sd.rec(int(round(record_time * Fs)), samplerate=int(Fs), channels=1, dtype='float64')
        sd.wait()
        rx_raw = rx_raw[:, 0]
        print(f'Muc tin hieu thu duoc: peak={np.max(np.abs(rx_raw)):.4f}, rms={np.sqrt(np.mean(rx_raw**2)):.4f} '
              '(gan 0 nghia la thu nham thiet bi hoac loa qua xa mic; peak ~1 = bi cat dinh, giam am luong)')
        wavfile.write(os.path.join(D, rx_wav), int(Fs),
                      np.round(np.clip(rx_raw, -1, 32767 / 32768) * 32768).astype(np.int16))

    # ===== 2-3. Ha tan + loc FIR bo anh 2*Fc + integrate-and-dump =====
    t = np.arange(len(rx_raw)) / Fs
    rx_bb = rx_raw * np.exp(-1j * 2 * np.pi * Fc * t)
    rx_bb = conv_same(rx_bb, firwin(sps + 1, Fc / (Fs / 2)))  # = fir1(sps, Fc/(Fs/2)): Hamming, DC = 1
    mf_out = conv_same(rx_bb, np.ones(sps) / sps)

    # ===== 4. Dong bo khung + CFO tho: luoi buoc 1/(4T) (luoi 15 Hz lot mat CFO that, xem Rx_qpsk_air.m) =====
    preamble_sym = 2 * preamble_bits - 1
    preamble_ref = np.repeat(preamble_sym, sps)
    N = len(mf_out)
    if N < len(preamble_ref):
        raise RuntimeError('Khong tim thay preamble trong tin hieu thu duoc.')
    ref_pad = np.zeros(N)
    ref_pad[:len(preamble_ref)] = preamble_ref  # dem 0 nhu xcorr: lag -(N-1)..N-1
    n_full = np.arange(N)
    cfo_step = float(P['baud_rate']) / (4 * len(preamble_bits))  # 2.5 Hz o 500 baud
    best_peak = -1
    for cfo_try in np.arange(-60, 60 + cfo_step / 2, cfo_step):
        derot = mf_out * np.exp(-1j * 2 * np.pi * cfo_try * n_full / Fs)
        c_try = np.abs(correlate(derot, ref_pad, 'full'))
        pk_try = int(np.argmax(c_try))
        if c_try[pk_try] > best_peak:
            best_peak, pk, cfo_hz = c_try[pk_try], pk_try, cfo_try
    start_idx = pk - (N - 1) + 1  # mau dau preamble trong mf_out (chi so 1)
    if start_idx < 1 or start_idx + len(preamble_ref) - 1 > N:
        raise RuntimeError('Khong tim thay preamble trong tin hieu thu duoc.')
    # CFO tho = diem luoi thang; khong dung lech pha preamble (da duong lam pha tan +-40 do)
    Np = len(preamble_bits)
    cfo_pre = cfo_hz
    print(f'Dong bo: khung bat dau tai {(start_idx - 1) / Fs:.3f} s, CFO tho {cfo_hz:.1f} Hz')

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
    print(f'{M_qam}-QAM: so bit loi (truoc sua loi) {num_err} / {len(data_bits)}, BER = {num_err / len(data_bits):.2e}')
    # Giai ma Reed-Solomon (so voi bit tin goc msg_bits). .mat cu (truoc_fec/) khong co rs_k -> bo qua.
    if 'rs_k' in P:
        import reedsolo
        rs_n, rs_k = int(P['rs_n']), int(P['rs_k'])
        msg_bits = np.atleast_1d(P['msg_bits']).astype(int)
        rx_bytes = np.packbits(rx_bits.astype(np.uint8)).tobytes()
        try:
            dec, _, errata = rs_codec(rs_n, rs_k).decode(rx_bytes)
            n_fix = len(errata)
        except reedsolo.ReedSolomonError:
            dec, n_fix = rx_bytes[:rs_k], -1  # nhu rsdec: qua kha nang sua thi tra ve phan tin chua sua
        msg_err = int(np.sum(np.unpackbits(np.frombuffer(bytes(dec), np.uint8)) != msg_bits))
        if n_fix < 0:
            print(f'Reed-Solomon({rs_n},{rs_k}): QUA {(rs_n - rs_k) // 2} byte sai, khong sua duoc. '
                  f'Bit tin sai: {msg_err} / {len(msg_bits)}')
        else:
            print(f'Reed-Solomon({rs_n},{rs_k}): da sua {n_fix} byte (toi da {(rs_n - rs_k) // 2}). '
                  f'Bit tin sai sau sua: {msg_err} / {len(msg_bits)}')
    ideal = qammod_bits(rx_bits, M_qam)  # diem chom sao gan nhat
    evm = np.sqrt(np.mean(np.abs(eq_all - ideal) ** 2) / np.mean(np.abs(ideal) ** 2))
    print(f'EVM = {100 * evm:.1f} % (SNR ky hieu ~ {-20 * np.log10(evm):.1f} dB)')
    block_err = (rx_bits != data_bits).reshape(num_blocks, -1).sum(axis=1)
    print(f'Loi tung block: {mat2str(block_err)}')
    return locals()


if __name__ == '__main__':
    r = rx_qpsk_air(sys.argv[1] if len(sys.argv) > 1 else RX_SOURCE)
    import matplotlib.pyplot as plt
    plt.figure(); plt.plot(r['eq_all'].real, r['eq_all'].imag, '.', ms=3); plt.axis('equal'); plt.grid(True)
    plt.title(f"{r['M_qam']}-QAM sau can bang MMSE + pilot")
    plt.figure(); plt.stem(np.arange(r['Lz']), np.abs(r['hh'][:r['Lz']]))
    plt.xlabel('tre (ky hieu, tinh tu dau cua so = tia manh nhat - mg)'); plt.ylabel('|h|')
    plt.title('Dap ung kenh uoc luong tu tieu de (block cuoi)')
    plt.show()
