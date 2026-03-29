style = agv_plot_theme();
init_agv_plot_defaults(style);
% 瀹氫箟鏁版嵁
C1 = [4 14 10 9 1 11 5 2 10 3 7 4 7 11];
P1 = [8 14 3 9 1 6 5 12 10 2 7 4 13 11];
P2 = [4 12 10 5 9 11 6 2 13 3 14 1 7 8];
C2 = [8 12 3 5 9 6 6 12 13 2 14 1 13 8];

% 灏嗘墍鏈夋暟鎹粍鍚堟垚涓€涓煩闃?
data = [C1; P1; P2; C2];

% 鍒涘缓鐑浘鎴栬〃鏍硷紙杩欓噷浣跨敤鍥惧儚鏂瑰紡鏄剧ず锛?
figure;
imagesc(data); % 鐢ㄩ鑹叉繁娴呰〃绀烘暟瀛楀ぇ灏忥紝浣滀负搴曞眰鍙傝€?
colormap(gca, 'parula'); % 璁剧疆棰滆壊
colorbar; % 鏄剧ず棰滆壊鏉?

% 鍦ㄦ瘡涓崟鍏冩牸涓婂彔鍔犳樉绀烘暟瀛?
[r, c] = size(data);
for i = 1:r
    for j = 1:c
        text(j, i, num2str(data(i, j)), 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'Color', 'white');
    end
end

% 娣诲姞鏍囩
yticks(1:4);
yticklabels({'C鈧?, 'P鈧?, 'P鈧?, 'C鈧?});
xlabel('鍩哄洜浣嶇偣');
title('鍥?3.5 浠诲姟鍩哄洜涓蹭氦鍙夎繃绋?(绀烘剰鍥炬鏋?');

% 娉ㄦ剰锛氳繖绉嶆柟寮忓彧鑳界敓鎴愯〃鏍煎簳鍥撅紝
% 閭ｄ簺绾㈣壊鐨勪氦鍙夌澶村拰鑺辨嫭鍙蜂粛鐒堕渶瑕佸湪 MATLAB 鐨勭粯鍥剧紪杈戝櫒涓墜鍔ㄦ坊鍔狅紝
% 鎴栬€呭湪 PowerPoint 涓墦寮€鐢熸垚鐨勫浘鐗囩户缁紪杈戙€
