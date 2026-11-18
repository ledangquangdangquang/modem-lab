"""Rx_qpsk.py - ban Python cua Rx_qpsk.m (dich tung dong; giai thich chi tiet tung buoc xem Rx_qpsk.m).

    uv run Rx_qpsk.py              # nguon = RX_SOURCE ben duoi
    uv run Rx_qpsk.py loopback     # tu-kiem-tra, BER phai = 0
    uv run Rx_qpsk.py file         # giai ma lai rx_debug_qpsk.wav
    uv run Rx_qpsk.py record       # thu that qua cap (can: uv sync)

Ham rx_qpsk(...) tra ve dict moi bien (nhu workspace MATLAB) de Audio_qpsk.py / Plot_qpsk.py dung lai.
Vi tri mau (start_idx, p, pilot_idx, idx_c ...) giu dung CHI SO 1 nhu MATLAB de so tung dong voi .m;
chi tru 1 khi lay phan tu mang numpy (x[p-1]).
"""
import os
import sys
import numpy as np
from scipy.io import loadmat, wavfile
from scipy.signal import correlate

D = os.path.dirname(os.path.abspath(__file__))
RX_SOURCE = 'record'  # 'loopback' / 'record' / 'file' (nhu Rx_qpsk.m)


def mround(x):
    """round cua MATLAB (.5 lam tron ra xa 0); np.round lam tron ve so chan -> lech 1 mau."""
    return (np.sign(x) * np.floor(np.abs(x) + 0.5)).astype(int)


