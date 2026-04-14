function apply_agv_plot_theme(fig, style)
%APPLY_AGV_PLOT_THEME Normalize figure-level plotting appearance.

    if nargin < 1 || isempty(fig)
        fig = gcf;
    end
    if nargin < 2 || isempty(style)
        style = agv_plot_theme();
    end

    if ~ishandle(fig)
        return;
    end

    set(fig, 'Color', style.figure_color);

    ax_list = findall(fig, 'Type', 'Axes');
    for i = 1:numel(ax_list)
        ax = ax_list(i);
        set(ax, 'FontName', style.en_font, ...
            'FontSize', style.axis_font, ...
            'LineWidth', style.axis_line_width, ...
            'GridAlpha', style.grid_alpha, ...
            'GridLineStyle', style.grid_line_style, ...
            'GridColor', style.grid_color, ...
            'Box', 'on');
        try
            title(ax, get(get(ax, 'Title'), 'String'), 'FontName', style.cn_font, 'FontSize', style.title_font, 'Interpreter', 'none');
        catch
        end
        try
            xlabel(ax, get(get(ax, 'XLabel'), 'String'), 'FontName', style.cn_font, 'FontSize', style.label_font, 'Interpreter', 'none');
        catch
        end
        try
            ylabel(ax, get(get(ax, 'YLabel'), 'String'), 'FontName', style.cn_font, 'FontSize', style.label_font, 'Interpreter', 'none');
        catch
        end
        try
            zlabel(ax, get(get(ax, 'ZLabel'), 'String'), 'FontName', style.cn_font, 'FontSize', style.label_font, 'Interpreter', 'none');
        catch
        end
    end

    line_list = findall(fig, 'Type', 'Line');
    for i = 1:numel(line_list)
        if strcmp(get(line_list(i), 'LineStyle'), '--') || strcmp(get(line_list(i), 'LineStyle'), ':')
            set(line_list(i), 'LineWidth', style.aux_line_width);
        else
            set(line_list(i), 'LineWidth', style.line_width);
        end
    end

    scatter_list = findall(fig, 'Type', 'Scatter');
    for i = 1:numel(scatter_list)
        set(scatter_list(i), 'LineWidth', 1.0);
    end

    legend_list = findall(fig, 'Type', 'Legend');
    for i = 1:numel(legend_list)
        set(legend_list(i), 'FontName', style.cn_font, 'FontSize', style.legend_font, 'Box', 'on', ...
            'LineWidth', style.legend_line_width, 'EdgeColor', style.legend_edge_color, 'Color', style.legend_bg_color);
    end

    colorbar_list = findall(fig, 'Type', 'ColorBar');
    for i = 1:numel(colorbar_list)
        set(colorbar_list(i), 'FontName', style.en_font, 'FontSize', style.axis_font, 'LineWidth', style.axis_line_width);
        try
            colorbar_list(i).Label.FontName = style.cn_font;
            colorbar_list(i).Label.FontSize = style.label_font;
        catch
        end
    end
end



