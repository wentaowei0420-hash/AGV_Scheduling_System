style = agv_plot_theme();
init_agv_plot_defaults(style);
% =========================================================================
% 鐙珛娴嬭瘯鑴氭湰锛氬紓鏋?AGV 闈炲绉颁汉宸ュ娍鍦?(4寮犵嫭绔嬪鏈浘鐗囩増)
% =========================================================================
clc; clear; close all;

% --- 鎭㈠ MATLAB 绯荤粺榛樿瀛椾綋鏍峰紡 ---
set(groot, 'DefaultAxesFontWeight', 'normal');
set(groot, 'DefaultTextFontWeight', 'normal');
% set(groot, 'DefaultAxesFontName', '瀹嬩綋'); 
% set(groot, 'DefaultTextFontName', '瀹嬩綋');

disp('>> [绯荤粺] 姝ｅ湪璁＄畻楂樼簿搴︽嫇鎵戝娍鑳藉満...');
global mapW mapH;
mapW = 51; mapH = 51; 

% 1. 鎻愬彇鍦板浘
staticMap = create_binary_grid_map(mapW, mapH, 17);
obs_map = (staticMap == 1); 
dist_map = bwdist(obs_map); 

% 2. 鐢熸垚浠ｄ环鍦板浘
costmap_type1 = zeros(mapH, mapW); 
costmap_type2 = zeros(mapH, mapW); 

for r = 1:mapH
    for c = 1:mapW
        if obs_map(r,c) == 1
            costmap_type1(r,c) = NaN;
            costmap_type2(r,c) = NaN;
        else
            d = dist_map(r,c);
            % 鍙夎溅 (Type 2)锛氬鎬曞澹侊紝鎸囨暟绾ф枼鍔?
            costmap_type2(r,c) = min(1.0 + 15.0 / (d^2), 25); 
            
            % 鎵樹妇杞?(Type 1)锛氶紦鍔辨簻杈癸紝涓績杞诲井鏂ュ姏
            costmap_type1(r,c) = 1.0 + 0.3 * d; 
        end
    end
end

disp('>> [绯荤粺] 姝ｅ湪鍒嗗埆娓叉煋 4 寮犵嫭绔嬬殑楂樼簿搴﹀浘鍍?..');
[X, Y] = meshgrid(1:mapW, 1:mapH); % 鐢熸垚骞虫粦缃戞牸

% 缁熶竴瀛楀彿璁剧疆 (閫傞厤璁烘枃鎺掔増)
title_fs = 12;
label_fs = 11;

% =========================================================
% 鍥?1: 鎵樹妇寮?AGV - 骞虫粦绛夐珮绾跨儹鍔涘浘 (Contourf)
% =========================================================
figure('Name', '鍥?锛氭墭涓惧紡AGV - 2D鐑姏鍥?, 'Position', [100, 100, 600, 500], 'Color', 'w');
contourf(X, Y, costmap_type1, 30, 'LineStyle', 'none'); 
colormap(gca, 'parula');
c1 = colorbar; c1.Label.String = '鍔胯兘浠ｄ环 (Cost)';
title('鎵樹妇寮廇GV - 2D鐑姏鍥?, 'FontSize', title_fs);
axis equal tight; 
set(gca, 'YDir', 'normal'); 
xlabel('X 杞?(鏍呮牸)', 'FontSize', label_fs); 
ylabel('Y 杞?(鏍呮牸)', 'FontSize', label_fs);

% =========================================================
% 鍥?2: 鎵樹妇寮?AGV - 闀傜┖ 3D 鎷撴墤鍦板舰鍥?(Surfc)
% =========================================================
figure('Name', '鍥?锛氭墭涓惧紡AGV - 3D鍦板舰鍥?, 'Position', [150, 150, 600, 500], 'Color', 'w');
surfc(X, Y, costmap_type1, 'EdgeAlpha', 0.1); 
colormap(gca, 'parula');
c2 = colorbar; c2.Label.String = '鍔胯兘浠ｄ环 (Cost)'; % 鍗曞浘闇€琛ュ厖鑹叉爣璇存槑
title('鎵樹妇寮廇GV - 3D鍦板舰鍥?, 'FontSize', title_fs);
set(gca, 'YDir', 'normal'); 
shading interp; lighting gouraud; camlight('headlight'); 
material dull; 
view(-25, 55); 
xlabel('X 杞?(鏍呮牸)', 'FontSize', label_fs); % 鍗曞浘闇€琛ュ厖 XY 杞存爣绛?
ylabel('Y 杞?(鏍呮牸)', 'FontSize', label_fs);
zlabel('鍔胯兘浠ｄ环 (Cost)', 'FontSize', label_fs);

% =========================================================
% 鍥?3: 鍙夎溅寮?AGV - 骞虫粦绛夐珮绾跨儹鍔涘浘
% =========================================================
figure('Name', '鍥?锛氬弶杞﹀紡AGV - 2D鐑姏鍥?, 'Position', [200, 200, 600, 500], 'Color', 'w');
contourf(X, Y, costmap_type2, 40, 'LineStyle', 'none'); 
colormap(gca, 'turbo'); 
c3 = colorbar; c3.Label.String = '鍔胯兘浠ｄ环 (Cost)';
title('鍙夎溅寮廇GV - 2D鐑姏鍥?, 'FontSize', title_fs);
axis equal tight; 
set(gca, 'YDir', 'normal'); 
xlabel('X 杞?(鏍呮牸)', 'FontSize', label_fs); 
ylabel('Y 杞?(鏍呮牸)', 'FontSize', label_fs);

% =========================================================
% 鍥?4: 鍙夎溅寮?AGV - 闀傜┖ 3D 鎷撴墤鍦板舰鍥?
% =========================================================
figure('Name', '鍥?锛氬弶杞﹀紡AGV - 3D鍦板舰鍥?, 'Position', [250, 250, 600, 500], 'Color', 'w');
surf(X, Y, costmap_type2, 'EdgeAlpha', 0.1);
colormap(gca, 'turbo');
c4 = colorbar; c4.Label.String = '鍔胯兘浠ｄ环 (Cost)'; % 鍗曞浘闇€琛ュ厖鑹叉爣璇存槑
title('鍙夎溅寮廇GV - 3D鍦板舰鍥?, 'FontSize', title_fs);
set(gca, 'YDir', 'normal'); 
shading interp; lighting gouraud; camlight('headlight');
material dull;
view(-25, 55);
xlabel('X 杞?(鏍呮牸)', 'FontSize', label_fs); % 鍗曞浘闇€琛ュ厖 XY 杞存爣绛?
ylabel('Y 杞?(鏍呮牸)', 'FontSize', label_fs);
zlabel('鍔胯兘浠ｄ环 (Cost)', 'FontSize', label_fs);

disp('>> [绯荤粺] 娓叉煋瀹屾瘯锛佽鍒嗗埆瀵煎嚭鍥剧墖銆?);
