function start_idx = uw_sync_reference(y, NFFT, nGI)
%UW_SYNC_REFERENCE "Reference scheme [7]" ma bai bao Nguyen Van Huy so
% sanh - chinh la thuat toan da co san trong
% Thay_Khuong/Matlab Programs/OFDM_DOPPLER_STUDENTS/reciever.m:1241-1260
% (bien syn/syn2 trong file do), chi dung lai o buoc SYN=Q.*R, KHONG co
% cac buoc CQ/CR/C moi cua bai bao (xem uw_sync.m). Dung lam baseline de
% so sanh Fig.8.
%
% Tra ve NaN neu khong tim thay diem vuot nguong (that bai dong bo hoan
% toan - thuong xay ra o SNR thap, dung y dinh cua bai bao).

y = y(:);
K = 2*NFFT + nGI + 1;
L = length(y);
n_i = L - K + 1;
if n_i < 1
    error('uw_sync_reference: tin hieu qua ngan (can it nhat %d mau, co %d).', K, L);
end

P = zeros(n_i, 1);
R = zeros(n_i, 1);
for i = 1:n_i
    w1 = y(i:i+nGI-1);
    w2 = y(i+K-nGI:i+K-1);
    P(i) = sum(abs(w1 - w2));
    R(i) = abs(w1' * w2);
end
Q = max(P) - P;
SYN = Q .* R;

bb = find(SYN > max(SYN)/3); % nguong 1/3 dinh cuc dai, dung y reciever.m
if isempty(bb)
    start_idx = NaN;
    return;
end
search_end = min(bb(1) + floor(K/2), n_i);
[~, start_idx] = max(SYN(1:search_end));
end
