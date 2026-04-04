function ga_text_scirpt_for_lift()
    clc;
    close all;
    clear;

    style = local_plot_style();
    init_agv_plot_defaults(style);

    %% 1. 定义仿真场景与参数
    disp('>> [1/4] 正在初始化环境与物理参数...');
    global mapW mapH
    mapW = 70;
    mapH = 50;
    fprintf('   - 栅格地图构建完成: [%d x %d] 区域\n', mapW, mapH);

    % --- AGV 配置 ---
    load_agv_config;
    garage_coords_type1 = [
         6, 2; 7, 2; 10, 2; 11, 2;
         6, 3; 7, 3; 10, 3; 11, 3
    ];
    garage_coords_type2 = [
        47, 2; 48, 2; 49, 2;
        47, 3; 48, 3; 49, 3;
        47, 4; 48, 4; 49, 4
    ];

    depots_xy = zeros(num_agvs, 2);
    for i = 1:num_agvs
        t = agv_params(i).type;
        pos_id = agv_params(i).initial_position;
        if pos_id <= 0
            pos_id = 1;
        end

        if t == 1
            if pos_id > 8
                pos_id = 1;
            end
            depots_xy(i, :) = garage_coords_type1(pos_id, :);
        else
            if pos_id > 9
                pos_id = 1;
            end
            depots_xy(i, :) = garage_coords_type2(pos_id, :);
        end
    end
    depots = xy2rc(depots_xy);

    task_list = MES_Order_System_text_for_lift();
    % ga_path_debug_probe(task_list, depots, agv_types, agv_params, 'lift');
    if isempty(task_list)
        error('[致命错误] 传入的任务列表为空，没有需要执行的任务。');
    end

    % --- GA 参数 ---
    ga_params.pop_size = 80;
    ga_params.max_gen = 350;

    %% 2. 调用调度算法接口
    disp('>> [2/4] 启动算法组进行全局调度优化...');

    disp('   [执行] 实验组（改进 NSGA-II + CPO + 物理能耗建模）...');
    exp_timer = tic;
    [sched_exp, batch_exp, metrics_exp, hist_exp, pareto_improved] = ...
        ga_schedule_optimizer_update(task_list, num_agvs, depots, agv_params, ga_params, agv_types);
    exp_elapsed = toc(exp_timer);
    fprintf('   [完成] 实验组运行时间: %.3f s\n', exp_elapsed);

    disp('   [执行] 对照组（标准 NSGA-II / SGA Baseline）...');
    base_timer = tic;
    [sched_base, batch_base, metrics_base, hist_base, pareto_baseline] = ...
        ga_schedule_optimizer(task_list, num_agvs, depots, agv_params, ga_params, agv_types);
    base_elapsed = toc(base_timer);
    fprintf('   [完成] 对照组运行时间: %.3f s\n', base_elapsed);

    %% 3. 打印终端调度报告
    disp('>> [3/4] 正在生成 AGV 分批调度与指标评估报告...');

    fprintf('\n================ 实验组（Proposed）批次规划明细 ================\n');
    print_batch_info(batch_exp, agv_types);

    fprintf('\n================ 对照组（Baseline）批次规划明细 ================\n');
    print_batch_info(batch_base, agv_types);

    fprintf('\n================ 核心优化指标对比 (Metrics) ================\n');
    fprintf('【托举式 AGV 车队 (Lift)】\n');
    fprintf('   -> 实验组: 总行驶距离 %6.1f m  |  最大完工时间 %6.1f s  |  总能耗 %6.2f\n', ...
            metrics_exp.lift.dist, metrics_exp.lift.time, metrics_exp.lift.energy);
    fprintf('   -> 对照组: 总行驶距离 %6.1f m  |  最大完工时间 %6.1f s  |  总能耗 %6.2f\n', ...
            metrics_base.lift.dist, metrics_base.lift.time, metrics_base.lift.energy);

    fprintf('\n【叉车式 AGV 车队 (Fork)】\n');
    fprintf('   -> 实验组: 总行驶距离 %6.1f m  |  最大完工时间 %6.1f s  |  总能耗 %6.2f\n', ...
            metrics_exp.fork.dist, metrics_exp.fork.time, metrics_exp.fork.energy);
    fprintf('   -> 对照组: 总行驶距离 %6.1f m  |  最大完工时间 %6.1f s  |  总能耗 %6.2f\n', ...
            metrics_base.fork.dist, metrics_base.fork.time, metrics_base.fork.energy);
    fprintf('   -> 实验组运行时间 %6.3f s  |  对照组运行时间 %6.3f s\n', exp_elapsed, base_elapsed);
    fprintf('============================================================\n');
    fprintf('   * 运行时间优化率: %.1f%%\n', ...
            (base_elapsed - exp_elapsed) / max(base_elapsed, 1e-9) * 100);

    %% 4. 绘制学术图表
    disp('>> [4/4] 正在绘制学术图表...');

    plot_convergence_compare( ...
        '托举式AGV物理能耗对比', ...
        '托举式 AGV 物理总能耗收敛对比图', ...
        '迭代次数 (Generation)', ...
        '系统总能耗 (Energy / 相对单位)', ...
        hist_exp.lift.energy, hist_base.lift.energy, style, [100, 100, 700, 500]);

    plot_convergence_compare( ...
        '托举式AGV完工时间对比', ...
        '托举式 AGV 最大完工时间收敛对比图', ...
        '迭代次数 (Generation)', ...
        '最大完工时间 (Time / s)', ...
        hist_exp.lift.time, hist_base.lift.time, style, [150, 150, 700, 500]);

    plot_convergence_compare( ...
        '托举式AGV算法性能对比', ...
        '托举式 AGV 配送总距离收敛对比图', ...
        '迭代次数 (Generation)', ...
        '行驶总距离 (Distance / m)', ...
        hist_exp.lift.dist, hist_base.lift.dist, style, [200, 200, 700, 500]);

    figure('Name', 'Pareto Front Comparison (Lift)', 'Color', 'w', 'Position', [250, 250, 1000, 450]);

    subplot(1, 2, 1);
    scatter3(pareto_baseline.lift(:,1), pareto_baseline.lift(:,2), pareto_baseline.lift(:,3), ...
        70, style.base_color, 'filled', 'MarkerFaceAlpha', 0.85);
    style_pareto_axes(style, '(a) 标准 NSGA-II 算法');

    subplot(1, 2, 2);
    scatter3(pareto_improved.lift(:,1), pareto_improved.lift(:,2), pareto_improved.lift(:,3), ...
        70, style.exp_color, 'filled', 'MarkerFaceAlpha', 0.85);
    style_pareto_axes(style, '(b) 改进 NSGA-II 算法');

    sgtitle('标准 NSGA-II 与改进 NSGA-II Pareto 前沿对比（托举式 AGV）', ...
        'FontSize', style.sgtitle_font, 'FontWeight', 'bold', 'FontName', style.cn_font, 'Interpreter', 'none');

    evaluate_and_plot_moea(hist_exp.lift.gen_fronts, hist_base.lift.gen_fronts);

    %% 5. 打印全局任务序列
    fprintf('\n================ 全局调度任务序列 (Schedules) ================\n');
    for k = 1:num_agvs
        type_str = '未知';
        if agv_types(k) == 1
            type_str = '托举式';
        elseif agv_types(k) == 2
            type_str = '叉车式';
        end

        fprintf(' AGV-%02d (%s):\n', k, type_str);
        fprintf('   - 实验组 %s\n', mat2str(sched_exp{k}));
        fprintf('   - 对照组 %s\n', mat2str(sched_base{k}));
    end
    disp('==============================================================');
