function plot_path_result(map, path, start, goal, path_length, turn_count, expanded_nodes, algo_name, ax, gScore_matrix)
    % 绘制路径规划结果 (含彩色搜索热力图)
    
    if nargin < 9
        figure;
        ax = gca;
    else
        axes(ax);  % 激活指定坐标轴
    end
    
    % --- 1. 绘制底层基础地图 (黑白) ---
    map_rgb = ones(size(map,1), size(map,2), 3); % 初始全白
    for c = 1:3
        channel = map_rgb(:,:,c);
        channel(map == 1) = 0; % 障碍物涂黑
        map_rgb(:,:,c) = channel;
    end
    imagesc(ax, map_rgb);
    hold(ax, 'on');
    
    % --- 2. 渲染代价热力图 (核心功能) ---
    if nargin >= 10 && ~isempty(gScore_matrix)
        % 找出所有被搜索过（非无穷大）且不是障碍物的节点
        valid_nodes = isfinite(gScore_matrix) & (map == 0);
        
        if any(valid_nodes, 'all')
            min_g = min(gScore_matrix(valid_nodes));
            max_g = max(gScore_matrix(valid_nodes));
            
            cmap = jet(256); % 使用 jet 颜色映射：蓝(小) -> 绿 -> 黄 -> 红(大)
            overlay_rgb = ones(size(map,1), size(map,2), 3);
            alpha_data = zeros(size(map,1), size(map,2)); % 透明度矩阵
            
            for r = 1:size(map,1)
                for c = 1:size(map,2)
                    if valid_nodes(r,c)
                        % 归一化代价到 1-256 的颜色索引
                        norm_val = (gScore_matrix(r,c) - min_g) / (max_g - min_g + 1e-5);
                        color_idx = round(norm_val * 255) + 1;
                        
                        overlay_rgb(r,c,:) = cmap(color_idx, :);
                        alpha_data(r,c) = 0.8; % 设置热力图透明度为 0.8 (可微调)
                    end
                end
            end
            
            % 将热力图叠加到坐标轴上
            h_heatmap = imagesc(ax, overlay_rgb);
            set(h_heatmap, 'AlphaData', alpha_data);
        end
    end
    
    % --- 3. 绘制网格线 ---
    ax_obj = ax;
    ax_obj.XTick = 0.5:1:size(map,2)+0.5;
    ax_obj.YTick = 0.5:1:size(map,1)+0.5;
    ax_obj.XTickLabel = [];
    ax_obj.YTickLabel = [];
    grid(ax_obj, 'on');
    ax_obj.GridColor = [0.3 0.3 0.3];
    ax_obj.GridAlpha = 0.5;
    ax_obj.LineWidth = 0.5;
    
    % --- 4. 绘制最终路径与起终点 ---
    if ~isempty(path)
        plot(ax, path(:,2), path(:,1), 'r-', 'LineWidth', 2.5);
    end
    plot(ax, start(2), start(1), 'go', 'MarkerSize', 6, 'MarkerFaceColor', 'g');
    plot(ax, goal(2), goal(1), 'ro', 'MarkerSize', 6, 'MarkerFaceColor', 'r');
    
    % --- 5. 设置标题与格式 ---
    title(ax, sprintf('%s (栅格数: %d, 转弯: %d, 节点: %d)', ...
                      algo_name, path_length, turn_count, expanded_nodes), 'FontSize', 10);
    
    axis(ax, 'equal');
    axis(ax, 'tight');
    hold(ax, 'off');
end