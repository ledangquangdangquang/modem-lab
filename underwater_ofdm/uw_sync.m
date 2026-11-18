function [start_idx, dbg] = uw_sync(y, NFFT, nGI, thresh_frac)
%UW_SYNC Dong bo nhieu giai doan (multi-stage) theo bai bao "A Multi-Stage
% Method for Time Synchronization in Acoustic Underwater Communications"
% (Nguyen Van Huy et al., HUST), muc III, cong thuc (2)-(8).
%
% y           : tin hieu thu duoc (vector cot hoac hang, THUC).
% NFFT, nGI   : tham so OFDM (xem build_ofdm_symbol.m). K = 2*NFFT+nGI+1
%               la do dai 1 ky hieu OFDM (ke ca GI) - cung la khoang cach
%               giua GI dau va GI cuoi cua CUNG mot ky hieu.
% thresh_frac : nguong cat, ty le tren dinh cuc dai da chuan hoa cua C(k)
%               (mac dinh 0.05 = 5% nhu bai bao).
%
% Tra ve start_idx: vi tri mau (trong y) cua GI dau tien tim duoc.
% dbg: struct chua P,Q,R,SYN,CQ,CR,C_norm de ve lai hinh kieu Fig.3-7.
%
% ponytail: cong thuc (6)-(7) trong bai bao bi OCR lam mat ky hieu gioi han
% tong, nen "tuong quan SYN voi Q/R" co the hieu nhieu cach. Da thu cach
% hieu "tuong quan toan cuc" (conv(SYN,Q,'same') tren toan bo do dai n_i)
% truoc, nhung bi loang/nhoe hoan toan: Q co do dai bang ca tin hieu nen
% phep conv do khong con la phep loc CUC BO, no tron gia tri qua toan bo
% truc i va pha vo tinh dinh vi. Cach hieu duoc dung o day thay vao do:
% CQ(i), CR(i) la TONG CUA SO CUC BO (do dai nGI, cung quy uoc cua so nhu
% P/R o cong thuc 2/4) cua SYN(j)*Q(j) va SYN(j)*R(j) - giu tinh chat "chi
% khuech dai/giam nhieu cuc bo" ma khong lam mat vi tri. Neu sau nay co
% ban chuan/code goc de doi chieu cong thuc that, kiem tra lai buoc nay.

if nargin < 4
    thresh_frac = 0.05;
end
y = y(:);
K = 2*NFFT + nGI + 1;
L = length(y);
n_i = L - K + 1; % so vi tri i hop le (can du K mau tu i tro di)
if n_i < 1
    error('uw_sync: tin hieu qua ngan (can it nhat %d mau, co %d).', K, L);
end

P = zeros(n_i, 1);
R = zeros(n_i, 1);
for i = 1:n_i
    w1 = y(i:i+nGI-1);
    w2 = y(i+K-nGI:i+K-1); % cach w1 dung 2*NFFT+1 mau (= K-nGI), dung cong thuc (2)
    P(i) = sum(abs(w1 - w2));
    R(i) = abs(w1' * w2);
end
Q = max(P) - P;          % cong thuc (3)
SYN = Q .* R;             % cong thuc (5), = "reference scheme [7]" (xem uw_sync_reference.m)

% cong thuc (6)-(7), xem ghi chu ponytail o tren: tong cua so cuc bo do
% dai nGI (cua so CAN GIUA tai i, khong lech ve mot phia) de khong lam
% lech vi tri dinh - thu ban dau dung cua so chi huong toi (i..i+nGI-1)
% lam dinh bi keo lui gan ca nGI mau so voi vi tri that.
CQ = movsum(SYN .* Q, nGI);
CR = movsum(SYN .* R, nGI);
C = CQ .* CR + CQ + CR;             % cong thuc (8)
C_norm = abs(C) / max(abs(C));

[~, max_i] = max(C_norm);
thresh = thresh_frac;
idx = max_i;
while idx - K >= 1 && C_norm(idx - K) >= thresh
    idx = idx - K; % lui dan tung K mau (1 ky hieu OFDM) cho toi vi tri cuoi cung con vuot nguong
end
start_idx = idx;

dbg = struct('P', P, 'Q', Q, 'R', R, 'SYN', SYN, 'CQ', CQ, 'CR', CR, ...
    'C_norm', C_norm, 'K', K);
end
