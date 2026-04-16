% =========================================================================
% MATLAB 修正脚本：绘制三维 MOEA Pareto 前沿对比图
% =========================================================================
clear; clc;
% --- 预设绘图参数 (基于用户代码) ---
marker_size = 50;        % 标记大小
marker_line_width = 0.5; % 线宽
% 基于 image_1.png 和 image_2.png 的示例数据
pareto_baseline_lift = [
1374, 373, 183;
    1381, 379, 178;
    1385, 366, 187;
    1388, 360, 185;
    1398, 365, 179;
    1403, 366, 175;
    1404, 364, 179;
    1424, 358, 183
];
pareto_improved_lift = [
1351, 357, 181;
    1358, 359, 180;
    1363, 358, 179;
    1374, 349, 183;
    1376, 353, 182;
    1385, 353, 180;
    1387, 344, 180;
    1391, 359, 177;
    1404, 342, 177;
    1408, 340, 177;
    1410, 354, 173
];
% --- 绘图逻辑 ---
if ~isempty(pareto_baseline_lift) && ~isempty(pareto_improved_lift)
    % 创建图形窗口
    figure('Name', 'Lift Pareto Front Comparison', 'Color', 'w', 'Position', [240, 240, 1000, 450]);
    
    % --- 子图 1: Baseline ---
    subplot(1, 2, 1);
    scatter3(pareto_baseline_lift(:,1), pareto_baseline_lift(:,2), pareto_baseline_lift(:,3), ...
        marker_size, 'r', '*', 'LineWidth', marker_line_width);
    grid on;
    view(45, 25);
    xlabel('距离 / m', 'FontSize', 12);
    ylabel('时间 / s', 'FontSize', 12);
    zlabel('能耗 / J', 'FontSize', 12);
    % 将标题加粗
    title('(a) NSGA-II 算法', 'FontSize', 12, 'FontWeight', 'bold');
    
    % --- 子图 2: Improved ---
    subplot(1, 2, 2);
    % 为了区分，这里将颜色改为蓝色 ('b')，但标记保持为星号 ('*')
    scatter3(pareto_improved_lift(:,1), pareto_improved_lift(:,2), pareto_improved_lift(:,3), ...
        marker_size, 'b', '*', 'LineWidth', marker_line_width);
    grid on;
    view(45, 25);
    xlabel('距离 / m', 'FontSize', 12);
    ylabel('时间 / s', 'FontSize', 12);
    zlabel('能耗 / J', 'FontSize', 12);
    % 将标题加粗
    title('(b) 改进 NSGA-II 算法', 'FontSize', 12, 'FontWeight', 'bold');
    
end
% 注释掉可能会干扰绘图的函数
% evaluate_and_plot_moea(hist_exp.lift.gen_fronts, hist_base.lift.gen_fronts);