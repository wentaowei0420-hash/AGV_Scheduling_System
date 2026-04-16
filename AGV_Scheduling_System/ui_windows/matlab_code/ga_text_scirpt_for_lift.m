function ga_text_scirpt_for_lift()
    clc;
    close all;
    clear;
    plot_data_opts = struct( ...
        'mode', 'live', ...
        'prefer_saved_for_plot', false);

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
        47, 4; 48, 4; 49, 4;
    ];

    % 动态提取并生成所有 AGV 的起点矩阵
    depots_xy = zeros(num_agvs, 2);
    for i = 1:num_agvs
        t = agv_params(i).type;
        pos_id = agv_params(i).initial_position;
        if pos_id <= 0, pos_id = 1; end

        if t == 1
            if pos_id > 8, pos_id = 1; end
            depots_xy(i, :) = garage_coords_type1(pos_id, :);
        else
            if pos_id > 9, pos_id = 1; end
            depots_xy(i, :) = garage_coords_type2(pos_id, :);
        end
    end
    depots = xy2rc(depots_xy);

    % 提取订单任务
    task_list = MES_Order_System_text_for_lift();
    if isempty(task_list)
        error('[致命错误] 传入的任务列表为空，没有需要执行的任务。');
    end

    % --- GA 参数 ---
    ga_params.pop_size = 80;
    ga_params.max_gen = 350;

    %% 2. 调用封装好的高级算法接口
    disp('>> [2/4] 启动算法组进行全局调度优化...');

    disp('   [执行] 实验组（改进 NSGA-II + CPO + 物理能耗建模）...');
    exp_timer = tic;
    [sched_exp, batch_exp, metrics_exp, hist_exp, pareto_improved] = ...
        ga_schedule_optimizer_update_standard(task_list, num_agvs, depots, agv_params, ga_params, agv_types);
    exp_elapsed = toc(exp_timer);
    fprintf('   [完成] 实验组运行时间: %.3f s\n', exp_elapsed);

    disp('   [执行] 对照组（标准 NSGA-II / SGA Baseline）...');
    base_timer = tic;
    [sched_base, batch_base, metrics_base, hist_base, pareto_baseline] = ...
        ga_schedule_optimizer_standard(task_list, num_agvs, depots, agv_params, ga_params, agv_types);
    base_elapsed = toc(base_timer);
    fprintf('   [完成] 对照组运行时间: %.3f s\n', base_elapsed);

    %% 3. 打印终端调度报告
    disp('>> [3/4] 正在生成 AGV 分批调度与指标评估报告...');

    fprintf('\n================ 实验组（Proposed）批次规划明细 ================\n');
    for i = 1:length(batch_exp)
        if agv_types(i) == 2
            fprintf('AGV %d (叉车式): 采用单件串行模式，无批次信息，请直接查看 schedules\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        if isempty(batch_exp{i})
            fprintf('AGV %d (托举式): [空闲] 无分配任务\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        info = batch_exp{i};
        fprintf('AGV %d (托举式): 总计出车 %d 趟\n', i, info.num_batches);
        for b = 1:info.num_batches
            taskListStr = strjoin(arrayfun(@num2str, info.task_batches{b}, 'UniformOutput', false), ', ');
            fprintf('  [第 %d 趟]: 任务清单 [%s], 总重: %.1f kg\n', b, taskListStr, info.batch_weights(b));
        end
        fprintf('--------------------------------------------------\n');
    end

    fprintf('\n================ 对照组（Baseline）批次规划明细 ================\n');
    for i = 1:length(batch_base)
        if agv_types(i) == 2
            fprintf('AGV %d (叉车式): 采用单件串行模式，无批次信息，请直接查看 schedules\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        if isempty(batch_base{i})
            fprintf('AGV %d (托举式): [空闲] 无分配任务\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        info = batch_base{i};
        fprintf('AGV %d (托举式): 总计出车 %d 趟\n', i, info.num_batches);
        for b = 1:info.num_batches
            taskListStr = strjoin(arrayfun(@num2str, info.task_batches{b}, 'UniformOutput', false), ', ');
            fprintf('  [第 %d 趟]: 任务清单 [%s], 总重: %.1f kg\n', b, taskListStr, info.batch_weights(b));
        end
        fprintf('--------------------------------------------------\n');
    end

    %% 4. 打印宏观指标对比
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
    fprintf('   -> 实验组运行时间: %6.3f s  |  对照组运行时间: %6.3f s\n', ...
            exp_elapsed, base_elapsed);
    fprintf('============================================================\n');
    fprintf('   * 运行时间优化率: %.1f%%\n', ...
            (base_elapsed - exp_elapsed) / max(base_elapsed, 1e-9) * 100);

    %% 5. 绘制收敛对比图
    disp('>> [4/4] 正在绘制学术图表...');

    % 图：总能耗对比
    figure('Name', '托举式AGV物理能耗对比', 'Color', 'w', 'Position', [100, 100, 700, 500]);
    gens = (1:length(hist_exp.lift.dist))';
    live_plot_tbl = table( ...
        gens, ...
        hist_exp.lift.dist(:), hist_base.lift.dist(:), ...
        hist_exp.lift.time(:), hist_base.lift.time(:), ...
        hist_exp.lift.energy(:), hist_base.lift.energy(:), ...
        'VariableNames', {'Generation', 'dist_exp', 'dist_base', 'time_exp', 'time_base', 'energy_exp', 'energy_base'});
    plot_tbl = save_and_select_sim_plot_data('lift', live_plot_tbl, plot_data_opts);
    plot(plot_tbl.energy_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进 NSGA-II算法）');
    hold on;
    plot(plot_tbl.energy_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准 NSGA-II算法）');
    xlabel('迭代次数 (Generation)', 'FontSize', 12);
    ylabel('系统总能耗 (Energy / 相对单位)', 'FontSize', 12);
    grid on; set(gca, 'GridAlpha', 0.3);
    legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
    axis tight;

    % 图：最大完工时间对比
    figure('Name', '托举式AGV完工时间对比', 'Color', 'w', 'Position', [150, 150, 700, 500]);
    plot(plot_tbl.time_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进 NSGA-II算法）');
    hold on;
    plot(plot_tbl.time_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准 NSGA-II算法）');
    xlabel('迭代次数 (Generation)', 'FontSize', 12);
    ylabel('最大完工时间 (Time / s)', 'FontSize', 12);
    grid on; set(gca, 'GridAlpha', 0.3);
    legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
    axis tight;

    % 图：总距离对比
    figure('Name', '托举式AGV算法性能对比', 'Color', 'w', 'Position', [200, 200, 700, 500]);
    plot(plot_tbl.dist_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进 NSGA-II算法）');
    hold on;
    plot(plot_tbl.dist_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准 NSGA-II算法）');
    xlabel('迭代次数 (Generation)', 'FontSize', 12);
    ylabel('行驶总距离 (Distance / m)', 'FontSize', 12);
    grid on; set(gca, 'GridAlpha', 0.3);
    legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
    axis tight;

    %% 绘制 3D Pareto 解集对比图（以托举式为例）
    front_base = pareto_baseline.lift;
    front_impr = pareto_improved.lift;

    figure('Name', 'Pareto Front Comparison (Lift)', 'Color', 'w', 'Position', [250, 250, 1000, 450]);

    subplot(1, 2, 1);
    scatter3(front_base(:,1), front_base(:,2), front_base(:,3), 80, 'r', '*');
    grid on;
    view(45, 25);
    xlabel('最短行驶距离 / m', 'FontSize', 12);
    ylabel('最大完工时间 / s', 'FontSize', 12);
    zlabel('最小总能耗 / J', 'FontSize', 12);
    title('(a) 标准 NSGA-II 算法', 'FontSize', 12);

    subplot(1, 2, 2);
    scatter3(front_impr(:,1), front_impr(:,2), front_impr(:,3), 80, 'r', '*');
    grid on;
    view(45, 25);
    xlabel('最短行驶距离 / m', 'FontSize', 12);
    ylabel('最大完工时间 / s', 'FontSize', 12);
    zlabel('最小总能耗 / J', 'FontSize', 12);
    title('(b) 改进 NSGA-II 算法', 'FontSize', 12);
    sgtitle('标准 NSGA-II 与改进 NSGA-II Pareto 前沿对比（托举式AGV）', 'FontSize', 14, 'FontWeight', 'bold');

    evaluate_and_plot_moea(hist_exp.lift.gen_fronts, hist_base.lift.gen_fronts);

    %% 6. 打印全局任务序列
    fprintf('\n================ 全局调度任务序列 (Schedules) ================\n');
    for k = 1:num_agvs
        type_str = '未知';
        if agv_types(k) == 1, type_str = '托举式'; end
        if agv_types(k) == 2, type_str = '叉车式'; end

        fprintf(' AGV-%02d (%s):\n', k, type_str);
        fprintf('   - 实验组 %s\n', mat2str(sched_exp{k}));
        fprintf('   - 对照组 %s\n', mat2str(sched_base{k}));
    end
    disp('==============================================================');
end
