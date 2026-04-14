function Test_Map_Vision()
    clc; clear; close all;
    
    % 地图尺寸
    W = 70; H = 50;
    
    % 创建图形窗口
    figure('Name', '电脑眼中的网格地图(含网格边界)', 'Color', 'w', 'Position', [100, 200, 1200, 600]);
    
    %% === 场景 1: 托盘式 AGV (Target ID = 17, 小配件) ===
    target_id_small = 17;
    % 生成地图
    binaryMap1 = create_binary_grid_map(W, H, target_id_small);
    
    % 绘图
    subplot(1, 2, 1);
    show_map(binaryMap1); % 调用修改后的显示函数
    title(['场景A: 托盘式 AGV (去目标' num2str(target_id_small) ')']);
    subtitle('注意右下角：叉车基地已被封锁 (黑色)');
    
    % 用红框圈出重点验证区域 (叉车基地 x=39~49, y=2)
    hold on;
    rectangle('Position', [39, 2, 10, 3], 'EdgeColor', 'r', 'LineWidth', 1, 'LineStyle', '--');
    text(39, 7, '叉车基地 (已封锁)', 'Color', 'r', 'FontSize', 10, 'FontWeight', 'bold');
    
    % 圈出目标 (应该可以看到目标5号是白的)
    rectangle('Position', [19, 18, 2, 2], 'EdgeColor', 'g', 'LineWidth', 1);
    text(19, 22, '目标5开放', 'Color', 'g', 'FontSize', 10, 'FontWeight', 'bold');

    %% === 场景 2: 叉车式 AGV (Target ID = 14, 大件) ===
    target_id_heavy = 14;
    % 生成地图
    binaryMap2 = create_binary_grid_map(W, H, target_id_heavy);
    
    % 绘图
    subplot(1, 2, 2);
    show_map(binaryMap2); % 调用修改后的显示函数
    title(['场景B: 叉车式 AGV (去目标' num2str(target_id_heavy) ')']);
    subtitle('注意左下角：托盘基地已被封锁 (黑色)');
    
    % 用红框圈出重点验证区域 (托盘基地 x=2~14, y=2)
    hold on;
    rectangle('Position', [2, 2, 14, 3], 'EdgeColor', 'r', 'LineWidth', 1, 'LineStyle', '--');
    text(2, 7, '托盘基地 (已封锁)', 'Color', 'r', 'FontSize', 10, 'FontWeight', 'bold');
    
    % 圈出目标
    rectangle('Position', [4, 41, 3, 3], 'EdgeColor', 'g', 'LineWidth', 1);
    text(4, 39, '目标14开放', 'Color', 'g', 'FontSize', 10, 'FontWeight', 'bold');
    
end

% === 【核心修改】辅助绘图函数(增加了网格线绘制) ===
function show_map(gridMap)
    % 1. 显示地图本身
    imagesc(1 - gridMap); % 1-gridMap 是为了让障碍物变黑(0)，路变白(1)
    colormap(gray); 
    axis xy;    % 坐标原点在左下角
    axis equal; % x轴y轴比例一致
    
    % 获取地图尺寸
    [rows, cols] = size(gridMap);
    
    % 设置坐标轴范围(留出一点边距)
    xlim([0.5, cols + 0.5]); 
    ylim([0.5, rows + 0.5]);
    xlabel('X 坐标'); ylabel('Y 坐标');
    set(gca, 'TickDir', 'out');
    
    hold on; % 保持图像，准备画线
    
    % === 新增代码：绘制网格边界 ===
    % imagesc 的像素中心在整数点(1,1), (2,2)...
    % 像素的边缘在 (0.5, 1.5, 2.5...)
    
    % A. 画竖线 (Vertical Lines)
    % 从 0.5 开始，步长为 1，画到最右边
    for x = 0.5 : 1 : cols + 0.5
        line([x, x], [0.5, rows + 0.5], 'Color', [0.6 0.6 0.6], 'LineWidth', 1);
    end
    
    % B. 画横线 (Horizontal Lines)
    % 从 0.5 开始，步长为 1，画到最上边
    for y = 0.5 : 1 : rows + 0.5
        line([0.5, cols + 0.5], [y, y], 'Color', [0.6 0.6 0.6], 'LineWidth', 1);
    end
end