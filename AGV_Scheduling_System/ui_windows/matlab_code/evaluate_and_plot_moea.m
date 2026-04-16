function evaluate_and_plot_moea(gen_fronts_exp, gen_fronts_base)
% evaluate_and_plot_moea_comparison 分析并绘制实验组与对照组的收敛性与多样性对比曲线
% 输入: 
%   gen_fronts_exp  - 改进 NSGA-II (实验组) 每一代的 Pareto 前沿
%   gen_fronts_base - 标准 NSGA-II (对照组) 每一代的 Pareto 前沿

    max_gen = length(gen_fronts_exp); % 假设两者迭代次数一致
    
    %% 1. 数据归一化与【全局参考前沿】提取 (至关重要)
    % 必须将两个算法产生的所有解合并，才能找到真正的全局最优参考前沿和统一的归一化边界
    all_points_exp = vertcat(gen_fronts_exp{:});
    all_points_base = vertcat(gen_fronts_base{:});
    all_points = [all_points_exp; all_points_base];
    
    % 计算全局最小/最大值
    min_val = min(all_points, [], 1);
    max_val = max(all_points, [], 1);
    range_val = max_val - min_val + 1e-6; % 防止除以 0
    
    % 获取两个算法合力产生出的最强“真实帕累托前沿”
    global_fronts = fast_non_dominated_sorting_simple(all_points);
    reference_front_raw = all_points(global_fronts{1}, :);
    
    % 对全局参考前沿进行归一化
    ref_front = (reference_front_raw - min_val) ./ range_val;
    
    %% 2. 分别计算实验组和对照组的 GD 和 SP
    % 调用底部封装好的子函数，确保评价标准完全一致
    [GD_exp, SP_exp] = compute_metrics(gen_fronts_exp, ref_front, min_val, range_val);
    [GD_base, SP_base] = compute_metrics(gen_fronts_base, ref_front, min_val, range_val);
    
    %% 3. 绘制独立评估对比曲线
    gens = 1:max_gen;
    
    % =========================================================
    % 第 1 张图：绘制收敛性对比曲线 (GD)
    % =========================================================
    figure('Name', '收敛性对比分析 (Generational Distance)', 'Color', 'w', 'Position', [100, 200, 700, 500]);
    
    % 绘制对照组 (灰色，方形标记，稍细)
    plot(gens, GD_base, '-', 'LineWidth', 1.5, 'MarkerSize', 4, 'Color', '#D95319'); 
    hold on;
    % 绘制实验组 (亮橙色，圆形标记，加粗突出)
    plot(gens, GD_exp, '-', 'LineWidth', 1.5, 'MarkerSize', 4, 'Color', '#7E2F8E','LineStyle', '--');
    xlabel('迭代次数 (Generation)', 'FontSize', 11);
    ylabel('GD 值 ', 'FontSize', 11);
    legend('标准 NSGA-II (对照组)', '改进 NSGA-II (实验组)', 'Location', 'northeast');
    grid on;
    set(gca, 'GridLineStyle', '--', 'GridAlpha', 0.4);
    

end

%% ================== 以下为内部辅助函数 ==================

function [GD, SP] = compute_metrics(gen_fronts, ref_front, min_val, range_val)
% 内部函数：给定某算法的前沿历史、全局参考前沿及归一化参数，计算其 GD 和 SP
    max_gen = length(gen_fronts);
    GD = zeros(1, max_gen); 
    SP = zeros(1, max_gen); 
    
    for gen = 1:max_gen
        current_front_raw = gen_fronts{gen};
        
        if isempty(current_front_raw)
            GD(gen) = NaN; SP(gen) = NaN;
            continue;
        end
        
        % 剔除这一代前沿中的重复解
        current_front_raw = unique(current_front_raw, 'rows');
        n_points = size(current_front_raw, 1);
        
        % 当前代前沿归一化 (使用全局极值)
        curr_front = (current_front_raw - min_val) ./ range_val;
        
        % --- 计算 GD ---
        if n_points == 0
            GD(gen) = NaN;
        else
            sum_d = 0;
            for i = 1:n_points
                d_i = min(sqrt(sum((ref_front - curr_front(i,:)).^2, 2)));
                sum_d = sum_d + d_i^2;
            end
            GD(gen) = sqrt(sum_d) / n_points;
        end
        
        % --- 计算 SP ---
        if n_points < 2
            SP(gen) = NaN; 
        else
            d_nn = zeros(n_points, 1); 
            for i = 1:n_points
                distances = sum(abs(curr_front - curr_front(i,:)), 2);
                distances(i) = inf; 
                d_nn(i) = min(distances);
            end
            d_mean = mean(d_nn);
            SP(gen) = sqrt(sum((d_mean - d_nn).^2) / (n_points - 1));
        end
    end
end

function fronts = fast_non_dominated_sorting_simple(pop_objs)
% 简化的非支配排序函数，仅提取第一前沿
    pop_size = size(pop_objs, 1);
    fronts = cell(1, 1);
    domination_count = zeros(pop_size, 1);
    for i = 1:pop_size
        for j = 1:pop_size
            if i == j, continue; end
            if all(pop_objs(j,:) <= pop_objs(i,:)) && any(pop_objs(j,:) < pop_objs(i,:))
                domination_count(i) = domination_count(i) + 1;
                break; 
            end
        end
        if domination_count(i) == 0
            fronts{1} = [fronts{1}, i];
        end
    end
end