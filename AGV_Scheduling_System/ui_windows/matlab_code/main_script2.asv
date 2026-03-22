%% 主脚本：多AGV路径规划仿真
% 该脚本演示如何使用带转向惩罚和时间窗的A*算法为多台AGV规划无冲突路径。
% 依赖函数：
%   multiAGV_planner.m
%   astar_turn_time.m (内嵌于 multiAGV_planner 中)
%   heuristic.m (内嵌)
%   countTurns.m (自定义，见本文件末尾)

clear; clc; close all;
rng(42);  % 固定随机种子，保证结果可复现

%% 1. 地图设置
mapSize = [50, 50];          % 地图尺寸
p_obstacle = 0.2;            % 障碍物概率
randMat = rand(mapSize);
map = randMat < p_obstacle;   % 障碍为1
map = double(map);            % 转换为double

%% 2. AGV定义
% 每个AGV包含起点、终点、优先级（数值越小优先级越高）
agvs(1) = struct('start', [2, 2], 'goal', [48, 48], 'priority', 1);
agvs(2) = struct('start', [2, 48], 'goal', [48, 2], 'priority', 2);
agvs(3) = struct('start', [25, 2], 'goal', [25, 48], 'priority', 3);

% 确保所有起点和终点不是障碍
for i = 1:length(agvs)
    map(agvs(i).start(1), agvs(i).start(2)) = 0;
    map(agvs(i).goal(1), agvs(i).goal(2)) = 0;
end

%% 3. 转弯惩罚值（所有AGV使用相同值）
turnPenalty = 0.6;
%% 4. 调用多AGV规划器
fprintf('开始规划 %d 台AGV的路径...\n', length(agvs));
try
    [paths, costs] = multiAGV_planner(map, agvs, turnPenalty);
    fprintf('规划成功！\n');
catch ME
    error('规划失败: %s', ME.message);
end

%% 5. 统计信息输出
fprintf('\n===== 路径规划结果 =====\n');
for i = 1:length(paths)
    path = paths{i};
    % 计算转弯次数（仅基于坐标，忽略时间）
    turns = countTurns(path(:,1:2));
    % 路径长度（总代价）已由costs给出
    fprintf('AGV %d (优先级 %d): 总代价 = %.2f, 转弯次数 = %d, 路径长度 = %d 步\n', ...
            i, agvs(i).priority, costs(i), turns, size(path,1)-1);
end

%% 6. 可视化
figure('Name', '多AGV路径规划结果', 'NumberTitle', 'off', 'Position', [100 100 900 700]);

% 显示地图
imagesc(map);
colormap(1-gray);  % 白色自由空间，黑色障碍
hold on;

% 为每个AGV分配不同颜色
colors = lines(length(paths));

% 绘制所有AGV的路径
for i = 1:length(paths)
    path = paths{i};
    % 提取坐标（忽略时间）
    coords = path(:,1:2);
    % 绘制路径线
    plot(coords(:,2), coords(:,1), 'Color', colors(i,:), 'LineWidth', 2);
    % 标记起点和终点
    plot(coords(1,2), coords(1,1), 'o', 'MarkerSize', 8, ...
         'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'k');
    plot(coords(end,2), coords(end,1), 's', 'MarkerSize', 8, ...
         'MarkerFaceColor', colors(i,:), 'MarkerEdgeColor', 'k');
end

% 添加栅格线（可选）
ax = gca;
ax.XTick = 0.5:1:size(map,2)+0.5;
ax.YTick = 0.5:1:size(map,1)+0.5;
ax.XTickLabel = [];
ax.YTickLabel = [];
grid on;
ax.GridColor = [0.7 0.7 0.7];
ax.GridAlpha = 0.5;

% 图例和标题
legendEntries = arrayfun(@(i) sprintf('AGV %d (优先级 %d)', i, agvs(i).priority), ...
                         1:length(agvs), 'UniformOutput', false);
legend([legendEntries, {'起点', '终点'}], 'Location', 'best');
title(sprintf('多AGV路径规划（转弯惩罚 = %.2f）', turnPenalty));
axis equal tight;
hold off;

%% 辅助函数：计算路径转弯次数
function turns = countTurns(path)
    % path: N×2 矩阵 [行,列]
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