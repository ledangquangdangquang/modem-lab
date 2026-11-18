function x_td = build_ofdm_symbol(c, nGI)
%BUILD_OFDM_SYMBOL Dung 1 ky hieu OFDM tu du lieu tan so, dung cong thuc
% cua bai bao "A Multi-Stage Method for Time Synchronization in Acoustic
% Underwater Communications" (Nguyen Van Huy et al.) va khop voi cach lam
% da co san trong Thay_Khuong/Matlab Programs/OFDM_DOPPLER_STUDENTS/transfer.m:372,381.
%
% c   : vector tan so (1 x NFFT), du lieu tren cac song mang duong (khong
%       gom DC). NFFT = length(c).
% nGI : do dai khoang bao ve (cyclic prefix).
%
% D = [0, c, conj(fliplr(c))] doi xung lien hop -> IFFT ra tin hieu THUC
% (khong can tach rieng I/Q khi phat qua loa/transducer). Sau do chen GI
% bang cach copy nGI mau cuoi cua ky hieu IFFT len dau (cyclic prefix
% chuan). Do dai ra: nGI + 2*NFFT + 1 (= K trong tai lieu, xem uw_sync.m).

c = c(:).'; % ep thanh hang
D = [0, c, fliplr(conj(c))];
x_full = real(ifft(D)); % doi xung lien hop nen phan ao ~0 (chi con sai so lam tron)
x_td = [x_full(end-nGI+1:end), x_full];
end
