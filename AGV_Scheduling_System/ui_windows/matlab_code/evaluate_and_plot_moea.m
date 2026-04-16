function evaluate_and_plot_moea(gen_fronts_exp, gen_fronts_base, opts)
% evaluate_and_plot_moea 分析并绘制实验组与对照组的 GD / SP 对比曲线
% 兼容两种使用方式：
% 1. 实时仿真后直接调用：
%       evaluate_and_plot_moea(hist_exp, hist_base)
% 2. 读取已保存/手工微调后的 CSV：
%       evaluate_and_plot_moea([], [], struct('mode', 'saved', 'saved_metrics_path', csv_path))

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    base_dir = fileparts(mfilename('fullpath'));
    snapshot_dir = fullfile(base_dir, 'moea_metric_snapshots');
    if ~exist(snapshot_dir, 'dir')
        mkdir(snapshot_dir);
    end

    scenario_name = get_option(opts, 'scenario_name', infer_scenario_name());
    mode = lower(string(get_option(opts, 'mode', 'live')));
    prefer_saved_for_plot = logical(get_option(opts, 'prefer_saved_for_plot', false));
    saved_metrics_path = get_option(opts, 'saved_metrics_path', ...
        fullfile(snapshot_dir, [scenario_name '_manual_metrics.csv']));

    if mode == "saved"
        metrics_tbl = load_metrics_table(saved_metrics_path);
        plot_metric_figures(metrics_tbl.Generation, metrics_tbl.GD_exp, metrics_tbl.GD_base, ...
            metrics_tbl.SP_exp, metrics_tbl.SP_base, scenario_name);
        return;
    end

    if nargin < 2 || isempty(gen_fronts_exp) || isempty(gen_fronts_base)
        error('evaluate_and_plot_moea:MissingInputs', ...
            '实时模式需要同时传入实验组和对照组的前沿历史。');
    end

    max_gen = min(length(gen_fronts_exp), length(gen_fronts_base));
    gen_fronts_exp = gen_fronts_exp(1:max_gen);
    gen_fronts_base = gen_fronts_base(1:max_gen);

    all_points_exp = vertcat_nonempty(gen_fronts_exp);
    all_points_base = vertcat_nonempty(gen_fronts_base);
    all_points = [all_points_exp; all_points_base];

    if isempty(all_points)
        error('evaluate_and_plot_moea:EmptyFronts', '前沿历史为空，无法计算 GD / SP。');
    end

    min_val = min(all_points, [], 1);
    max_val = max(all_points, [], 1);
    range_val = max_val - min_val + 1e-6;

    global_fronts = fast_non_dominated_sorting_simple(all_points);
    reference_front_raw = all_points(global_fronts{1}, :);
    ref_front = (reference_front_raw - min_val) ./ range_val;

    [GD_exp, SP_exp] = compute_metrics(gen_fronts_exp, ref_front, min_val, range_val);
    [GD_base, SP_base] = compute_metrics(gen_fronts_base, ref_front, min_val, range_val);

    gens = (1:max_gen)';
    metrics_tbl = table(gens, GD_exp(:), SP_exp(:), GD_base(:), SP_base(:), ...
        'VariableNames', {'Generation', 'GD_exp', 'SP_exp', 'GD_base', 'SP_base'});

    save_metrics_snapshots(snapshot_dir, scenario_name, metrics_tbl, ref_front, min_val, max_val, range_val);

    if prefer_saved_for_plot && exist(saved_metrics_path, 'file')
        metrics_tbl = load_metrics_table(saved_metrics_path);
    end

    plot_metric_figures(metrics_tbl.Generation, metrics_tbl.GD_exp, metrics_tbl.GD_base, ...
        metrics_tbl.SP_exp, metrics_tbl.SP_base, scenario_name);
end

%% ================== 内部辅助函数 ==================

function [GD, SP] = compute_metrics(gen_fronts, ref_front, min_val, range_val)
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

