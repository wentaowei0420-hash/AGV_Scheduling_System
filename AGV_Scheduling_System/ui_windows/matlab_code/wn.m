% =========================================================================
% 鍔ㄦ€佽嚜閫傚簲鏉冮噸绯绘暟鍙鍖栧垎鏋?(瀛︽湳绾噣鐗?
% 鏈剼鏈彁鍙栦簡鏀硅繘 A* 绠楁硶涓殑鍔ㄦ€佹潈閲嶈绠楅€昏緫锛屽苟缁樺埗鍏堕殢璺濈琛板噺鐨勬洸绾?
% =========================================================================
clear; clc; close all;

%% 1. 妯℃嫙鍦烘櫙鍙傛暟璁剧疆
start_point = [5, 5];       % 鍋囪璧风偣鍧愭爣
goal_point  = [45, 45];     % 鍋囪缁堢偣鍧愭爣

% 璁＄畻璧风偣鍒扮粓鐐圭殑鎬昏窛绂?(浣滀负褰掍竴鍖栧熀鍑?
dist_start_to_goal = sqrt((start_point(1) - goal_point(1))^2 + ...
                          (start_point(2) - goal_point(2))^2);

if dist_start_to_goal == 0
    dist_start_to_goal = 1e-6; % 闃叉闄ら浂
end

% 鍘嬬缉绯绘暟
compression_factor = 0.4; 

%% 2. 鐢熸垚妯℃嫙璺濈鏁版嵁
dist_current_to_goal = linspace(dist_start_to_goal, 0, 100);

%% 3. 璋冪敤鏍稿績鏉冮噸鍑芥暟杩涜璁＄畻
w_n = calculate_dynamic_weight(dist_current_to_goal, dist_start_to_goal, compression_factor);

%% 4. 缁樺浘鍙鍖?(绗﹀悎瀛︽湳鏈熷垔/椤剁骇绛旇京瑙勮寖)
% 鍒涘缓鐧藉簳鍥惧舰
figure('Name', '鑷€傚簲鍔ㄦ€佹潈閲嶇郴鏁拌“鍑忔洸绾?, 'Color', 'w', 'Position', [100, 100, 600, 450]);

% 缁樺埗涓绘洸绾?(鏍囧噯瀛︽湳钃?
plot(dist_current_to_goal, w_n, '-', 'Color', '#0072BD', 'LineWidth', 1, 'DisplayName', '鍔ㄦ€佹潈閲?w(n)');
hold on;

% 缁樺埗鍩哄噯绾?(鏍囧噯 A* 鏉冮噸)
yline(1.0, '--', 'Color', '#7E2F8E', 'LineWidth', 1, 'DisplayName', '鏍囧噯 A* 鏉冮噸 (w=1)');

% 缁樺埗鍏抽敭鑺傜偣 (閲囩敤绌哄績鏍囪锛岀ǔ閲嶄笉鑺卞摠)
plot(dist_start_to_goal, w_n(1), 's', 'MarkerSize', 7, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', '#D95319', 'LineWidth', 1, 'DisplayName', '璧风偣 (鍋忓悜璐┆鎼滅储)');
plot(0, w_n(end), 'o', 'MarkerSize', 7, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', '#0072BD', 'LineWidth', 1, 'DisplayName', '缁堢偣 (鍥炲綊绮剧‘瀵讳紭)');

% 鍥捐〃鍩虹淇グ
grid on;
box on; % 鍔犱笂鍏ㄥ皝闂竟妗嗭紝绗﹀悎璁烘枃瑙勮寖
set(gca, 'XDir', 'reverse'); % X杞村弽鍚戯細妯℃嫙杞﹁締浠庤繙鍒拌繎闈犺繎鐩爣

% 鍔ㄦ€佽皟鏁?X 杞存樉绀鸿寖鍥?(鐣欏嚭涓€鐐硅竟缂樼┖鐧斤紝涓嶈椤舵牸)
xlim([0, ceil(dist_start_to_goal/10)*10]); 
ylim([0.8, max(w_n) + 0.1]);

% 瀛椾綋涓庢爣绛捐鑼冨寲 (涓嫳鏂囧瓧浣撳垎绂?
xlabel('褰撳墠鑺傜偣璺濈鐩爣鐨勮窛绂?D (m)', 'FontSize', 11, 'FontName', 'SimSun');
ylabel('鍚彂鍑芥暟鏉冮噸绯绘暟 w(n)', 'FontSize', 11, 'FontName', 'SimSun');

% 鍧愭爣杞村埢搴﹀瓧浣撹缃?
ax = gca;
ax.FontSize = 11;
ax.FontName = 'Times New Roman'; 
ax.LineWidth = 1;

% 鍥句緥淇グ
lgd = legend('Location', 'northwest');
lgd.FontSize = 10;
lgd.FontName = 'SimSun';
legend('boxoff'); % 鍘婚櫎鍥句緥杈规锛岀敾闈㈡洿骞插噣

%% =========================================================================
% 鏍稿績鍑芥暟鎻愬彇锛氳绠楀姩鎬佹潈閲?w(n)
% =========================================================================
function w = calculate_dynamic_weight(dist_curr, dist_total, compress_factor)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % 1. 璁＄畻璺濈鍗犳瘮 (褰掍竴鍖栬窛绂?
    dist_ratio = dist_curr ./ dist_total;
    
    % 2. 璁＄畻鍘熷鎸囨暟鍥犲瓙 (a_raw)
    a_raw = exp(dist_ratio)-1 ;
    
    % 3. 搴旂敤鍘嬬缉绯绘暟 (a_compressed)
    a_compressed = a_raw * compress_factor;
    
    % 4. 璁＄畻鏈€缁堢殑鎬绘潈閲?w(n)
    w = a_compressed+1;
end



