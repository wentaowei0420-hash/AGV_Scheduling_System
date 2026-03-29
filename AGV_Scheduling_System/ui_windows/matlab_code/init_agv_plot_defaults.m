function init_agv_plot_defaults(style)
%INIT_AGV_PLOT_DEFAULTS Apply unified root defaults for plotting.

    if nargin < 1 || isempty(style)
        style = agv_plot_theme();
    end

    set(groot, 'DefaultFigureColor', style.figure_color);
    set(groot, 'DefaultAxesFontName', style.en_font);
    set(groot, 'DefaultAxesFontSize', style.axis_font);
    set(groot, 'DefaultAxesLineWidth', style.axis_line_width);
    set(groot, 'DefaultAxesGridAlpha', style.grid_alpha);
    set(groot, 'DefaultAxesGridColor', style.grid_color);
    set(groot, 'DefaultAxesGridLineStyle', style.grid_line_style);
    set(groot, 'DefaultTextInterpreter', 'none');
    set(groot, 'DefaultLegendInterpreter', 'none');
    set(groot, 'DefaultLineLineWidth', style.line_width);
    set(groot, 'DefaultTextFontName', style.cn_font);
    set(groot, 'DefaultLegendFontName', style.cn_font);
    set(groot, 'DefaultLegendFontSize', style.legend_font);
    set(groot, 'DefaultLegendColor', style.legend_bg_color);
    set(groot, 'DefaultLegendEdgeColor', style.legend_edge_color);
end

