% demo_turn_penalty - 演示自适应转弯惩罚随负载增加的变化趋势
% 运行此脚本可直观看到惩罚值随重量增加的非线性增长，特别是重载时的急剧上升。
% 同时用红色虚线框标出轻载区间（0~80）和重载区间（150~200）。

clear; clc; close all;

% 定义重量范围（例如从0到200，覆盖轻载到重载）
weights = 0:1:200;

% 调用函数计算对应的惩罚值
penalties = compute_turn_penalty(weights);  % 使用默认参数

% 绘制曲线
figure;
plot(weights, penalties, 'b-', 'LineWidth', 2);
xlabel('负载重量 W (kg)');
ylabel('转弯惩罚值 TurnPenalty');
title('自适应转弯惩罚随负载变化曲线');
grid on;
hold on;

% 标注关键点
plot(0, compute_turn_penalty(0), 'ro', 'MarkerSize', 8, 'DisplayName', '空载 (W=0)');
plot(80, compute_turn_penalty(80), 'ms', 'MarkerSize', 8, 'DisplayName', '典型重载 (W=80)');
plot(170, compute_turn_penalty(170), 'kd', 'MarkerSize', 8, 'DisplayName', '极限重载 (W=170)');

% 获取当前坐标轴范围
ax = gca;
yl = ylim;  % 当前y轴范围
xlim([-5, 205]);  % 适当扩展x轴范围以便框显示完整

% 绘制轻载区间 (0~80) 红色虚线框
h1 = rectangle('Position', [0, yl(1), 80, yl(2)-yl(1)], ...
               'EdgeColor', 'r', 'LineStyle', '--', 'LineWidth', 1.5);
% 添加文字标注
text(40, yl(1)+0.05*(yl(2)-yl(1)), '轻载区间', 'Color', 'r', ...
     'HorizontalAlignment', 'center', 'FontSize', 10);

% 绘制重载区间 (150~200) 红色虚线框
h2 = rectangle('Position', [150, yl(1), 50, yl(2)-yl(1)], ...
               'EdgeColor', 'r', 'LineStyle', '--', 'LineWidth', 1.5);
text(175, yl(1)+0.05*(yl(2)-yl(1)), '重载区间', 'Color', 'r', ...
     'HorizontalAlignment', 'center', 'FontSize', 10);

% 图例（只显示点标记，不包含矩形框）
legend('Location', 'northwest');

% 输出关键数值
fprintf('空载 (W=0)   惩罚值 = %.2f\n', compute_turn_penalty(0));
fprintf('轻载 (W=40)  惩罚值 = %.2f\n', compute_turn_penalty(40));
fprintf('重载 (W=80)  惩罚值 = %.2f\n', compute_turn_penalty(80));
fprintf('极限重载(W=170)惩罚值 = %.2f\n', compute_turn_penalty(170));
function turnPenalty = compute_turn_penalty(payload_weight, base_penalty, linear_factor, inertia_factor)
% compute_turn_penalty - 根据当前负载计算自适应转弯惩罚值
%
% 语法: turnPenalty = compute_turn_penalty(payload_weight)
%        turnPenalty = compute_turn_penalty(payload_weight, base_penalty, linear_factor, inertia_factor)
%
% 输入参数:
%   payload_weight - 当前AGV的负载重量（单位与问题定义一致）
%   base_penalty   - （可选）基础转弯惩罚，默认 2.5
%   linear_factor  - （可选）线性载荷因子，模拟摩擦力增加，默认 0.005
%   inertia_factor - （可选）二阶惯性因子，模拟重载离心惯量，默认 0.0001
%
% 输出:
%   turnPenalty    - 计算得到的总转弯惩罚值
%
% 说明:
%   惩罚值 = base_penalty + linear_factor * W + inertia_factor * W^2
%   该公式体现了负载对转弯代价的影响：轻载时线性增长，重载时非线性急剧增加，
%   用于引导A*算法在重载时尽量选择少转弯的路径，保障安全。

    % 设置默认参数
    if nargin < 2 || isempty(base_penalty), base_penalty = 1; end
    if nargin < 3 || isempty(linear_factor), linear_factor = 0.00001; end
    if nargin < 4 || isempty(inertia_factor), inertia_factor = 3/6400; end

    % 计算转弯惩罚
    turnPenalty = base_penalty + linear_factor * payload_weight + inertia_factor * (payload_weight.^2);
end