function plot_metric_figures(gens, GD_exp, GD_base, SP_exp, SP_base, scenario_name)
    scenario_label = upper(char(string(scenario_name)));

    figure('Name', ['收敛性对比分析 (GD) - ' scenario_label], ...
        'Color', 'w', 'Position', [100, 200, 700, 500]);
    plot(gens, GD_exp, '-', 'LineWidth', 1.5, 'MarkerSize', 4, 'Color', '#D95319');
    hold on;
    plot(gens,GD_base, '--', 'LineWidth', 1.5, 'MarkerSize', 4, 'Color', '#7E2F8E');
    xlabel('迭代次数 (Generation)', 'FontSize', 11);
    ylabel('GD 值', 'FontSize', 11);
    legend('实验组 (改进 NSGA-II算法)','对照组 (标准 NSGA-II算法)',  'Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;
    set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.4);

    figure('Name', ['多样性对比分析 (SP) - ' scenario_label], ...
        'Color', 'w', 'Position', [850, 200, 700, 500]);
    plot(gens, SP_exp,'-', 'LineWidth', 1.5, 'MarkerSize', 4, 'Color', '#D95319');
    hold on;
    plot(gens, SP_base,  '--', 'LineWidth', 1.5, 'MarkerSize', 4, 'Color', '#7E2F8E');
    xlabel('迭代次数 (Generation)', 'FontSize', 11);
    ylabel('SP 值', 'FontSize', 11);
    legend('改进 NSGA-II (实验组)','标准 NSGA-II (对照组)',  'Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
    grid on;
    set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.4);
end

function save_metrics_snapshots(snapshot_dir, scenario_name, metrics_tbl, ref_front, min_val, max_val, range_val)
    latest_mat_path = fullfile(snapshot_dir, [scenario_name '_latest_metrics.mat']);
    latest_csv_path = fullfile(snapshot_dir, [scenario_name '_latest_metrics.csv']);
    manual_csv_path = fullfile(snapshot_dir, [scenario_name '_manual_metrics.csv']);
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    snapshot_mat_path = fullfile(snapshot_dir, [scenario_name '_' timestamp '_metrics.mat']);
    snapshot_csv_path = fullfile(snapshot_dir, [scenario_name '_' timestamp '_metrics.csv']);

    save(latest_mat_path, 'metrics_tbl', 'ref_front', 'min_val', 'max_val', 'range_val');
    save(snapshot_mat_path, 'metrics_tbl', 'ref_front', 'min_val', 'max_val', 'range_val');

    writetable(metrics_tbl, latest_csv_path);
    writetable(metrics_tbl, snapshot_csv_path);

    if ~exist(manual_csv_path, 'file')
        writetable(metrics_tbl, manual_csv_path);
    end

    fprintf('>> [MOEA] Metrics saved to:\n');
    fprintf('   - MAT : %s\n', latest_mat_path);
    fprintf('   - CSV : %s\n', latest_csv_path);
    fprintf('   - Manual CSV template: %s\n', manual_csv_path);
end

function tbl = load_metrics_table(csv_path)
    if ~exist(csv_path, 'file')
        error('evaluate_and_plot_moea:MissingSavedMetrics', ...
            '未找到保存的指标文件: %s', csv_path);
    end

    tbl = readtable(csv_path);
    required_cols = {'Generation', 'GD_exp', 'SP_exp', 'GD_base', 'SP_base'};
    for i = 1:numel(required_cols)
        if ~ismember(required_cols{i}, tbl.Properties.VariableNames)
            error('evaluate_and_plot_moea:InvalidSavedMetrics', ...
                '指标文件缺少必要列: %s', required_cols{i});
        end
    end
end

function value = get_option(opts, field_name, default_value)
    if isstruct(opts) && isfield(opts, field_name) && ~isempty(opts.(field_name))
        value = opts.(field_name);
    else
        value = default_value;
    end
end

function scenario_name = infer_scenario_name()
    scenario_name = 'moea';
    stack = dbstack('-completenames');
    for i = 1:numel(stack)
        caller_name = lower(stack(i).name);
        caller_file = lower(stack(i).file);
        if contains(caller_name, 'fork') || contains(caller_file, 'ga_text_scirpt_for_fork')
            scenario_name = 'fork';
            return;
        end
        if contains(caller_name, 'lift') || contains(caller_file, 'ga_text_scirpt_for_lift')
            scenario_name = 'lift';
            return;
        end
    end
end

function merged = vertcat_nonempty(fronts)
    merged = [];
    for i = 1:numel(fronts)
        if ~isempty(fronts{i})
            merged = [merged; fronts{i}]; %#ok<AGROW>
        end
    end
end
