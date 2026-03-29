function style = agv_plot_theme(mode)
%AGV_PLOT_THEME Return unified plotting style configuration.
%   style = agv_plot_theme() returns the default unified style struct.
%   style = agv_plot_theme('presentation') returns the same style and keeps
%   the API open for future variants.

    if nargin < 1
        mode = 'default';
    end

    switch lower(mode)
        case {'default', 'presentation', 'paper'}
            style.figure_color = 'w';
            style.cn_font = pick_cn_font();
            style.en_font = 'Times New Roman';
            style.title_font = 14;
            style.label_font = 12;
            style.axis_font = 11;
            style.legend_font = 11;
            style.sgtitle_font = 15;
            style.line_width = 1.0;
            style.aux_line_width = 1.0;
            style.axis_line_width = 1.0;
            style.grid_alpha = 0.18;
            style.grid_line_style = '--';
            style.grid_color = [0.78, 0.78, 0.78];
            style.legend_line_width = 0.8;
            style.legend_edge_color = [0.55, 0.55, 0.55];
            style.legend_bg_color = [1.0, 1.0, 1.0];
            style.exp_color = [0.0000, 0.4470, 0.7410];
            style.base_color = [0.8500, 0.3250, 0.0980];
            style.accent_green = [0.4660, 0.6740, 0.1880];
            style.accent_purple = [0.4940, 0.1840, 0.5560];
            style.accent_red = [0.6350, 0.0780, 0.1840];
        otherwise
            error('Unsupported plot theme mode: %s', mode);
    end
end

function font_name = pick_cn_font()
    preferred_fonts = { ...
        'Microsoft YaHei UI', ...
        'Microsoft YaHei', ...
        'SimHei', ...
        'SimSun', ...
        '宋体', ...
        'Arial Unicode MS' ...
    };

    font_name = preferred_fonts{1};
    try
        installed_fonts = listfonts;
        for i = 1:numel(preferred_fonts)
            if any(strcmpi(installed_fonts, preferred_fonts{i}))
                font_name = preferred_fonts{i};
                return;
            end
        end
    catch
        % Fall back to the first preferred font.
    end
end


