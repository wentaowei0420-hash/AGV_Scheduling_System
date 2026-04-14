% =================================================================
% 模块：电量监控系统初始化 (UI优化版 - 严格中英文字体控制)
% =================================================================
function [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    
    % 1. 创建更整洁的窗口
    f_batt = figure('Name', 'AGV Fleet Energy Monitor', 'NumberTitle', 'off', ...
                    'Position', [1060, 250, 450, 350], ... 
                    'Color', [0.95 0.95 0.95], ... 
                    'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off');
    
    % 2. 创建坐标轴，留出边距
    ax_batt = axes(f_batt, 'Position', [0.15 0.15 0.78 0.75], 'Color', 'w', ...
                   'Box', 'on', 'LineWidth', 1, 'GridColor', [0.8 0.8 0.8]);
    
    % 3. 初始化柱状图
    b_handle = bar(ax_batt, 1:num_agvs, ones(1,num_agvs)*100, 0.6); 
    
    % =========================================================
    % 【关键修改】：将主题应用提前到这里！
    % =========================================================
    apply_agv_plot_theme(f_batt, style);
    
    % =========================================================
    % 在主题应用之后，再设置坐标系和文字，确保 tex 属性生效
    % =========================================================
    ylim(ax_batt, [0 110]); 
    % 将坐标轴的全局字体设为 Times New Roman，这样 X、Y 轴的刻度数字就都是新罗马了
    set(ax_batt, 'XTick', 1:num_agvs, 'YGrid', 'on', 'XGrid', 'off', ...
        'FontSize', 10, 'FontWeight', 'bold', 'FontName', 'Times New Roman');
    
    % 使用 \fontname{} 语法实现精准的中英文混排
    title(ax_batt, '\fontname{宋体}实时电量状态监控', 'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'tex');
    xlabel(ax_batt, '\fontname{Times New Roman}AGV \fontname{宋体}编号', 'FontSize', 11, 'Interpreter', 'tex');
    ylabel(ax_batt, '\fontname{宋体}电池水平 \fontname{Times New Roman}(%)', 'FontSize', 11, 'Interpreter', 'tex');
    
    b_handle.FaceColor = 'flat'; 
    b_handle.CData = repmat([0.1 0.7 0.3], num_agvs, 1);
    
    % 4. 添加低电量警戒线
    hold(ax_batt, 'on');
    % 警戒线标签同样混排
    yline(ax_batt, 20, '--r', '\fontname{宋体}低电量阈值 \fontname{Times New Roman}(20%)', 'LineWidth', 1, ...
        'LabelHorizontalAlignment', 'right', 'FontSize', 9, 'Color', [0.8 0.2 0.2], 'Interpreter', 'tex');
    
    % 5. 初始化柱顶的百分比文字标签
    t_handles = gobjects(1, num_agvs);
    for i = 1:num_agvs
        % 顶部的电量百分比纯粹是数字和符号，直接指定 Times New Roman
        t_handles(i) = text(ax_batt, i, 103, '100.0%', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2], ...
            'FontName', 'Times New Roman');
    end
end