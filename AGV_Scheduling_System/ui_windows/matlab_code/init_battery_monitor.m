% =================================================================
% 模块：电量监控系统初始化 (UI优化版)
% =================================================================
function [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs)
    % 1. 创建更整洁的窗口 (去除默认菜单栏和工具栏，调整背景色)
    f_batt = figure('Name', 'AGV Fleet Energy Monitor', 'NumberTitle', 'off', ...
                    'Position', [1060, 250, 450, 350], ... %稍微调大一点
                    'Color', [0.95 0.95 0.95], ... % 浅灰背景，更有质感
                    'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off');
    
    % 2. 创建坐标轴，留出边距
    ax_batt = axes(f_batt, 'Position', [0.15 0.15 0.78 0.75], 'Color', 'w', ...
                   'Box', 'on', 'LineWidth', 1.2, 'GridColor', [0.8 0.8 0.8]);
    
    % 3. 初始化柱状图 (宽度稍微变窄一点，更精致)
    b_handle = bar(ax_batt, 1:num_agvs, ones(1,num_agvs)*100, 0.6); 
    
    % 4. 设置样式美化
    ylim(ax_batt, [0 110]); % Y轴留出空间显示顶部的数字
    set(ax_batt, 'XTick', 1:num_agvs, 'YGrid', 'on', 'XGrid', 'off', ...
        'FontSize', 10, 'FontWeight', 'bold');
    
    title(ax_batt, '实时电量状态监控', 'FontSize', 12, 'FontWeight', 'bold');
    xlabel(ax_batt, 'AGV 编号', 'FontSize', 11);
    ylabel(ax_batt, '电池水平 (%)', 'FontSize', 11);
    
    b_handle.FaceColor = 'flat'; % 允许独立着色
    % 初始颜色设为健康的绿色
    b_handle.CData = repmat([0.1 0.7 0.3], num_agvs, 1);
    
    % 5. 【新增】添加低电量警戒线 (例如 20% 处)
    hold(ax_batt, 'on');
    yline(ax_batt, 20, '--r', '低电量阈值 (20%)', 'LineWidth', 1.5, ...
        'LabelHorizontalAlignment', 'right', 'FontSize', 9, 'Color', [0.8 0.2 0.2]);
    
    % 6. 【新增】初始化柱顶的百分比文字标签
    t_handles = gobjects(1, num_agvs);
    for i = 1:num_agvs
        % 初始显示 100.0%，位置在柱子上方一点
        t_handles(i) = text(ax_batt, i, 103, '100.0%', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2]);
    end
end