def conv_same(x, h):
    """conv(x, h, 'same') cua MATLAB (np.convolve 'same' lech 1 mau khi len(h) chan)."""
    return np.convolve(x, h)[len(h) // 2: len(h) // 2 + len(x)]


def wav_read(path):
    """nhu audioread: tra ve so thuc trong [-1, 1], kenh dau tien."""
    _, x = wavfile.read(path)
    if x.ndim > 1:
        x = x[:, 0]
    if x.dtype == np.uint8:
        return (x - 128.0) / 128.0
    if np.issubdtype(x.dtype, np.integer):
        return x / float(-np.iinfo(x.dtype).min)
    return x.astype(float)


def record(Fs, record_time, input_device_id=None):
    """nhu audiorecorder + recordblocking. None = thiet bi mac dinh; sai thiet bi thi xem sounddevice.query_devices()."""
    import sounddevice as sd  # chi can khi thu that: uv sync
    x = sd.rec(int(round(record_time * Fs)), samplerate=int(Fs), channels=1, dtype='float64',
               device=input_device_id)
    sd.wait()
    return x[:, 0]


def mat2str(a):
    return '[' + ' '.join(str(int(v)) for v in a) + ']'


def rx_qpsk(source=RX_SOURCE, params_file='tx_params_qpsk.mat', rx_wav='rx_debug_qpsk.wav', record_time=5):
    P = loadmat(os.path.join(D, params_file), squeeze_me=True)
    Fs, Fc = float(P['Fs']), float(P['Fc'])
    sps, syms_per_block, num_blocks = int(P['sps']), int(P['syms_per_block']), int(P['num_blocks'])
    pilot_sym = complex(P['pilot_sym'])
    preamble_bits = np.atleast_1d(P['preamble_bits']).astype(float)
    data_bits = np.atleast_1d(P['data_bits']).astype(int)
    tx_signal = np.atleast_1d(P['tx_signal']).astype(float)

    # ===== 1. Chon nguon tin hieu thu =====
    if source == 'loopback':
        rx_raw = tx_signal.copy()
    elif source == 'file':
        rx_raw = wav_read(os.path.join(D, rx_wav))
    else:
        print('Bat dau phat file .wav (tx_cable_qpsk.wav hoac tx_cable_audio.wav) tren dien thoai ngay bay gio...')
        rx_raw = record(Fs, record_time)
        print(f'Muc tin hieu thu duoc: peak={np.max(np.abs(rx_raw)):.4f}, rms={np.sqrt(np.mean(rx_raw**2)):.4f} '
              '(gan 0 nghia la thu nham thiet bi hoac chua cam cap)')
        wavfile.write(os.path.join(D, rx_wav), int(Fs),
                      np.round(np.clip(rx_raw, -1, 32767 / 32768) * 32768).astype(np.int16))  # de soi lai neu decode sai

    # ===== 2. Ha tan xuong baseband phuc (I/Q) =====
    t = np.arange(len(rx_raw)) / Fs
    rx_bb = rx_raw * np.exp(-1j * 2 * np.pi * Fc * t)

    # ===== 3. Loc phoi hop (integrate-and-dump) =====
    mf_out = conv_same(rx_bb, np.ones(sps) / sps)

    # ===== 4. Dong bo khung: tuong quan preamble, quet luoi CFO =====
    preamble_sym = 2 * preamble_bits - 1
    preamble_ref = np.repeat(preamble_sym, sps)
    N = len(mf_out)
    if N < len(preamble_ref):
        raise RuntimeError('Khong tim thay preamble trong tin hieu thu duoc.')
    ref_pad = np.zeros(N)
    ref_pad[:len(preamble_ref)] = preamble_ref  # dem 0 bang do dai nhu xcorr: lag -(N-1)..N-1
    n_full = np.arange(N)
    best_peak = -1
    for cfo_try in np.arange(-500, 501, 15):
        derot = mf_out * np.exp(-1j * 2 * np.pi * cfo_try * n_full / Fs)
        c_try = correlate(derot, ref_pad, 'full')  # c_try[i] <-> lag i-(N-1)
        pk_try = int(np.argmax(np.abs(c_try)))
        if abs(c_try[pk_try]) > best_peak:
            best_peak, c, pk = abs(c_try[pk_try]), c_try, pk_try
    start_idx = pk - (N - 1) + 1  # chi so 1 nhu MATLAB (lags(pk)+1)
    sync_confidence = best_peak / np.median(np.abs(c))
    print(f'Dong bo: peak/median tuong quan = {sync_confidence:.1f} (cang cao cang chac chan tim dung preamble)')
    if start_idx < 1 or start_idx + len(preamble_ref) - 1 > N:
        raise RuntimeError('Khong tim thay preamble trong tin hieu thu duoc.')

    # ===== 5. CFO tu preamble: lech pha giua 2 ky hieu lien tiep =====
    preamble_seg = mf_out[start_idx - 1: start_idx - 1 + len(preamble_ref)]
    idx_c = np.arange(len(preamble_bits)) * sps + mround(sps / 2)
    sym_val = preamble_seg[idx_c - 1] * preamble_sym
    diffs = sym_val[1:] * np.conj(sym_val[:-1])
    cfo_hz = np.angle(np.mean(diffs)) / (2 * np.pi * sps / Fs)

    # ===== 6. Bam CFO + vi tri pilot theo tung doan M block =====
    data_start = len(preamble_ref) + 1
    spb = (syms_per_block + 1) * sps
    mfo = mf_out[start_idx - 1:]
    L = len(mfo)  # mfo[0] = mau dau preamble
    M, win = 10, 2
    pilot_idx = np.zeros(num_blocks, dtype=int)
    cfo_blk = np.zeros(num_blocks)
    cfo_pre = cfo_hz
    p0 = data_start + mround(sps / 2) - 1  # so thuc, cong don qua cac doan
    for b0 in range(1, num_blocks + 1, M):  # b0 = block dau doan (chi so 1)
        m = min(M, num_blocks - b0 + 1)
        for _ in range(2):  # cfo -> vi tri pilot -> cfo
            drift = -cfo_hz / (Fc + cfo_hz)
            p = np.minimum(mround(p0 + np.arange(m) * spb * (1 + drift)), L)
            if m >= 3:
                ph = np.unwrap(np.angle(mfo[p - 1] * np.exp(-1j * 2 * np.pi * cfo_hz * (p - 1) / Fs) / pilot_sym))
                pf = np.polyfit(p - p[0], ph, 1)
                cfo_hz = cfo_hz + pf[0] * Fs / (2 * np.pi)
        drift = -cfo_hz / (Fc + cfo_hz)
        p = mround(p0 + np.arange(m) * spb * (1 + drift))
        best_coh, dbest = -1, 0
        for dd in (0, -1, 1, -win, win):  # 0 truoc: hoa thi giu vi tri du doan
            pd = np.clip(p + dd, 1, L)
            z = mfo[pd - 1] * np.exp(-1j * 2 * np.pi * cfo_hz * (pd - 1) / Fs)
            coh = abs(np.sum(z)) / np.sum(np.abs(z))  # do dong pha pilot ca doan
            if coh > best_coh:
                best_coh, dbest = coh, dd
        pilot_idx[b0 - 1: b0 - 1 + m] = np.clip(p + dbest, 1, L)
        cfo_blk[b0 - 1: b0 - 1 + m] = cfo_hz
        p0 = p0 + m * spb * (1 + drift) + dbest
    cfo_hz = np.median(cfo_blk)
    print(f'CFO preamble {cfo_pre:.2f} Hz -> bam theo pilot (min / median / max): '
          f'{cfo_blk.min():.2f} / {cfo_hz:.2f} / {cfo_blk.max():.2f} Hz')

    # ===== 7. Can bang pilot (zero-forcing) + giai dieu che QPSK =====
    eq_all = np.zeros(num_blocks * syms_per_block, dtype=complex)
    block_timing = pilot_idx - (data_start + np.arange(num_blocks) * spb + mround(sps / 2) - 1)
    b = np.arange(1, syms_per_block + 1)
    for blk in range(num_blocks):
        p, cb = pilot_idx[blk], cfo_blk[blk]
        drift = -cb / (Fc + cb)
        g = mfo[p - 1] / pilot_sym  # he so kenh r∠θ tu pilot dau block
        idx_c = np.minimum(p + b * sps + mround(drift * b * sps), L)
        eq_all[blk * syms_per_block: (blk + 1) * syms_per_block] = \
            mfo[idx_c - 1] * np.exp(-1j * 2 * np.pi * cb * (idx_c - p) / Fs) / g
    rx_bits = np.zeros(2 * len(eq_all), dtype=int)
    rx_bits[0::2] = np.real(eq_all) > 0  # b1 -> I
    rx_bits[1::2] = np.imag(eq_all) > 0  # b2 -> Q
    if num_blocks <= 300:
        print(f'Lech dinh pilot so voi danh nghia tung block (mau): {mat2str(block_timing)}')
    else:
        print(f'Lech dinh pilot so voi danh nghia (mau): dau {block_timing[0]}, '
              f'giua {block_timing[(num_blocks + 1) // 2 - 1]}, cuoi {block_timing[-1]}')

    # ===== 8. BER, EVM, loi tung block =====
    num_err = int(np.sum(rx_bits != data_bits))
    ber = num_err / len(data_bits)
    print(f'CFO uoc luong: {cfo_hz:.2f} Hz. So bit loi: {num_err} / {len(data_bits)}, BER = {ber:.4f}')
    ideal = (np.sign(np.real(eq_all)) + 1j * np.sign(np.imag(eq_all))) / np.sqrt(2)
    evm = np.sqrt(np.mean(np.abs(eq_all - ideal) ** 2)) / np.sqrt(np.mean(np.abs(ideal) ** 2))
    print(f'EVM = {100 * evm:.1f} % (SNR ky hieu ~ {-20 * np.log10(evm):.1f} dB)')
    block_err = (rx_bits != data_bits).reshape(num_blocks, -1).sum(axis=1)
    if num_blocks <= 300:
        print(f'Loi tung block (block 1..{num_blocks}): {mat2str(block_err)}')
    else:
        bad = np.flatnonzero(block_err) + 1
        print(f'Block co loi: {len(bad)} / {num_blocks} (block loi dau tien: {mat2str(bad[:1])})')
    return locals()  # nhu workspace MATLAB: Audio_qpsk.py / Plot_qpsk.py lay rx_bits, eq_all, mf_out ...


if __name__ == '__main__':
    r = rx_qpsk(sys.argv[1] if len(sys.argv) > 1 else RX_SOURCE)
    import matplotlib.pyplot as plt
    plt.figure()
    plt.plot(r['eq_all'].real, r['eq_all'].imag, '.', ms=3)
    plt.axis('equal'); plt.grid(True)
    plt.title('Ky hieu du lieu sau can bang pilot (mong doi 4 cum o (+-1+-j)/sqrt(2))')
    plt.figure(); plt.plot(r['rx_bb'].real); plt.title('Baseband I sau ha tan')
    plt.show()
