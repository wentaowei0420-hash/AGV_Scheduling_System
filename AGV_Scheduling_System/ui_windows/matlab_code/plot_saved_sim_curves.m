function plot_saved_sim_curves(scenario_name)
%PLOT_SAVED_SIM_CURVES Plot dist/time/energy curves from manually edited CSV.
%   plot_saved_sim_curves('fork') reads fork_manual_plot_data.csv.
%   plot_saved_sim_curves('lift') reads lift_manual_plot_data.csv.

    if nargin < 1 || isempty(scenario_name)
        scenario_name = 'fork';
    end

    scenario_name = lower(string(scenario_name));
    if scenario_name ~= "fork" && scenario_name ~= "lift"
        error('scenario_name must be ''fork'' or ''lift''.');
    end

    base_dir = fileparts(mfilename('fullpath'));
    snapshot_dir = fullfile(base_dir, 'sim_plot_snapshots');
    csv_path = fullfile(snapshot_dir, sprintf('%s_manual_plot_data.csv', scenario_name));

    if ~isfile(csv_path)
        error('Manual plot CSV not found: %s', csv_path);
    end

    tbl = readtable(csv_path);
    required_cols = {'Generation', 'dist_exp', 'dist_base', 'time_exp', 'time_base', 'energy_exp', 'energy_base'};
    for i = 1:numel(required_cols)
        if ~ismember(required_cols{i}, tbl.Properties.VariableNames)
            error('Manual plot CSV is missing required column: %s', required_cols{i});
        end
    end

    if scenario_name == "fork"
        figure('Name', '叉车式AGV距离收敛对比', 'Color', 'w', 'Position', [100, 100, 700, 500]);
        plot(tbl.dist_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进NSGA-II算法）');
        hold on;
        plot(tbl.dist_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准NSGA-II算法）');
        xlabel('迭代次数 (Generation)', 'FontSize', 12);
        ylabel('行驶总距离 (Distance / m)', 'FontSize', 12);
        grid on;
        legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
        axis tight;

        figure('Name', '叉车式AGV完工时间收敛对比', 'Color', 'w', 'Position', [150, 150, 700, 500]);
        plot(tbl.time_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进NSGA-II算法）');
        hold on;
        plot(tbl.time_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准NSGA-II算法）');
        xlabel('迭代次数 (Generation)', 'FontSize', 12);
        ylabel('最大完工时间 (Time / s)', 'FontSize', 12);
        grid on;
        legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
        axis tight;

        figure('Name', '叉车式AGV物理总能耗收敛对比', 'Color', 'w', 'Position', [200, 200, 700, 500]);
        plot(tbl.energy_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进NSGA-II算法）');
        hold on;
        plot(tbl.energy_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准NSGA-II算法）');
        xlabel('迭代次数 (Generation)', 'FontSize', 12);
        ylabel('系统总能耗 (Energy)', 'FontSize', 12);
        grid on;
        legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
        axis tight;
    else
        figure('Name', '托举式AGV物理能耗对比', 'Color', 'w', 'Position', [100, 100, 700, 500]);
        plot(tbl.energy_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进 NSGA-II）');
        hold on;
        plot(tbl.energy_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准 NSGA-II）');
        xlabel('迭代次数 (Generation)', 'FontSize', 12);
        ylabel('系统总能耗 (Energy / 相对单位)', 'FontSize', 12);
        grid on;
        set(gca, 'GridAlpha', 0.3);
        legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
        axis tight;

        figure('Name', '托举式AGV完工时间对比', 'Color', 'w', 'Position', [150, 150, 700, 500]);
        plot(tbl.time_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进 NSGA-II）');
        hold on;
        plot(tbl.time_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准 NSGA-II）');
        xlabel('迭代次数 (Generation)', 'FontSize', 12);
        ylabel('最大完工时间 (Time / s)', 'FontSize', 12);
        grid on;
        set(gca, 'GridAlpha', 0.3);
        legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
        axis tight;

        figure('Name', '托举式AGV算法性能对比', 'Color', 'w', 'Position', [200, 200, 700, 500]);
        plot(tbl.dist_exp, 'LineWidth', 1.5, 'Color', '#D95319', 'DisplayName', '实验组（改进 NSGA-II）');
        hold on;
        plot(tbl.dist_base, 'LineWidth', 1.5, 'Color', '#7E2F8E', 'LineStyle', '--', 'DisplayName', '对照组（标准 NSGA-II）');
        xlabel('迭代次数 (Generation)', 'FontSize', 12);
        ylabel('行驶总距离 (Distance / m)', 'FontSize', 12);
        grid on;
        set(gca, 'GridAlpha', 0.3);
        legend('Location', 'northeast', 'FontSize', 12, 'FontWeight', 'bold');
        axis tight;
    end
end
