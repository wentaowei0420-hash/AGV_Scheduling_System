function evaluate_and_plot_moea(gen_fronts_exp, gen_fronts_base)
% evaluate_and_plot_moea
% 评估并绘制实验组与对照组的收敛性和多样性对比曲线。
%
% 输入：
%   gen_fronts_exp  - 改进 NSGA-II（实验组）每一代的 Pareto 前沿
%   gen_fronts_base - 标准 NSGA-II（对照组）每一代的 Pareto 前沿

    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    max_gen = length(gen_fronts_exp);

    %% 1. 数据归一化与全局参考前沿提取
    all_points_exp = vertcat(gen_fronts_exp{:});
    all_points_base = vertcat(gen_fronts_base{:});
    all_points = [all_points_exp; all_points_base];

    min_val = min(all_points, [], 1);
    max_val = max(all_points, [], 1);
    range_val = max_val - min_val + 1e-6;

    global_fronts = fast_non_dominated_sorting_simple(all_points);
    reference_front_raw = all_points(global_fronts{1}, :);
    ref_front = (reference_front_raw - min_val) ./ range_val;

    %% 2. 分别计算实验组和对照组的 GD 与 SP
    [GD_exp, SP_exp] = compute_metrics(gen_fronts_exp, ref_front, min_val, range_val);
    [GD_base, SP_base] = compute_metrics(gen_fronts_base, ref_front, min_val, range_val);

    %% 3. 绘制独立评估对比曲线
    gens = 1:max_gen;

    figure('Name', '收敛性对比分析 (Generational Distance)', 'Color', 'w', 'Position', [100, 200, 700, 500]);
    plot(gens, GD_exp, '-', 'LineWidth', style.line_width, 'Color', style.exp_color, ...
        'DisplayName', '改进 NSGA-II（实验组）');
    hold on;
    plot(gens, GD_base, '--', 'LineWidth', style.line_width, 'Color', style.base_color, ...
        'DisplayName', '标准 NSGA-II（对照组）');
    title('算法收敛性对比 (Generational Distance)', 'FontSize', style.title_font, 'FontWeight', 'bold', 'FontName', style.cn_font, 'Interpreter', 'none');
    xlabel('迭代次数 (Generation)', 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    ylabel('GD 值', 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    style_axes(style);
    legend('Location', 'northeast', 'FontSize', style.axis_font, 'FontName', style.cn_font);
    axis tight;
    apply_agv_plot_theme(gcf, style);

    figure('Name', '多样性对比分析 (Spacing Metric)', 'Color', 'w', 'Position', [650, 200, 700, 500]);
    plot(gens, SP_exp, '-', 'LineWidth', style.line_width, 'Color', style.exp_color, ...
        'DisplayName', '改进 NSGA-II（实验组）');
    hold on;
    plot(gens, SP_base, '--', 'LineWidth', style.line_width, 'Color', style.base_color, ...
        'DisplayName', '标准 NSGA-II（对照组）');
    title('算法多样性对比 (Spacing Metric)', 'FontSize', style.title_font, 'FontWeight', 'bold', 'FontName', style.cn_font, 'Interpreter', 'none');
    xlabel('迭代次数 (Generation)', 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    ylabel('SP 值', 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    style_axes(style);
    legend('Location', 'northeast', 'FontSize', style.axis_font, 'FontName', style.cn_font);
    axis tight;
    apply_agv_plot_theme(gcf, style);
end

function style_axes(style)
    grid on;
    set(gca, 'FontName', style.en_font, 'FontSize', style.axis_font, ...
        'GridLineStyle', '--', 'GridAlpha', style.grid_alpha, 'LineWidth', 1);
end

function [GD, SP] = compute_metrics(gen_fronts, ref_front, min_val, range_val)
% 给定某算法的前沿历史、全局参考前沿和归一化参数，计算各代 GD 与 SP。
    max_gen = length(gen_fronts);
    GD = zeros(1, max_gen);
    SP = zeros(1, max_gen);

    for gen = 1:max_gen
        current_front_raw = gen_fronts{gen};

        if isempty(current_front_raw)
            GD(gen) = NaN;
            SP(gen) = NaN;
            continue;
        end

        current_front_raw = unique(current_front_raw, 'rows');
        n_points = size(current_front_raw, 1);
        curr_front = (current_front_raw - min_val) ./ range_val;

        if n_points == 0
            GD(gen) = NaN;
        else
            sum_d = 0;
            for i = 1:n_points
                d_i = min(sqrt(sum((ref_front - curr_front(i, :)).^2, 2)));
                sum_d = sum_d + d_i^2;
            end
            GD(gen) = sqrt(sum_d) / n_points;
        end

        if n_points < 2
            SP(gen) = NaN;
        else
            d_nn = zeros(n_points, 1);
            for i = 1:n_points
                distances = sum(abs(curr_front - curr_front(i, :)), 2);
                distances(i) = inf;
                d_nn(i) = min(distances);
            end
            d_mean = mean(d_nn);
            SP(gen) = sqrt(sum((d_mean - d_nn).^2) / (n_points - 1));
        end
    end
end

function fronts = fast_non_dominated_sorting_simple(pop_objs)
% 简化非支配排序，仅提取第一前沿。
    pop_size = size(pop_objs, 1);
    fronts = cell(1, 1);
    domination_count = zeros(pop_size, 1);

    for i = 1:pop_size
        for j = 1:pop_size
            if i == j
                continue;
            end
            if all(pop_objs(j, :) <= pop_objs(i, :)) && any(pop_objs(j, :) < pop_objs(i, :))
                domination_count(i) = domination_count(i) + 1;
                break;
            end
        end
        if domination_count(i) == 0
            fronts{1} = [fronts{1}, i]; %#ok<AGROW>
        end
    end
end





