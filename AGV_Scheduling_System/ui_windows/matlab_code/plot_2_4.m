clc; clear; close all;

style = agv_plot_theme();
init_agv_plot_defaults(style);

% =========================================================================
% 独立测试脚本：异构 AGV 非对称人工势场
% 4 张独立学术图片版
% 中文：宋体；英文和数字：Times New Roman
% 取消标题，统一图幅，优化 3D 图 Y 轴标签位置
% =========================================================================

% --- 字体设置 ---
ch_font = 'SimSun';              % 中文字体：宋体
en_font = 'Times New Roman';     % 英文字体：Times New Roman
label_fs = 11;

set(groot, 'DefaultAxesFontName', en_font);
set(groot, 'DefaultAxesFontSize', label_fs);
set(groot, 'DefaultAxesFontWeight', 'normal');

set(groot, 'DefaultTextFontName', ch_font);
set(groot, 'DefaultTextFontSize', label_fs);
set(groot, 'DefaultTextFontWeight', 'normal');
set(groot, 'DefaultTextInterpreter', 'tex');

disp('>> [系统] 正在计算高精度拓扑势能场...');

global mapW mapH;
mapW = 51;
mapH = 51;

% 1. 提取地图
staticMap = create_binary_grid_map(mapW, mapH, 17);
obs_map = (staticMap == 1);
dist_map = bwdist(obs_map);

% 2. 生成代价地图
costmap_type1 = zeros(mapH, mapW);
costmap_type2 = zeros(mapH, mapW);

for r = 1:mapH
    for c = 1:mapW
        if obs_map(r, c) == 1
            costmap_type1(r, c) = NaN;
            costmap_type2(r, c) = NaN;
        else
            d = dist_map(r, c);

            % 叉车式 AGV（Type 2）：靠近墙壁时代价急剧升高
            costmap_type2(r, c) = min(1.0 + 15.0 / (d^2), 25);

            % 托举式 AGV（Type 1）：鼓励贴近边缘，中心区域存在轻微斥力
            costmap_type1(r, c) = 1.0 + 0.3 * d;
        end
    end
end

disp('>> [系统] 正在分别渲染 4 张独立的高精度图像...');

[X, Y] = meshgrid(1:mapW, 1:mapH);

% 统一图窗尺寸
fig_w = 600;
fig_h = 500;

fig_pos_1 = [100, 100, fig_w, fig_h];
fig_pos_2 = [150, 150, fig_w, fig_h];
fig_pos_3 = [200, 200, fig_w, fig_h];
fig_pos_4 = [250, 250, fig_w, fig_h];

% 统一坐标区位置
axes_pos_2d = [0.12, 0.13, 0.66, 0.78];
axes_pos_3d = [0.12, 0.15, 0.66, 0.74];

% 中英文混排标签
xlabel_str = '\fontname{Times New Roman}X \fontname{SimSun}轴（栅格）';
ylabel_str = '\fontname{Times New Roman}Y \fontname{SimSun}轴（栅格）';
zlabel_str = '\fontname{SimSun}势能代价 \fontname{Times New Roman}(Cost)';
cbar_str   = '\fontname{SimSun}势能代价 \fontname{Times New Roman}(Cost)';

% =========================================================
% 图 1：托举式 AGV - 2D 热力图
% =========================================================
fig1 = figure('Name', '图1：托举式 AGV - 2D 热力图', ...
    'Position', fig_pos_1, ...
    'Color', 'w');

contourf(X, Y, costmap_type1, 30, 'LineStyle', 'none');
colormap(gca, 'parula');

axis equal tight;

ax1 = gca;
set(ax1, 'YDir', 'normal', ...
         'FontName', en_font, ...
         'FontSize', label_fs, ...
         'Box', 'on', ...
         'LineWidth', 1, ...
         'Position', axes_pos_2d);

