"""Rx.py - ban Python cua Rx.m (dich tung dong; giai thich chi tiet xem Rx.m).

    uv run Rx.py [loopback|record|file]   # mac dinh = RX_SOURCE ben duoi; record can: uv sync

Khac Rx.m: luon nap tx_params.mat (Python khong co workspace con sot bien -> het loi BER~0.5 do ghep nham).
Vi tri mau giu CHI SO 1 nhu MATLAB; chi tru 1 khi lay phan tu mang numpy (x[i-1]).
"""
import os
import sys
import numpy as np
from scipy.io import loadmat, wavfile
from scipy.signal import correlate

D = os.path.dirname(os.path.abspath(__file__))
RX_SOURCE = 'file'  # 'loopback' / 'record' / 'file' (nhu Rx.m)


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


def rx(source=RX_SOURCE):
    P = loadmat(os.path.join(D, 'tx_params.mat'), squeeze_me=True)
    Fs, Fc = float(P['Fs']), float(P['Fc'])
    sps, bits_per_block, num_blocks = int(P['sps']), int(P['bits_per_block']), int(P['num_blocks'])
    pilot_val = float(P['pilot_val'])
    preamble_bits = np.atleast_1d(P['preamble_bits']).astype(float)
    data_bits = np.atleast_1d(P['data_bits']).astype(int)
    tx_signal = np.atleast_1d(P['tx_signal']).astype(float)

    if source == 'loopback':
        rx_raw = tx_signal.copy()
    elif source == 'file':
        rx_raw = wav_read(os.path.join(D, 'rx_debug.wav'))
    else:
        import sounddevice as sd  # chi can khi thu that: uv sync
        record_time = 5  # chua biet tx_signal dai bao nhieu, mac dinh 5 s
        input_device_id = None  # None = thiet bi mac dinh; sai thiet bi thi xem sd.query_devices()
        print('Bat dau phat tx_cable.wav tren dien thoai ngay bay gio...')
        rx_raw = sd.rec(int(record_time * Fs), samplerate=int(Fs), channels=1, dtype='float64',
                        device=input_device_id)
        sd.wait()
        rx_raw = rx_raw[:, 0]
        print(f'Muc tin hieu thu duoc: peak={np.max(np.abs(rx_raw)):.4f}, rms={np.sqrt(np.mean(rx_raw**2)):.4f} '
              '(gan 0 nghia la thu nham thiet bi hoac chua cam cap)')
        wavfile.write(os.path.join(D, 'rx_debug.wav'), int(Fs),
                      np.round(np.clip(rx_raw, -1, 32767 / 32768) * 32768).astype(np.int16))  # de soi lai neu decode sai

    # Ha tan xuong baseband phuc (I/Q)
    t = np.arange(len(rx_raw)) / Fs
    rx_bb = rx_raw * np.exp(-1j * 2 * np.pi * Fc * t)

    # Loc phoi hop (integrate-and-dump)
    mf_out = conv_same(rx_bb, np.ones(sps) / sps)

    # Dong bo: tuong quan preamble, quet luoi CFO
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
        c_try = correlate(derot, ref_pad, 'full')  # c_try[i] <-> lag i-(N-1)
        pk_try = int(np.argmax(np.abs(c_try)))
        if abs(c_try[pk_try]) > best_peak:
            best_peak, c, pk = abs(c_try[pk_try]), c_try, pk_try
    start_idx = pk - (N - 1) + 1  # chi so 1 nhu MATLAB
    print(f'Dong bo: peak/median tuong quan = {best_peak / np.median(np.abs(c)):.1f} '
          '(cang cao cang chac chan tim dung preamble)')
    if start_idx < 1 or start_idx + len(preamble_ref) - 1 > N:
        raise RuntimeError('Khong tim thay preamble trong tin hieu thu duoc.')

    # CFO tu preamble: lech pha giua 2 ky hieu lien tiep
    preamble_seg = mf_out[start_idx - 1: start_idx - 1 + len(preamble_ref)]
    idx_c = np.arange(len(preamble_bits)) * sps + mround(sps / 2)
    sym_val = preamble_seg[idx_c - 1] * preamble_sym
    cfo_hz = np.angle(np.mean(sym_val[1:] * np.conj(sym_val[:-1]))) / (2 * np.pi * sps / Fs)

    # Bu CFO tu vi tri preamble tro di
    n = np.arange(N - start_idx + 1)
    mf_corr = mf_out[start_idx - 1:] * np.exp(-1j * 2 * np.pi * cfo_hz * n / Fs)

    # Lay mau tung ky hieu, ZF bang pilot tung block, early-late +-search_win quanh vi tri du doan
    data_start = len(preamble_ref) + 1
    pilot_sym = 2 * pilot_val - 1
    rx_bits = np.zeros(num_blocks * bits_per_block, dtype=int)
    drift = -cfo_hz / (Fc + cfo_hz)  # do troi dong ho suy ra tu CFO
    search_win = 3
    block_timing = np.zeros(num_blocks, dtype=int)
    b = np.arange(1, bits_per_block + 1)
    for blk in range(num_blocks):
        blk_off_nom = data_start + blk * (bits_per_block + 1) * sps
        pilot_nom = blk_off_nom + mround(sps / 2) - 1
        pilot_idx_nom = pilot_nom + mround(drift * pilot_nom)
        cand = pilot_idx_nom + np.arange(-search_win, search_win + 1)
        cand = cand[(cand >= 1) & (cand <= len(mf_corr))]
        pilot_idx = cand[np.argmax(np.abs(mf_corr[cand - 1]))]
        timing_off = pilot_idx - pilot_nom
        block_timing[blk] = timing_off
        blk_off = blk_off_nom + timing_off
        g = mf_corr[blk_off + mround(sps / 2) - 2] / pilot_sym  # pilot o dau block
        idx_c = blk_off + b * sps + mround(sps / 2) - 1 + mround(drift * b * sps)  # drift trong block
        rx_bits[blk * bits_per_block: (blk + 1) * bits_per_block] = np.real(mf_corr[idx_c - 1] / g) > 0
    print(f'Lech dinh pilot tich luy tung block (mau, +-{search_win} la cua so tim): {mat2str(block_timing)}')

    num_err = int(np.sum(rx_bits != data_bits))
    print(f'CFO uoc luong: {cfo_hz:.2f} Hz. So bit loi: {num_err} / {len(data_bits)}, '
          f'BER = {num_err / len(data_bits):.4f}')
    block_err = (rx_bits != data_bits).reshape(num_blocks, -1).sum(axis=1)  # loi tang dan ve cuoi = clock drift
    print(f'Loi tung block (block 1..{num_blocks}): {mat2str(block_err)}')
    return locals()


if __name__ == '__main__':
    r = rx(sys.argv[1] if len(sys.argv) > 1 else RX_SOURCE)
    import matplotlib.pyplot as plt
    z = r['mf_corr'][r['data_start'] - 1:]
    plt.figure(); plt.plot(z.real, z.imag, '.', ms=2); plt.grid(True)
    plt.title('Ky hieu du lieu sau can bang pilot')
    plt.figure(); plt.plot(r['rx_bb'].real); plt.title('Baseband I sau ha tan')
    plt.show()
