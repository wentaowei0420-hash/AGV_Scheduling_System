function ga_text_scirpt_for_fork()
    clc;
    close all;
    clear;

    %% 1. 定义仿真场景与参数
    disp('>> [1/4] 正在初始化环境与物理参数...');
    global mapW mapH binaryMap
    mapW = 70;
    mapH = 50;

    binaryMap = create_binary_grid_map(mapW, mapH, 0);
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

    task_list = MES_Order_System_text_for_fork();

    % --- GA 参数 ---
    ga_params.pop_size = 80;
    ga_params.max_gen = 250;

    %% 2. 调用封装好的高级算法接口
    disp('>> [2/4] 启动算法组进行叉车全局调度优化对比...');

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
    disp('>> [3/4] 正在生成 AGV 指标评估报告...');

    fprintf('\n================ 叉车式 AGV 核心指标对比 (Metrics) ================\n');
    fprintf('   -> 实验组: 总行驶距离 %6.1f m  |  最大完工时间 %6.1f s  |  总能耗 %6.2f\n', ...
            metrics_exp.fork.dist, metrics_exp.fork.time, metrics_exp.fork.energy);
    fprintf('   -> 对照组: 总行驶距离 %6.1f m  |  最大完工时间 %6.1f s  |  总能耗 %6.2f\n', ...
            metrics_base.fork.dist, metrics_base.fork.time, metrics_base.fork.energy);
    fprintf('   -> 实验组运行时间: %6.3f s  |  对照组运行时间: %6.3f s\n', ...
            exp_elapsed, base_elapsed);
    fprintf('-------------------------------------------------------------------\n');
    fprintf('   * 优化率(距离): %.1f%%  |  优化率(时间): %.1f%%  |  优化率(能耗): %.1f%%\n', ...
            (metrics_base.fork.dist - metrics_exp.fork.dist) / metrics_base.fork.dist * 100, ...
            (metrics_base.fork.time - metrics_exp.fork.time) / metrics_base.fork.time * 100, ...
            (metrics_base.fork.energy - metrics_exp.fork.energy) / metrics_base.fork.energy * 100);
    fprintf('   * 运行时间优化率: %.1f%%\n', ...
            (base_elapsed - exp_elapsed) / max(base_elapsed, 1e-9) * 100);
    fprintf('===================================================================\n');

    %% 4. 绘制学术对比图
    disp('>> [4/4] 正在绘制学术收敛曲线...');

    % 图 1：总行驶距离收敛对比
    figure('Name', '叉车式AGV距离收敛对比', 'Color', 'w', 'Position', [100, 100, 700, 500]);
    plot(hist_exp.fork.dist, 'LineWidth', 2.5, 'Color', '#D95319', 'DisplayName', '实验组（改进NSGA-II算法）');
    hold on;
    plot(hist_base.fork.dist, 'LineWidth', 2.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准NSGA-II算法）');
    title('叉车式 AGV 最优行驶距离收敛对比', 'FontSize', 14);
    xlabel('迭代次数 (Generation)', 'FontSize', 12);
    ylabel('行驶总距离 (Distance / m)', 'FontSize', 12);
    grid on; legend('Location', 'northeast'); axis tight;

    % 图 2：最大完工时间收敛对比
    figure('Name', '叉车式AGV完工时间收敛对比', 'Color', 'w', 'Position', [150, 150, 700, 500]);
    plot(hist_exp.fork.time, 'LineWidth', 2.5, 'Color', '#D95319', 'DisplayName', '实验组（改进NSGA-II算法）');
    hold on;
    plot(hist_base.fork.time, 'LineWidth', 2.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准NSGA-II算法）');
    title('叉车式 AGV 最大完工时间性能对比', 'FontSize', 14);
    xlabel('迭代次数 (Generation)', 'FontSize', 12);
    ylabel('最大完工时间 (Time / s)', 'FontSize', 12);
    grid on; legend('Location', 'northeast'); axis tight;

    % 图 3：物理总能耗收敛对比
    figure('Name', '叉车式AGV物理总能耗收敛对比', 'Color', 'w', 'Position', [200, 200, 700, 500]);
    plot(hist_exp.fork.energy, 'LineWidth', 2.5, 'Color', '#D95319', 'DisplayName', '实验组（改进NSGA-II算法）');
    hold on;
    plot(hist_base.fork.energy, 'LineWidth', 2.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准NSGA-II算法）');
    title('叉车式 AGV 物理总能耗性能对比', 'FontSize', 14);
    xlabel('迭代次数 (Generation)', 'FontSize', 12);
    ylabel('系统总能耗 (Energy)', 'FontSize', 12);
    grid on; legend('Location', 'northeast'); axis tight;

    %% 绘制 3D Pareto 解集对比图（以叉车为例）
    front_base = pareto_baseline.fork;
    front_impr = pareto_improved.fork;

    figure('Name', 'Pareto Front Comparison', 'Color', 'w', 'Position', [100, 100, 1000, 450]);

    subplot(1, 2, 1);
    scatter3(front_base(:,1), front_base(:,2), front_base(:,3), 80, 'r', '*');
    grid on;
    view(45, 25);
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
    xlabel('最短行驶距离 / m', 'FontSize', 12, 'FontName', '宋体');
    ylabel('最大完工时间 / s', 'FontSize', 12, 'FontName', '宋体');
    zlabel('最小总能耗 / J', 'FontSize', 12, 'FontName', '宋体');
    title('(a) 标准 NSGA-II 算法', 'FontSize', 14, 'FontName', '宋体');

    subplot(1, 2, 2);
    scatter3(front_impr(:,1), front_impr(:,2), front_impr(:,3), 80, 'r', '*');
    grid on;
    view(45, 25);
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 10);
    xlabel('最短行驶距离 / m', 'FontSize', 12, 'FontName', '宋体');
    ylabel('最大完工时间 / s', 'FontSize', 12, 'FontName', '宋体');
    zlabel('最小总能耗 / J', 'FontSize', 12, 'FontName', '宋体');
    title('(b) 改进 NSGA-II 算法', 'FontSize', 14, 'FontName', '宋体');
    sgtitle('标准 NSGA-II 与改进 NSGA-II Pareto 前沿对比（叉车式AGV）', 'FontSize', 15, 'FontWeight', 'bold', 'FontName', '宋体');

    evaluate_and_plot_moea(hist_exp.fork.gen_fronts, hist_base.fork.gen_fronts);

    %% 5. 打印任务序列明细
    fprintf('\n================ 叉车调度任务序列明细 (Schedules) ================\n');
    for k = 1:num_agvs
        if agv_types(k) == 2
            fprintf(' AGV-%02d (叉车式):\n', k);
            fprintf('   - 实验组 %s\n', mat2str(sched_exp{k}));
            fprintf('   - 对照组 %s\n', mat2str(sched_base{k}));
        end
    end
    disp('==================================================================');
end
