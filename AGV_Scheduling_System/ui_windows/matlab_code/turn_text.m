% demo_turn_penalty - 婕旂ず鑷€傚簲杞集鎯╃綒闅忚礋杞藉鍔犵殑鍙樺寲瓒嬪娍
% 杩愯姝よ剼鏈彲鐩磋鐪嬪埌鎯╃綒鍊奸殢閲嶉噺澧炲姞鐨勯潪绾挎€у闀匡紝鐗瑰埆鏄噸杞芥椂鐨勬€ュ墽涓婂崌銆?
% 鍚屾椂鐢ㄧ孩鑹茶櫄绾挎鏍囧嚭杞昏浇鍖洪棿锛?~80锛夊拰閲嶈浇鍖洪棿锛?50~200锛夈€?

clear; clc; close all;

% 瀹氫箟閲嶉噺鑼冨洿锛堜緥濡備粠0鍒?00锛岃鐩栬交杞藉埌閲嶈浇锛?
weights = 0:1:200;

% 璋冪敤鍑芥暟璁＄畻瀵瑰簲鐨勬儵缃氬€?
penalties = compute_turn_penalty(weights);  % 浣跨敤榛樿鍙傛暟

% 缁樺埗鏇茬嚎
figure;
plot(weights, penalties, 'b-', 'LineWidth', 1);
xlabel('璐熻浇閲嶉噺 W (kg)');
ylabel('杞集鎯╃綒鍊?TurnPenalty');
title('鑷€傚簲杞集鎯╃綒闅忚礋杞藉彉鍖栨洸绾?);
grid on;
hold on;

% 鏍囨敞鍏抽敭鐐?
plot(0, compute_turn_penalty(0), 'ro', 'MarkerSize', 8, 'DisplayName', '绌鸿浇 (W=0)');
plot(80, compute_turn_penalty(80), 'ms', 'MarkerSize', 8, 'DisplayName', '鍏稿瀷閲嶈浇 (W=80)');
plot(170, compute_turn_penalty(170), 'kd', 'MarkerSize', 8, 'DisplayName', '鏋侀檺閲嶈浇 (W=170)');

% 鑾峰彇褰撳墠鍧愭爣杞磋寖鍥?
ax = gca;
yl = ylim;  % 褰撳墠y杞磋寖鍥?
xlim([-5, 205]);  % 閫傚綋鎵╁睍x杞磋寖鍥翠互渚挎鏄剧ず瀹屾暣

% 缁樺埗杞昏浇鍖洪棿 (0~80) 绾㈣壊铏氱嚎妗?
h1 = rectangle('Position', [0, yl(1), 80, yl(2)-yl(1)], ...
               'EdgeColor', 'r', 'LineStyle', '--', 'LineWidth', 1);
% 娣诲姞鏂囧瓧鏍囨敞
text(40, yl(1)+0.05*(yl(2)-yl(1)), '杞昏浇鍖洪棿', 'Color', 'r', ...
     'HorizontalAlignment', 'center', 'FontSize', 10);

% 缁樺埗閲嶈浇鍖洪棿 (150~200) 绾㈣壊铏氱嚎妗?
h2 = rectangle('Position', [150, yl(1), 50, yl(2)-yl(1)], ...
               'EdgeColor', 'r', 'LineStyle', '--', 'LineWidth', 1);
text(175, yl(1)+0.05*(yl(2)-yl(1)), '閲嶈浇鍖洪棿', 'Color', 'r', ...
     'HorizontalAlignment', 'center', 'FontSize', 10);

% 鍥句緥锛堝彧鏄剧ず鐐规爣璁帮紝涓嶅寘鍚煩褰㈡锛?
legend('Location', 'northwest');

% 杈撳嚭鍏抽敭鏁板€?
fprintf('绌鸿浇 (W=0)   鎯╃綒鍊?= %.2f\n', compute_turn_penalty(0));
fprintf('杞昏浇 (W=40)  鎯╃綒鍊?= %.2f\n', compute_turn_penalty(40));
fprintf('閲嶈浇 (W=80)  鎯╃綒鍊?= %.2f\n', compute_turn_penalty(80));
fprintf('鏋侀檺閲嶈浇(W=170)鎯╃綒鍊?= %.2f\n', compute_turn_penalty(170));
function turnPenalty = compute_turn_penalty(payload_weight, base_penalty, linear_factor, inertia_factor)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
% compute_turn_penalty - 鏍规嵁褰撳墠璐熻浇璁＄畻鑷€傚簲杞集鎯╃綒鍊?
%
% 璇硶: turnPenalty = compute_turn_penalty(payload_weight)
%        turnPenalty = compute_turn_penalty(payload_weight, base_penalty, linear_factor, inertia_factor)
%
% 杈撳叆鍙傛暟:
%   payload_weight - 褰撳墠AGV鐨勮礋杞介噸閲忥紙鍗曚綅涓庨棶棰樺畾涔変竴鑷达級
%   base_penalty   - 锛堝彲閫夛級鍩虹杞集鎯╃綒锛岄粯璁?2.5
%   linear_factor  - 锛堝彲閫夛級绾挎€ц浇鑽峰洜瀛愶紝妯℃嫙鎽╂摝鍔涘鍔狅紝榛樿 0.005
%   inertia_factor - 锛堝彲閫夛級浜岄樁鎯€у洜瀛愶紝妯℃嫙閲嶈浇绂诲績鎯噺锛岄粯璁?0.0001
%
% 杈撳嚭:
%   turnPenalty    - 璁＄畻寰楀埌鐨勬€昏浆寮儵缃氬€?
%
% 璇存槑:
%   鎯╃綒鍊?= base_penalty + linear_factor * W + inertia_factor * W^2
%   璇ュ叕寮忎綋鐜颁簡璐熻浇瀵硅浆寮唬浠风殑褰卞搷锛氳交杞芥椂绾挎€у闀匡紝閲嶈浇鏃堕潪绾挎€ф€ュ墽澧炲姞锛?
%   鐢ㄤ簬寮曞A*绠楁硶鍦ㄩ噸杞芥椂灏介噺閫夋嫨灏戣浆寮殑璺緞锛屼繚闅滃畨鍏ㄣ€?

    % 璁剧疆榛樿鍙傛暟
    if nargin < 2 || isempty(base_penalty), base_penalty = 1; end
    if nargin < 3 || isempty(linear_factor), linear_factor = 0.00001; end
    if nargin < 4 || isempty(inertia_factor), inertia_factor = 3/6400; end

    % 璁＄畻杞集鎯╃綒
    turnPenalty = base_penalty + linear_factor * payload_weight + inertia_factor * (payload_weight.^2);
end


