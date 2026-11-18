"""Audio_qpsk.py - ban Python cua Audio_qpsk.m: gui am thanh qua modem QPSK (am thanh -> 8 bit/mau -> khung QPSK).

    uv run Audio_qpsk.py tx                 # sinh tx_cable_audio.wav + tx_params_audio.mat tu giong.wav, 1 s
    uv run Audio_qpsk.py tx file.wav 3      # file cua ban, 3 s dau
    uv run Audio_qpsk.py rx                 # thu that qua cap, giai ma bang Rx_qpsk.py, ghi + phat rx_audio.wav
    uv run Audio_qpsk.py rx loopback        # tu-kiem-tra (BER phai = 0)
    uv run Audio_qpsk.py rx file            # giai ma lai rx_debug_audio.wav

Khac Audio_qpsk.m: mac dinh la giong.wav (Python khong co handel.mat cua MATLAB).
Chu y: 'tx' ghi de tx_params_audio.mat -> ban thu that rx_debug_audio.wav cu khong giai ma duoc nua.
"""
import os
import sys
from math import gcd
import numpy as np
from scipy.io import savemat, wavfile
from scipy.signal import resample_poly
from Rx_qpsk import rx_qpsk, mround

D = os.path.dirname(os.path.abspath(__file__))
params_file = 'tx_params_audio.mat'
rx_wav = 'rx_debug_audio.wav'


def audio_tx(audio_file='giong.wav', audio_sec=1.0):
    audio_fs = 8000.0   # tan so lay mau am thanh gui di
    Fs, Fc = 48000.0, 8000.0
    baud_rate = 4000.0  # da chay dung qua cap that; ha xuong 1000 neu kenh khac cho BER > 0
    sps = int(Fs / baud_rate)
    syms_per_block = 5
    pilot_sym = (1 + 1j) / np.sqrt(2)

    x_fs, x = wavfile.read(audio_file)
    x = x.astype(float).reshape(len(x), -1).mean(axis=1)  # mono (thang do khong quan trong: chuan hoa ben duoi)
    g = gcd(int(audio_fs), int(x_fs))
    x = resample_poly(x, int(audio_fs) // g, int(x_fs) // g)
    x = x[:round(audio_sec * audio_fs)]
    audio_q = mround((x / np.max(np.abs(x)) + 1) / 2 * 255).astype(np.uint8)  # luong tu 8 bit
    n_audio = len(audio_q)
    audio_bits = np.unpackbits(audio_q).astype(float)  # MSB truoc

    bits_per_block = 2 * syms_per_block
    n_pad = -len(audio_bits) % bits_per_block
    data_bits = np.concatenate([audio_bits, np.zeros(n_pad)])
    num_blocks = len(data_bits) // bits_per_block
    preamble_bits = np.random.default_rng().integers(0, 2, 50).astype(float)

    # Cung anh xa Gray va bo cuc khung [pilot, 5 ky hieu] nhu Tx_qpsk.py
    data_syms = ((2 * data_bits[0::2] - 1) + 1j * (2 * data_bits[1::2] - 1)) / np.sqrt(2)
    blocks = np.hstack([np.full((num_blocks, 1), pilot_sym), data_syms.reshape(num_blocks, syms_per_block)])
    symbols = np.concatenate([2 * preamble_bits - 1, blocks.ravel()])
    baseband = np.repeat(symbols, sps)
    t = np.arange(len(baseband)) / Fs
    passband = np.real(baseband * np.exp(1j * 2 * np.pi * Fc * t))
    pad = np.zeros(round(0.5 * Fs))
    tx_signal = np.concatenate([pad, passband, pad])
    tx_signal = 0.9 * tx_signal / np.max(np.abs(tx_signal))

    wavfile.write(os.path.join(D, 'tx_cable_audio.wav'), int(Fs), np.round(tx_signal * 32768).astype(np.int16))
    savemat(os.path.join(D, params_file), dict(
        Fs=Fs, Fc=Fc, baud_rate=baud_rate, sps=float(sps), syms_per_block=float(syms_per_block),
        num_blocks=float(num_blocks), pilot_sym=pilot_sym, preamble_bits=preamble_bits, data_bits=data_bits,
        tx_signal=tx_signal, audio_fs=audio_fs, audio_q=audio_q, n_audio=float(n_audio)))
    print(f'Da ghi tx_cable_audio.wav: {n_audio} mau am thanh = {len(audio_bits)} bit, {num_blocks} block, '
          f'khung dai {len(tx_signal) / Fs:.1f} s.')
    print('Copy sang dien thoai, phat, roi chay: uv run Audio_qpsk.py rx')


def audio_rx(audio_src='record'):
    from scipy.io import loadmat
    S = loadmat(os.path.join(D, params_file), squeeze_me=True)
    record_time = len(S['tx_signal']) / float(S['Fs']) + 3  # khung dai vai chuc giay
    r = rx_qpsk(audio_src, params_file, rx_wav, record_time)

    n_audio, audio_fs = int(S['n_audio']), float(S['audio_fs'])
    q = np.packbits(r['rx_bits'][:8 * n_audio].astype(np.uint8))
    print(f'Mau am thanh sai: {int(np.sum(q != np.atleast_1d(S["audio_q"])))} / {n_audio}')
    y = 2 * q / 255.0 - 1
    wavfile.write(os.path.join(D, 'rx_audio.wav'), int(audio_fs), np.round(y * 32767).astype(np.int16))
    try:
        import sounddevice as sd  # khong co thi chi ghi file, tu mo rx_audio.wav de nghe
        sd.play(y, int(audio_fs)); sd.wait()
    except ImportError:
        print('Khong co sounddevice (uv sync): mo rx_audio.wav de nghe.')


if __name__ == '__main__':
    a = sys.argv[1:]
    if not a or a[0] not in ('tx', 'rx'):
        sys.exit(__doc__)
    if a[0] == 'tx':
        audio_tx(a[1] if len(a) > 1 else os.path.join(D, 'giong.wav'), float(a[2]) if len(a) > 2 else 1.0)
    else:
        audio_rx(a[1] if len(a) > 1 else 'record')