end

function style = local_plot_style()
    style = agv_plot_theme('paper');
end

function plot_convergence_compare(fig_name, fig_title, x_label, y_label, exp_data, base_data, style, fig_pos)
    figure('Name', fig_name, 'Color', 'w', 'Position', fig_pos);
    plot(exp_data, 'LineWidth', style.line_width, 'Color', style.exp_color, ...
        'DisplayName', '实验组（改进 NSGA-II 算法）');
    hold on;
    plot(base_data, 'LineWidth', style.line_width, 'Color', style.base_color, ...
        'LineStyle', '--', 'DisplayName', '对照组（标准 NSGA-II 算法）');
    set(gca, 'FontName', style.en_font, 'FontSize', style.axis_font, 'GridAlpha', style.grid_alpha, 'LineWidth', 1);
    grid on;
    title(fig_title, 'FontSize', style.title_font, 'FontWeight', 'bold', 'FontName', style.cn_font, 'Interpreter', 'none');
    xlabel(x_label, 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    ylabel(y_label, 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    legend('Location', 'northeast', 'FontSize', style.axis_font, 'FontName', style.cn_font);
    axis tight;
end

function style_pareto_axes(style, fig_title)
    grid on;
    view(45, 25);
    set(gca, 'FontName', style.en_font, 'FontSize', style.axis_font, 'GridAlpha', style.grid_alpha, 'LineWidth', 1);
    xlabel('最短行驶距离 / m', 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    ylabel('最大完工时间 / s', 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    zlabel('最小总能耗 / J', 'FontSize', style.label_font, 'FontName', style.cn_font, 'Interpreter', 'none');
    title(fig_title, 'FontSize', style.title_font, 'FontWeight', 'bold', 'FontName', style.cn_font, 'Interpreter', 'none');
end

function print_batch_info(batch_info, agv_types)
    for i = 1:length(batch_info)
        if agv_types(i) == 2
            fprintf('AGV %d (叉车式): 采用单件串行模式，无批次信息，请直接查看 schedules\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        if isempty(batch_info{i})
            fprintf('AGV %d (托举式): [空闲] 无分配任务\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        info = batch_info{i};
        fprintf('AGV %d (托举式): 总计出车 %d 趟\n', i, info.num_batches);
        for b = 1:info.num_batches
            taskListStr = strjoin(arrayfun(@num2str, info.task_batches{b}, 'UniformOutput', false), ', ');
            fprintf('  [第 %d 趟]: 任务清单 [%s], 总重: %.1f kg\n', b, taskListStr, info.batch_weights(b));
        end
        fprintf('--------------------------------------------------\n');
    end
end