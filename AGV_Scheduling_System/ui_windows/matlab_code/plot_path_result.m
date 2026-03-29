function plot_path_result(map, path, start, goal, path_length, turn_count, expanded_nodes, algo_name, ax, gScore_matrix)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % 缁樺埗璺緞瑙勫垝缁撴灉 (鍚僵鑹叉悳绱㈢儹鍔涘浘)
    
    if nargin < 9
        figure;
        ax = gca;
    else
        axes(ax);  % 婵€娲绘寚瀹氬潗鏍囪酱
    end
    
    % --- 1. 缁樺埗搴曞眰鍩虹鍦板浘 (榛戠櫧) ---
    map_rgb = ones(size(map,1), size(map,2), 3); % 鍒濆鍏ㄧ櫧
    for c = 1:3
        channel = map_rgb(:,:,c);
        channel(map == 1) = 0; % 闅滅鐗╂秱榛?
        map_rgb(:,:,c) = channel;
    end
    imagesc(ax, map_rgb);
    hold(ax, 'on');
    
    % --- 2. 娓叉煋浠ｄ环鐑姏鍥?(鏍稿績鍔熻兘) ---
    if nargin >= 10 && ~isempty(gScore_matrix)
        % 鎵惧嚭鎵€鏈夎鎼滅储杩囷紙闈炴棤绌峰ぇ锛変笖涓嶆槸闅滅鐗╃殑鑺傜偣
        valid_nodes = isfinite(gScore_matrix) & (map == 0);
        
        if any(valid_nodes, 'all')
            min_g = min(gScore_matrix(valid_nodes));
            max_g = max(gScore_matrix(valid_nodes));
            
            cmap = jet(256); % 浣跨敤 jet 棰滆壊鏄犲皠锛氳摑(灏? -> 缁?-> 榛?-> 绾?澶?
            overlay_rgb = ones(size(map,1), size(map,2), 3);
            alpha_data = zeros(size(map,1), size(map,2)); % 閫忔槑搴︾煩闃?
            
            for r = 1:size(map,1)
                for c = 1:size(map,2)
                    if valid_nodes(r,c)
                        % 褰掍竴鍖栦唬浠峰埌 1-256 鐨勯鑹茬储寮?
                        norm_val = (gScore_matrix(r,c) - min_g) / (max_g - min_g + 1e-5);
                        color_idx = round(norm_val * 255) + 1;
                        
                        overlay_rgb(r,c,:) = cmap(color_idx, :);
                        alpha_data(r,c) = 0.8; % 璁剧疆鐑姏鍥鹃€忔槑搴︿负 0.8 (鍙井璋?
                    end
                end
            end
            
            % 灏嗙儹鍔涘浘鍙犲姞鍒板潗鏍囪酱涓?
            h_heatmap = imagesc(ax, overlay_rgb);
            set(h_heatmap, 'AlphaData', alpha_data);
        end
    end
    
    % --- 3. 缁樺埗缃戞牸绾?---
    ax_obj = ax;
    ax_obj.XTick = 0.5:1:size(map,2)+0.5;
    ax_obj.YTick = 0.5:1:size(map,1)+0.5;
    ax_obj.XTickLabel = [];
    ax_obj.YTickLabel = [];
    grid(ax_obj, 'on');
    ax_obj.GridColor = [0.3 0.3 0.3];
    ax_obj.GridAlpha = 0.5;
    ax_obj.LineWidth = 1;
    
    % --- 4. 缁樺埗鏈€缁堣矾寰勪笌璧风粓鐐?---
    if ~isempty(path)
        plot(ax, path(:,2), path(:,1), 'r-', 'LineWidth', 1);
    end
    plot(ax, start(2), start(1), 'go', 'MarkerSize', 6, 'MarkerFaceColor', 'g');
    plot(ax, goal(2), goal(1), 'ro', 'MarkerSize', 6, 'MarkerFaceColor', 'r');
    
    % --- 5. 璁剧疆鏍囬涓庢牸寮?---
    title(ax, sprintf('%s (鏍呮牸鏁? %d, 杞集: %d, 鑺傜偣: %d)', ...
                      algo_name, path_length, turn_count, expanded_nodes), 'FontSize', 10);
    
    axis(ax, 'equal');
    axis(ax, 'tight');
    apply_agv_plot_theme(ancestor(ax, 'figure'), style);
    hold(ax, 'off');
end




