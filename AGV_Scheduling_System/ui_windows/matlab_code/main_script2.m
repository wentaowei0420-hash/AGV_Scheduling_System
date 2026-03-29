%% 涓昏剼鏈細澶欰GV璺緞瑙勫垝浠跨湡
% 璇ヨ剼鏈紨绀哄浣曚娇鐢ㄥ甫杞悜鎯╃綒鍜屾椂闂寸獥鐨凙*绠楁硶涓哄鍙癆GV瑙勫垝鏃犲啿绐佽矾寰勩€?
% 渚濊禆鍑芥暟锛?
%   multiAGV_planner.m
%   astar_turn_time.m (鍐呭祵浜?multiAGV_planner 涓?
%   heuristic.m (鍐呭祵)
%   countTurns.m (鑷畾涔夛紝瑙佹湰鏂囦欢鏈熬)

clear; clc; close all;
rng(42);  % 鍥哄畾闅忔満绉嶅瓙锛屼繚璇佺粨鏋滃彲澶嶇幇

%% 1. 鍦板浘璁剧疆
mapSize = [50, 50];          % 鍦板浘灏哄
p_obstacle = 0.2;            % 闅滅鐗╂鐜?
randMat = rand(mapSize);
map = randMat < p_obstacle;   % 闅滅涓?
map = double(map);            % 杞崲涓篸ouble

%% 2. AGV瀹氫箟
% 姣忎釜AGV鍖呭惈璧风偣銆佺粓鐐广€佷紭鍏堢骇锛堟暟鍊艰秺灏忎紭鍏堢骇瓒婇珮锛?
agvs(1) = struct('start', [2, 2], 'goal', [48, 48], 'priority', 1);
agvs(2) = struct('start', [2, 48], 'goal', [48, 2], 'priority', 2);
agvs(3) = struct('start', [25, 2], 'goal', [25, 48], 'priority', 3);

% 纭繚鎵€鏈夎捣鐐瑰拰缁堢偣涓嶆槸闅滅
for i = 1:length(agvs)
    map(agvs(i).start(1), agvs(i).start(2)) = 0;
    map(agvs(i).goal(1), agvs(i).goal(2)) = 0;
end

%% 3. 杞集鎯╃綒鍊硷紙鎵€鏈堿GV浣跨敤鐩稿悓鍊硷級
turnPenalty = 0.6;
%% 4. 璋冪敤澶欰GV瑙勫垝鍣?
fprintf('寮€濮嬭鍒?%d 鍙癆GV鐨勮矾寰?..\n', length(agvs));
try
    [paths, costs] = multiAGV_planner(map, agvs, turnPenalty);
    fprintf('瑙勫垝鎴愬姛锛乗n');
catch ME
    error('瑙勫垝澶辫触: %s', ME.message);
end

%% 5. 缁熻淇℃伅杈撳嚭
fprintf('\n===== 璺緞瑙勫垝缁撴灉 =====\n');
for i = 1:length(paths)
    path = paths{i};
    % 璁＄畻杞集娆℃暟锛堜粎鍩轰簬鍧愭爣锛屽拷鐣ユ椂闂达級
    turns = countTurns(path(:,1:2));
    % 璺緞闀垮害锛堟€讳唬浠凤級宸茬敱costs缁欏嚭
    fprintf('AGV %d (浼樺厛绾?%d): 鎬讳唬浠?= %.2f, 杞集娆℃暟 = %d, 璺緞闀垮害 = %d 姝n', ...
            i, agvs(i).priority, costs(i), turns, size(path,1)-1);
end

%% 6. 鍙鍖?
figure('Name', '澶欰GV璺緞瑙勫垝缁撴灉', 'NumberTitle', 'off', 'Position', [100 100 900 700]);

% 鏄剧ず鍦板浘
imagesc(map);
colormap(1-gray);  % 鐧借壊鑷敱绌洪棿锛岄粦鑹查殰纰?
hold on;

% 涓烘瘡涓狝GV鍒嗛厤涓嶅悓棰滆壊
colors = lines(length(paths));

% 缁樺埗鎵€鏈堿GV鐨勮矾寰?
for i = 1:length(paths)
    path = paths{i};
    % 鎻愬彇鍧愭爣锛堝拷鐣ユ椂闂达級
    coords = path(:,1:2);
    % 缁樺埗璺緞绾?
    plot(coords(:,2), coords(:,1), 'Color', colors(i,:), 'LineWidth', 1);
    % 鏍囪璧风偣鍜岀粓鐐?
    plot(coords(1,2), coords(1,1), 'o', 'MarkerSize', 8, ...
         'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'k');
    plot(coords(end,2), coords(end,1), 's', 'MarkerSize', 8, ...
         'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'k');
end

% 娣诲姞鏍呮牸绾匡紙鍙€夛級
ax = gca;
ax.XTick = 0.5:1:size(map,2)+0.5;
ax.YTick = 0.5:1:size(map,1)+0.5;
ax.XTickLabel = [];
ax.YTickLabel = [];
grid on;
ax.GridColor = [0.7 0.7 0.7];
ax.GridAlpha = 0.5;

% 鍥句緥鍜屾爣棰?
legendEntries = arrayfun(@(i) sprintf('AGV %d (浼樺厛绾?%d)', i, agvs(i).priority), ...
                         1:length(agvs), 'UniformOutput', false);
legend([legendEntries, {'璧风偣', '缁堢偣'}], 'Location', 'best');
title(sprintf('澶欰GV璺緞瑙勫垝锛堣浆寮儵缃?= %.2f锛?, turnPenalty));
axis equal tight;
hold off;

%% 杈呭姪鍑芥暟锛氳绠楄矾寰勮浆寮鏁?
function turns = countTurns(path)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % path: N脳2 鐭╅樀 [琛?鍒梋
    turns = 0;
    if size(path, 1) > 2
        prev_dir = path(2, :) - path(1, :);
        for i = 3:size(path, 1)
            curr_dir = path(i, :) - path(i-1, :);
            if ~isequal(curr_dir, prev_dir)
                turns = turns + 1;
            end
            prev_dir = curr_dir;
        end
    end
end


