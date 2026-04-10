function plot_path_result(map, path, start_rc, goal_rc, path_length, turn_count, expanded_nodes, algo_name, ax, gscore_matrix)
style = agv_plot_theme();
init_agv_plot_defaults(style);

if nargin < 9 || isempty(ax)
    fig = figure('Color', 'w', 'Renderer', 'painters');
    ax = axes('Parent', fig);
else
    axes(ax);
    set(ancestor(ax, 'figure'), 'Renderer', 'painters');
end

hasHeatmap = (nargin >= 10) && ~isempty(gscore_matrix);
[nRows, nCols] = size(map);

base_rgb = ones(nRows, nCols, 3);
for ch = 1:3
    channel = base_rgb(:,:,ch);
    channel(map == 1) = 0;
    base_rgb(:,:,ch) = channel;
end
hBase = imagesc(ax, [1, nCols], [1, nRows], base_rgb);
set(hBase, 'Interpolation', 'nearest');
hold(ax, 'on');
set(ax, 'YDir', 'normal');

if hasHeatmap
    valid_nodes = isfinite(gscore_matrix) & (map == 0);
    if any(valid_nodes(:))
        min_g = min(gscore_matrix(valid_nodes));
        max_g = max(gscore_matrix(valid_nodes));
        cmap = jet(256);
        overlay_rgb = ones(nRows, nCols, 3);
        alpha_data = zeros(nRows, nCols);

        for r = 1:nRows
            for c = 1:nCols
                if valid_nodes(r,c)
                    norm_val = (gscore_matrix(r,c) - min_g) / max(max_g - min_g, 1e-6);
                    color_idx = min(256, max(1, round(norm_val * 255) + 1));
                    overlay_rgb(r,c,:) = cmap(color_idx, :);
                    alpha_data(r,c) = 0.92;
                end
            end
        end

        hHeat = imagesc(ax, [1, nCols], [1, nRows], overlay_rgb);
        set(hHeat, 'AlphaData', alpha_data, 'Interpolation', 'nearest');
    end
end

ax.XTick = [];
ax.YTick = [];
ax.XLim = [0.5, nCols + 0.5];
ax.YLim = [0.5, nRows + 0.5];
ax.LineWidth = 1.0;
ax.Layer = 'top';
ax.Box = 'on';
axis(ax, 'equal');
axis(ax, 'tight');
apply_agv_plot_theme(ancestor(ax, 'figure'), style);

if ~isempty(path)
    plot(ax, path(:,2), path(:,1), 'k-', 'LineWidth', 1.6);
end
plot(ax, start_rc(2), start_rc(1), 'go', 'MarkerSize', 10, 'MarkerFaceColor', 'g');
plot(ax, goal_rc(2), goal_rc(1), 'ro', 'MarkerSize', 10, 'MarkerFaceColor', 'r');

draw_cell_boundaries(ax, nRows, nCols, hasHeatmap);

fprintf('[PathPlot] %s | Steps=%d | Turns=%d | Nodes=%d\n', algo_name, path_length, turn_count, expanded_nodes);
hold(ax, 'off');
end

function draw_cell_boundaries(ax, nRows, nCols, hasHeatmap)
if hasHeatmap
    gridColor = [0.6, 0.6, 0.6];
    lineWidth = 0.45;
else
    gridColor = [0.60, 0.60, 0.60];
    lineWidth = 0.50;
end

for x = 0.5:1:(nCols + 0.5)
    line(ax, [x x], [0.5, nRows + 0.5], 'Color', gridColor, 'LineWidth', lineWidth, 'Clipping', 'on', 'HitTest', 'off');
end
for y = 0.5:1:(nRows + 0.5)
    line(ax, [0.5, nCols + 0.5], [y y], 'Color', gridColor, 'LineWidth', lineWidth, 'Clipping', 'on', 'HitTest', 'off');
end
end