xlabel(xlabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

ylabel(ylabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

c1 = colorbar;
c1.FontName = en_font;
c1.FontSize = label_fs;
c1.Label.String = cbar_str;
c1.Label.Interpreter = 'tex';
c1.Label.FontSize = label_fs;

% =========================================================
% 图 2：托举式 AGV - 3D 拓扑地形图
% =========================================================
fig2 = figure('Name', '图2：托举式 AGV - 3D 地形图', ...
    'Position', fig_pos_2, ...
    'Color', 'w');

surfc(X, Y, costmap_type1, 'EdgeAlpha', 0.08);
colormap(gca, 'parula');

ax2 = gca;
set(ax2, 'YDir', 'normal', ...
         'FontName', en_font, ...
         'FontSize', label_fs, ...
         'Box', 'on', ...
         'LineWidth', 1, ...
         'Position', axes_pos_3d);

shading interp;
lighting gouraud;
camlight('headlight');
material dull;

view(-38, 32);
pbaspect([1 1 0.50]);

xlim([1, mapW]);
ylim([1, mapH]);

xlabel(xlabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

% 取消默认 Y 轴标签，避免跑偏
ylabel('');

zlabel(zlabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

c2 = colorbar;
c2.FontName = en_font;
c2.FontSize = label_fs;
c2.Label.String = cbar_str;
c2.Label.Interpreter = 'tex';
c2.Label.FontSize = label_fs;

% 手动添加 Y 轴标签到左下方圈出位置
add_manual_y_label_bottom(fig2, ylabel_str, label_fs);

% =========================================================
% 图 3：叉车式 AGV - 2D 热力图
% =========================================================
fig3 = figure('Name', '图3：叉车式 AGV - 2D 热力图', ...
    'Position', fig_pos_3, ...
    'Color', 'w');

contourf(X, Y, costmap_type2, 40, 'LineStyle', 'none');
colormap(gca, 'turbo');

axis equal tight;

ax3 = gca;
set(ax3, 'YDir', 'normal', ...
         'FontName', en_font, ...
         'FontSize', label_fs, ...
         'Box', 'on', ...
         'LineWidth', 1, ...
         'Position', axes_pos_2d);

xlabel(xlabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

ylabel(ylabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

c3 = colorbar;
c3.FontName = en_font;
c3.FontSize = label_fs;
c3.Label.String = cbar_str;
c3.Label.Interpreter = 'tex';
c3.Label.FontSize = label_fs;

% =========================================================
% 图 4：叉车式 AGV - 3D 拓扑地形图
% =========================================================
fig4 = figure('Name', '图4：叉车式 AGV - 3D 地形图', ...
    'Position', fig_pos_4, ...
    'Color', 'w');

surf(X, Y, costmap_type2, 'EdgeAlpha', 0.08);
colormap(gca, 'turbo');

ax4 = gca;
set(ax4, 'YDir', 'normal', ...
         'FontName', en_font, ...
         'FontSize', label_fs, ...
         'Box', 'on', ...
         'LineWidth', 1, ...
         'Position', axes_pos_3d);

shading interp;
lighting gouraud;
camlight('headlight');
material dull;

view(-38, 32);
pbaspect([1 1 0.50]);

xlim([1, mapW]);
ylim([1, mapH]);

xlabel(xlabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

% 取消默认 Y 轴标签，避免跑偏
ylabel('');

zlabel(zlabel_str, ...
    'FontSize', label_fs, ...
    'Interpreter', 'tex');

c4 = colorbar;
c4.FontName = en_font;
c4.FontSize = label_fs;
c4.Label.String = cbar_str;
c4.Label.Interpreter = 'tex';
c4.Label.FontSize = label_fs;

% 手动添加 Y 轴标签到左下方圈出位置
add_manual_y_label_bottom(fig4, ylabel_str, label_fs);

disp('>> [系统] 渲染完毕！请分别导出图片。');


% =========================================================================
% 辅助函数：为 3D 图在左下方添加 Y 轴标签
% =========================================================================
function add_manual_y_label_bottom(fig_handle, ylabel_str, label_fs)
    figure(fig_handle);

    % 创建透明覆盖层，用于稳定放置文字
    ax_text = axes('Parent', fig_handle, ...
        'Position', [0, 0, 1, 1], ...
        'Visible', 'off', ...
        'Color', 'none', ...
        'HitTest', 'off');

    % 标签位置：对应图中左下方空白区域
    text(ax_text, 0.17, 0.24, ylabel_str, ...
        'Units', 'normalized', ...
        'Interpreter', 'tex', ...
        'FontSize', label_fs, ...
        'Rotation', 0, ...
        'HorizontalAlignment', 'center', ...
        'VerticalAlignment', 'middle', ...
        'Clipping', 'off');
end