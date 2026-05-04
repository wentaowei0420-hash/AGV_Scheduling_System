function [best_schedule, batch_details, metrics, history, pareto_fronts] = ga_schedule_optimizer_update(task_list, num_agvs, depots, agv_params, ga_params, agv_types)
% =========================================================================
% 主函数：基于NSGA-II的多AGV任务调度优化器（支持托举式与叉车式AGV）
%
% 输入参数：
%   task_list     - N×3 矩阵，每行 [任务ID, 目标区域ID, 负载重量]
%   num_agvs      - AGV总数
%   depots        - AGV起始位置矩阵，每行对应一个AGV的 [行, 列] 坐标
%   agv_params    - AGV参数结构体数组，包含 speed, e_base, e_load_factor 等字段
%   ga_params     - 遗传算法参数结构体，包含 .pop_size (种群大小) 和 .max_gen (最大代数)
%   agv_types     - AGV类型向量，1表示托举式AGV，2表示叉车式AGV
%
% 输出参数：
%   best_schedule - 1×num_agvs 的元胞数组，每个元素为对应AGV的任务执行顺序（任务ID向量）
%   batch_details - 1×num_agvs 的元胞数组，每个元素为托举式AGV的批次信息结构体
%   metrics       - 结构体，包含 .lift 和 .fork 的最终优化目标值 (dist, time, energy)
%   history       - 结构体，包含每代Pareto前沿的目标最小值以及各代前沿面数据
%   pareto_fronts - 结构体，包含 .lift 和 .fork 的最终第一前沿所有解的目标值矩阵
% =========================================================================

    % 构建区域距离Oracle（用于快速获取路径距离和候选点）
    oracle_options = struct();
    oracle_options.task_target_ids = unique(task_list(:, 2))';   % 所有出现的目标区域ID
    oracle_options.agv_types = unique(agv_types)';               % 所有使用的AGV类型
    path_oracle = region_distance_oracle('build', oracle_options);

    % 按任务目标区域ID进行划分：ID ≤ 12 为托举任务，>12 为叉车任务
    idx_lift_tasks = task_list(:,2) <= 12;
    idx_fork_tasks = task_list(:,2) > 12;
    
    tasks_lift = task_list(idx_lift_tasks, :);
    tasks_fork = task_list(idx_fork_tasks, :);
    
    % 获取不同类型AGV的ID列表
    agvs_lift = find(agv_types == 1); 
    agvs_fork = find(agv_types == 2); 
    
    % 初始化输出变量
    best_schedule = cell(1, num_agvs);
    batch_details = cell(1, num_agvs); 
    
    dist_lift = 0; time_lift = 0; energy_lift = 0;
    dist_fork = 0; time_fork = 0; energy_fork = 0;
    
    % 历史记录初始化：每代Pareto前沿的目标最小值（距离、时间、能量）
    hist_lift_dist = zeros(1, ga_params.max_gen);
    hist_lift_time = zeros(1, ga_params.max_gen);
    hist_lift_energy = zeros(1, ga_params.max_gen);
    
    hist_fork_dist = zeros(1, ga_params.max_gen);
    hist_fork_time = zeros(1, ga_params.max_gen);
    hist_fork_energy = zeros(1, ga_params.max_gen);

    gen_fronts_lift = {};  
    gen_fronts_fork = {};
    pareto_fronts = struct('lift', [], 'fork', []);

    %% ==================== 托举式AGV优化 ====================
    if ~isempty(tasks_lift) && ~isempty(agvs_lift)
        disp('   -> 启动 NSGA-II 引擎优化托举车 (多目标: 距离、时间、能耗)...');
        
        % 定义托举AGV的多目标评估函数句柄
        eval_lift_moo = @(chrom) cost_func_lift_moo(chrom, tasks_lift, agvs_lift, depots, agv_params, path_oracle);
        
        % 运行NSGA-II，返回种群、目标值、前沿面、拥挤距离及各代历史
        [pop_lift, objs_lift, fronts_lift, ~, hist_lift_dist, hist_lift_time, hist_lift_energy, gen_fronts_lift] = ...
            run_sub_nsga2_lift(tasks_lift, length(agvs_lift), ga_params, eval_lift_moo);
        
        % 获取第一前沿的个体索引及其目标值
        front1_idx = fronts_lift{1}; 
        front1_objs = objs_lift(front1_idx, :);
        
        % 使用TOPSIS多准则决策从第一前沿中选出妥协最优解
        best_idx_in_front1 = select_compromise_index(front1_objs);
        best_lift_chrom = pop_lift(front1_idx(best_idx_in_front1), :);
        
        % 评估该最优解并获取详细调度方案与批次信息
        [sched_lift, best_objs_lift, batch_info_lift] = eval_lift_moo(best_lift_chrom);
        dist_lift = best_objs_lift(1);          
        time_lift = best_objs_lift(2);          
        energy_lift = best_objs_lift(3);        
        
        % 将最优调度分配给对应的AGV
        for i = 1:length(agvs_lift)
            best_schedule{agvs_lift(i)} = sched_lift{i};
            batch_details{agvs_lift(i)} = batch_info_lift{i}; 
        end
    end 
    
    %% ==================== 叉车式AGV优化 ====================
    if ~isempty(tasks_fork) && ~isempty(agvs_fork)
        disp('   -> 启动 NSGA-II 引擎优化叉车 (多目标: 距离、时间、能耗)...');
        eval_fork_moo = @(chrom) cost_func_fork_moo(chrom, tasks_fork, agvs_fork, depots, agv_params, path_oracle);
        
        [pop_fork, objs_fork, fronts_fork, ~, hist_fork_dist, hist_fork_time, hist_fork_energy, gen_fronts_fork] = ...
            run_sub_nsga2_fork(tasks_fork, length(agvs_fork), ga_params, eval_fork_moo);
        
        % TOPSIS 妥协解选择
        front1_idx = fronts_fork{1}; 
        front1_objs = objs_fork(front1_idx, :);
        
        best_idx_in_front1 = select_compromise_index(front1_objs);      
        best_fork_chrom = pop_fork(front1_idx(best_idx_in_front1), :);
        
        [sched_fork, best_objs_fork] = eval_fork_moo(best_fork_chrom);
        dist_fork = best_objs_fork(1);          
        time_fork = best_objs_fork(2);          
        energy_fork = best_objs_fork(3); 
        
        for i = 1:length(agvs_fork)
            best_schedule{agvs_fork(i)} = sched_fork{i};
        end
    end
    
    %% ==================== 打包输出结果 ====================
    % 最终稳态指标
    metrics.lift.dist = dist_lift;       
    metrics.lift.time = time_lift;       
    metrics.lift.energy = energy_lift;   
    
    metrics.fork.dist = dist_fork;       
    metrics.fork.time = time_fork;       
    metrics.fork.energy = energy_fork;   
    
    % 算法迭代历史曲线
    history.lift.dist = hist_lift_dist;
    history.lift.time = hist_lift_time;
    history.lift.energy = hist_lift_energy;
    history.lift.gen_fronts = gen_fronts_lift;   % 各代第一前沿全部解的目标值
    
    history.fork.dist = hist_fork_dist;
    history.fork.time = hist_fork_time;
    history.fork.energy = hist_fork_energy;
    history.fork.gen_fronts = gen_fronts_fork;

    % 最终Pareto前沿（第一前沿的所有解）
    if ~isempty(tasks_lift) && ~isempty(agvs_lift) && exist('objs_lift', 'var') && exist('fronts_lift', 'var') && ~isempty(fronts_lift)
        pareto_fronts.lift = objs_lift(fronts_lift{1}, :);
    end
    if ~isempty(tasks_fork) && ~isempty(agvs_fork) && exist('objs_fork', 'var') && exist('fronts_fork', 'var') && ~isempty(fronts_fork)
        pareto_fronts.fork = objs_fork(fronts_fork{1}, :);
    end
end


%% ==================== 托举式AGV评估函数 ====================
function [schedules, objectives, batch_info] = cost_func_lift_moo(chromosome, tasks, agv_ids, depots, agv_params, path_oracle)
% 托举式AGV的染色体解码与多目标评估（距离、时间、能耗）
% 输入: chromosome [1, 2*num_tasks] 前一半为任务顺序排列，后一半为AGV分配
% 输出: schedules - 各AGV的任务序列（包含任务ID）
%        objectives - [总距离, 最大耗时, 总能耗]
%        batch_info - 各AGV的批次信息（包含批次划分与重量）

    num_tasks = size(tasks, 1);
    num_agvs = length(agv_ids);
    task_seq = chromosome(1:num_tasks);        % 任务执行顺序
    agv_assign = chromosome(num_tasks+1:end);  % 对应任务的AGV分配

    schedules = cell(1, num_agvs);
    batch_info = cell(1, num_agvs);
    agv_dists = zeros(1, num_agvs);
    agv_times = zeros(1, num_agvs);
    agv_energy = zeros(1, num_agvs);

    for k = 1:num_agvs
        real_agv_id = agv_ids(k);              % 实际AGV编号
        curr_agv = agv_params(real_agv_id);    % 获取该AGV的参数结构体
        my_tasks = task_seq(agv_assign == k);  % 属于该AGV的任务索引
        real_task_ids = tasks(my_tasks, 1)';   % 转换为真实任务ID
        schedules{k} = real_task_ids;

        if isempty(my_tasks)
            schedules{k} = [];
            continue;
        end

        % 托举式AGV特有的批次组合：根据负载容量将任务分组为批次
        batches = {};
        batch_weights_list = [];
        max_load_capacity = get_energy_capacity_by_agv_type(curr_agv, 1, 80);  % 默认80kg

        % 贪心批次分配：顺序遍历任务，添加到能容纳的批次中，否则开新批次
        for t = 1:length(my_tasks)
            row_idx = my_tasks(t);
            w = tasks(row_idx, 3);
            placed = false;
            for b = 1:length(batches)
                if batch_weights_list(b) + w <= max_load_capacity
                    batches{b}(end+1) = row_idx;
                    batch_weights_list(b) = batch_weights_list(b) + w;
                    placed = true;
                    break;
                end
            end
            if ~placed
                batches{end+1} = row_idx;
                batch_weights_list(end+1) = w;
            end
        end

        % 重新整理任务ID及批次信息
        real_task_ids = [];
        real_task_batches = cell(1, length(batches));
        for b = 1:length(batches)
            real_task_ids = [real_task_ids, tasks(batches{b}, 1)']; %#ok<AGROW>
            real_task_batches{b} = tasks(batches{b}, 1)';
        end
        schedules{k} = real_task_ids;
        batch_info{k} = struct(...
            'num_batches', length(batches), ...
            'task_batches', {real_task_batches}, ...
            'batch_weights', batch_weights_list ...
        );

        % 从停靠点出发，模拟执行所有批次任务，计算距离、时间、能耗
        curr_pos = depots(real_agv_id, :);
        dist_sum = 0;
        time_spent = 0;
        energy_spent = 0;
        e_base = 0.3;                % 基础能耗系数 (每单位距离)
        e_load_factor = 0.2;         % 负载附加能耗系数
        if isfield(curr_agv, 'e_base'), e_base = curr_agv.e_base; end
        if isfield(curr_agv, 'e_load_factor'), e_load_factor = curr_agv.e_load_factor; end
        speed = max(curr_agv.speed, 1e-6);   % 避免除零

        for b = 1:length(batches)
            batch = batches{b};
            current_payload = 0;     % 当前批次已装载重量

            % 1) 依次前往各任务的取货点 (pickup)
            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);
                [pick_rc, segment_dist, ~, feasible] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 1, current_payload);
                if ~feasible
                    objectives = [inf, inf, inf];
                    return;
                end
                dist_sum = dist_sum + segment_dist;
                time_spent = time_spent + segment_dist / speed;
                % 能耗 = 距离 * (基础系数 + 负载系数 * (当前载重/最大载重))
                energy_spent = energy_spent + segment_dist * (e_base + e_load_factor * (current_payload / max_load_capacity));
                curr_pos = pick_rc;
                current_payload = current_payload + tasks(batch(j), 3);
            end

            % 2) 依次前往各任务的卸货点 (dropoff)
            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);
                [drop_rc, segment_dist, ~, feasible] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'dropoff', 1, current_payload);
                if ~feasible
                    objectives = [inf, inf, inf];
                    return;
                end
                dist_sum = dist_sum + segment_dist;
                time_spent = time_spent + segment_dist / speed;
                energy_spent = energy_spent + segment_dist * (e_base + e_load_factor * (current_payload / max_load_capacity));
                curr_pos = drop_rc;
                current_payload = current_payload - tasks(batch(j), 3);
            end
        end

        agv_dists(k) = dist_sum;
        agv_times(k) = time_spent;
        agv_energy(k) = energy_spent;
    end

    % 多目标值：总距离、最大任务完成时间（makespan）、总能耗
    objectives = [sum(agv_dists), max(agv_times), sum(agv_energy)];
end


%% ==================== 叉车式AGV评估函数 ====================
function [schedules, objectives] = cost_func_fork_moo(chromosome, tasks, agv_ids, depots, agv_params, path_oracle)
% 叉车式AGV的染色体解码与多目标评估（距离、时间、能耗）
% 叉车每次只处理一个任务（取货-送货），不需要批次组合

    num_tasks = size(tasks, 1);
    num_agvs = length(agv_ids);
    task_seq = chromosome(1:num_tasks);
    agv_assign = chromosome(num_tasks+1:end);

    schedules = cell(1, num_agvs);
    agv_dists = zeros(1, num_agvs);
    agv_times = zeros(1, num_agvs);
    agv_energy = zeros(1, num_agvs);

    for k = 1:num_agvs
        real_agv_id = agv_ids(k);
        curr_agv = agv_params(real_agv_id);
        my_tasks = task_seq(agv_assign == k);

        if isempty(my_tasks)
            schedules{k} = [];
            continue;
        end

        schedules{k} = tasks(my_tasks, 1)';
        curr_pos = depots(real_agv_id, :);
        dist_sum = 0;
        time_spent = 0;
        energy_spent = 0;
        e_base = 1.0;
        e_load_factor = 0.3;
        if isfield(curr_agv, 'e_base'), e_base = curr_agv.e_base; end
        if isfield(curr_agv, 'e_load_factor'), e_load_factor = curr_agv.e_load_factor; end
        max_load_capacity = get_energy_capacity_by_agv_type(curr_agv, 2, 500);  % 叉车默认500kg
        speed = max(curr_agv.speed, 1e-6);

        for t = 1:length(my_tasks)
            row_idx = my_tasks(t);
            target_id = tasks(row_idx, 2);
            task_weight = tasks(row_idx, 3);

            % 先去取货点
            [pick_rc, d1, ~, feasible_pick] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 2, 0);
            if ~feasible_pick
                objectives = [inf, inf, inf];
                return;
            end

            % 再去卸货点（空载行驶至取货点，然后负载行驶至卸货点）
            [drop_rc, d2, ~, feasible_drop] = query_region_oracle_or_astar(path_oracle, pick_rc, target_id, 'dropoff', 2, task_weight);
            if ~feasible_drop
                objectives = [inf, inf, inf];
                return;
            end

            dist_sum = dist_sum + d1 + d2;
            % 取货段能耗基础空载，送货段能耗包含负载附加
            energy_spent = energy_spent + (d1 * e_base);
            energy_spent = energy_spent + (d2 * (e_base + e_load_factor * (task_weight / max_load_capacity)));
            time_spent = time_spent + (d1 + d2) / speed;
            curr_pos = drop_rc;
        end

        agv_dists(k) = dist_sum;
        agv_times(k) = time_spent;
        agv_energy(k) = energy_spent;
    end

    objectives = [sum(agv_dists), max(agv_times), sum(agv_energy)];
end


%% ==================== 托举式AGV的NSGA-II子算法 ====================
function [pop, pop_objs, fronts, cd, dist_hist, time_hist, energy_hist, gen_fronts_history] = run_sub_nsga2_lift(tasks, num_sub_agvs, ga_params, eval_func)
% 运行针对托举式AGV的NSGA-II多目标优化
% 输入: tasks - 任务矩阵; num_sub_agvs - AGV数量; ga_params - 算法参数
%        eval_func - 评估函数句柄
% 输出: pop - 最终种群; pop_objs - 目标值矩阵; fronts - 前沿面; cd - 拥挤距离
%        dist_hist, time_hist, energy_hist - 各代最优目标值历史
%        gen_fronts_history - 各代第一前沿全部解的目标值（元胞数组）
   
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;

    % 初始化历史记录
    dist_hist = zeros(1, max_gen);
    time_hist = zeros(1, max_gen);
    energy_hist = zeros(1, max_gen);

    % 自适应交叉/变异概率范围
    pc_max = 0.6; pc_min = 0.3;
    pm_max = 0.2; pm_min = 0.05;

    gen_fronts_history = cell(1, max_gen);

    %% 种群初始化
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);                 % 随机任务顺序
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks); % 随机AGV分配
    end

    % 评估初始种群
    pop_objs = zeros(pop_size, 3);
    for i = 1:pop_size
        [~, obj] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;
    end

    % 非支配排序与拥挤距离
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);

    %% 进化主循环
    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);

        % 构建基于rank和拥挤距离的多目标排序索引，用于自适应变异决策
        avg_rank = mean(rank);
        min_rank = min(rank);
        sort_criteria = [rank, -cd];       % 先按rank升序，再按-cd降序
        [~, sorted_moo_idx] = sortrows(sort_criteria);
        moo_ranks = zeros(pop_size, 1);
        moo_ranks(sorted_moo_idx) = 1:pop_size;   % 1为最优，pop_size为最差

        % 锦标赛选择、交叉、变异生成子代
        i = 1;
        while i <= pop_size
            p1_idx = tournament_select_nsga2(rank, cd);
            p2_idx = tournament_select_nsga2(rank, cd);
            child1 = pop(p1_idx, :);
            child2 = pop(p2_idx, :);

            rank_p1 = rank(p1_idx);
            rank_p2 = rank(p2_idx);
            better_rank = min(rank_p1, rank_p2);

            % --- 自适应交叉概率 ---
            if better_rank <= avg_rank
                pc = pc_min + (pc_max - pc_min) * (better_rank - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pc = pc_max;
            end

            % --- 自适应变异概率 ---
            if rank_p1 <= avg_rank
                pm1 = pm_min + (pm_max - pm_min) * (rank_p1 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm1 = pm_max;
            end
            if rank_p2 <= avg_rank
                pm2 = pm_min + (pm_max - pm_min) * (rank_p2 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm2 = pm_max;
            end

            % 交叉 (IPOX-MPX)
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks);
            end

            % 变异 (Fork-CPO)
            if rand < pm1
                child1 = mutate_fork_cpo(child1, num_tasks, num_sub_agvs, pm1, gen, max_gen, moo_ranks(p1_idx), pop_size);
            end
            if rand < pm2
                child2 = mutate_fork_cpo(child2, num_tasks, num_sub_agvs, pm2, gen, max_gen, moo_ranks(p2_idx), pop_size);
            end

            offspring(i, :) = child1;
            if i+1 <= pop_size
                offspring(i+1, :) = child2;
            end
            i = i + 2;
        end

        % 评估子代
        off_objs = zeros(pop_size, 3);
        for i = 1:pop_size
            [~, obj] = eval_func(offspring(i,:));
            off_objs(i,:) = obj;
        end

        % 合并父代与子代，进行精英保留选择
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);

        % 截断选择 pop_size 个个体作为新一代种群
        pop = zeros(pop_size, num_tasks * 2);
        pop_objs = zeros(pop_size, 3);
        current_idx = 1;
        f = 1;

        while current_idx <= pop_size && f <= length(c_fronts)
            front = c_fronts{f};
            if current_idx + length(front) - 1 <= pop_size
                pop(current_idx : current_idx + length(front) - 1, :) = combined_pop(front, :);
                pop_objs(current_idx : current_idx + length(front) - 1, :) = combined_objs(front, :);
                current_idx = current_idx + length(front);
            else
                [~, sort_idx] = sort(c_cd(front), 'descend');   % 拥挤距离大的优先
                num_needed = pop_size - current_idx + 1;
                selected_front = front(sort_idx(1:num_needed));
                pop(current_idx : end, :) = combined_pop(selected_front, :);
                pop_objs(current_idx : end, :) = combined_objs(selected_front, :);
                break;
            end
            f = f + 1;
        end

        % 重新计算新种群的非支配排序与拥挤距离
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);

        % 记录本代第一前沿的代表性目标值（使用TOPSIS选取妥协解）
        front1 = fronts{1};
        rep_idx = get_representative_front_index(pop_objs, front1);
        dist_hist(gen) = pop_objs(rep_idx, 1);
        time_hist(gen) = pop_objs(rep_idx, 2);
        energy_hist(gen) = pop_objs(rep_idx, 3);

        % 保存本代第一前沿所有解的目标值
        gen_fronts_history{gen} = pop_objs(front1, :);
    end
end


%% ==================== 叉车式AGV的NSGA-II子算法 ====================
function [pop, pop_objs, fronts, cd, dist_hist, time_hist, energy_hist, gen_fronts_history] = run_sub_nsga2_fork(tasks, num_sub_agvs, ga_params, eval_func)  
% 运行针对叉车式AGV的NSGA-II多目标优化
% 结构与 run_sub_nsga2_lift 类似，但交叉/变异概率范围不同

    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    
    dist_hist = zeros(1, max_gen);
    time_hist = zeros(1, max_gen); 
    energy_hist = zeros(1, max_gen); 
    
    pc_max = 0.7; pc_min = 0.4;    % 叉车交叉率范围略大
    pm_max = 0.15; pm_min = 0.05;  % 变异率上限略低
    
    gen_fronts_history = cell(1, max_gen);
    
    %% 种群初始化
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end    
    
    % 初始评估
    pop_objs = zeros(pop_size, 3); 
    for i = 1:pop_size
        [~, obj] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;
    end    
    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);
    
    %% 进化循环
    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);
        avg_rank = mean(rank);
        min_rank = min(rank); 
        sort_criteria = [rank, -cd];
        [~, sorted_moo_idx] = sortrows(sort_criteria);
        moo_ranks = zeros(pop_size, 1);
        moo_ranks(sorted_moo_idx) = 1:pop_size;
        
        i = 1;
        while i <= pop_size
            p1_idx = tournament_select_nsga2(rank, cd);
            p2_idx = tournament_select_nsga2(rank, cd);         
            child1 = pop(p1_idx, :); 
            child2 = pop(p2_idx, :);
            
            rank_p1 = rank(p1_idx);
            rank_p2 = rank(p2_idx);
            better_rank = min(rank_p1, rank_p2);             
            
            % 自适应交叉/变异概率
            if better_rank <= avg_rank
                pc = pc_min + (pc_max - pc_min) * (better_rank - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pc = pc_max;
            end
            if rank_p1 <= avg_rank
                pm1 = pm_min + (pm_max - pm_min) * (rank_p1 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm1 = pm_max;
            end
            if rank_p2 <= avg_rank
                pm2 = pm_min + (pm_max - pm_min) * (rank_p2 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm2 = pm_max;
            end
            
            % 交叉
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks); 
            end
            
            % 变异
            if rand < pm1
                child1 = mutate_fork_cpo(child1, num_tasks, num_sub_agvs, pm1, gen, max_gen, moo_ranks(p1_idx), pop_size); 
            end
            if rand < pm2
                child2 = mutate_fork_cpo(child2, num_tasks, num_sub_agvs, pm2, gen, max_gen, moo_ranks(p2_idx), pop_size); 
            end
            
            offspring(i,:) = child1;
            if i+1 <= pop_size, offspring(i+1,:) = child2; end
            i = i + 2;
        end        
        
        % 评估子代
        off_objs = zeros(pop_size, 3);
        for i = 1:pop_size
            [~, obj] = eval_func(offspring(i,:));
            off_objs(i,:) = obj;
        end
        
        % 合并与精英选择
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);
        
        pop = zeros(pop_size, num_tasks * 2);
        pop_objs = zeros(pop_size, 3);
        current_idx = 1; f = 1;
        
        while current_idx <= pop_size && f <= length(c_fronts)
            front = c_fronts{f};
            if current_idx + length(front) - 1 <= pop_size
                pop(current_idx : current_idx + length(front) - 1, :) = combined_pop(front, :);
                pop_objs(current_idx : current_idx + length(front) - 1, :) = combined_objs(front, :);
                current_idx = current_idx + length(front);
            else
                [~, sort_idx] = sort(c_cd(front), 'descend');
                num_needed = pop_size - current_idx + 1;
                selected_front = front(sort_idx(1:num_needed));
                pop(current_idx : end, :) = combined_pop(selected_front, :);
                pop_objs(current_idx : end, :) = combined_objs(selected_front, :);
                break;
            end
            f = f + 1;
        end
        
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);
        
        % 记录收敛曲线
        front1 = fronts{1};
        rep_idx = get_representative_front_index(pop_objs, front1);
        dist_hist(gen) = pop_objs(rep_idx, 1);
        time_hist(gen) = pop_objs(rep_idx, 2);
        energy_hist(gen) = pop_objs(rep_idx, 3);
        
        gen_fronts_history{gen} = pop_objs(front1, :);
    end
end


%% ==================== 拥挤距离计算 ====================
function cd = calc_crowding_distance(pop_objs, fronts)
% 计算种群中每个个体的拥挤距离，用于保持解集的多样性
    pop_size = size(pop_objs, 1);
    num_objs = size(pop_objs, 2);
    cd = zeros(pop_size, 1);

    for f = 1:length(fronts)
        front = fronts{f};
        l = length(front);
        
        if l <= 2
            cd(front) = inf;   % 前沿面极小时直接设为无穷大
            continue;
        end
        
        for m = 1:num_objs
            [sorted_objs, idx] = sort(pop_objs(front, m));
            sorted_front = front(idx);
            
            % 边界个体拥挤度设为无穷大，确保不被淘汰
            cd(sorted_front(1)) = inf;
            cd(sorted_front(end)) = inf;
            
            f_min = sorted_objs(1);
            f_max = sorted_objs(end);
            
            if f_max - f_min == 0, continue; end   % 避免除以0
            
            % 内部个体根据相邻点的目标差值计算拥挤度
            for i = 2:l-1
                cd(sorted_front(i)) = cd(sorted_front(i)) + (sorted_objs(i+1) - sorted_objs(i-1)) / (f_max - f_min);
            end
        end
    end
end


%% ==================== 锦标赛选择 ====================
function idx = tournament_select_nsga2(rank, cd)
% NSGA-II锦标赛选择：优先选取非支配等级较低的个体，等级相同时选取拥挤距离较大的个体
    pop_size = length(rank);
    i1 = randi(pop_size);
    i2 = randi(pop_size);
    
    if rank(i1) < rank(i2)
        idx = i1;
    elseif rank(i1) > rank(i2)
        idx = i2;
    else
        if cd(i1) > cd(i2)
            idx = i1;
        else
            idx = i2;
        end
    end
end


%% ==================== 快速非支配排序 ====================
function [fronts, rank] = fast_non_dominated_sorting(pop_objs)
% 对种群进行快速非支配排序，返回前沿面元胞数组和每个个体的前沿等级
    pop_size = size(pop_objs, 1);
    fronts = cell(pop_size, 1);
    domination_count = zeros(pop_size, 1);   % n_p：支配该个体的个体数量
    dominated_set = cell(pop_size, 1);       % S_p：该个体支配的个体集合
    rank = zeros(pop_size, 1);

    for i = 1:pop_size
        for j = 1:pop_size
            if i == j, continue; end
            % i 支配 j 的条件：i 所有目标都不差于 j，且至少有一个目标严格优于 j
            if all(pop_objs(i,:) <= pop_objs(j,:)) && any(pop_objs(i,:) < pop_objs(j,:))
                dominated_set{i} = [dominated_set{i}, j];
            elseif all(pop_objs(j,:) <= pop_objs(i,:)) && any(pop_objs(j,:) < pop_objs(i,:))
                domination_count(i) = domination_count(i) + 1;
            end
        end
        % 不被任何人支配的个体属于第一前沿
        if domination_count(i) == 0
            rank(i) = 1;
            fronts{1} = [fronts{1}, i];
        end
    end

    % 逐层构建后续前沿面
    current_front = 1;
    while ~isempty(fronts{current_front})
        next_front = [];
        for i = fronts{current_front}
            for j = dominated_set{i}
                domination_count(j) = domination_count(j) - 1;
                if domination_count(j) == 0
                    rank(j) = current_front + 1;
                    next_front = [next_front, j];
                end
            end
        end
        current_front = current_front + 1;
        fronts{current_front} = next_front;
    end
    fronts(cellfun(@isempty, fronts)) = [];   % 清除空的前沿面
end


%% ==================== TOPSIS妥协解选择 ====================
function idx = select_compromise_index(front_objs)
% 使用TOPSIS方法从Pareto前沿中选取最接近理想解的妥协解索引
    if isempty(front_objs)
        idx = 1;
        return;
    end

    min_objs = min(front_objs, [], 1);
    max_objs = max(front_objs, [], 1);
    obj_norm = (front_objs - min_objs) ./ (max_objs - min_objs + 1e-9);
    ideal_best = min(obj_norm, [], 1);
    ideal_worst = max(obj_norm, [], 1);
    d_best = sqrt(sum((obj_norm - ideal_best).^2, 2));
    d_worst = sqrt(sum((obj_norm - ideal_worst).^2, 2));
    closeness = d_worst ./ (d_best + d_worst + 1e-9);   % 相对接近度
    [~, idx] = max(closeness);
end


%% ==================== 代表性前沿个体选择 ====================
function rep_idx = get_representative_front_index(pop_objs, front_idx)
% 从指定前沿中选取TOPSIS妥协解对应的原种群索引
    if isempty(front_idx)
        rep_idx = 1;
        return;
    end
    best_idx_in_front = select_compromise_index(pop_objs(front_idx, :));
    rep_idx = front_idx(best_idx_in_front);
end


%% ==================== 获取AGV最大载重容量 ====================
function capacity = get_energy_capacity_by_agv_type(curr_agv, agv_type, default_capacity)
% 根据AGV类型和参数结构体获取最大负载容量
% 优先使用结构体中的字段，否则使用默认值
    if nargin < 3 || isempty(default_capacity)
        if agv_type == 1
            default_capacity = 80;     % 托举式默认80
        else
            default_capacity = 500;    % 叉车式默认500
        end
    end

    capacity = default_capacity;
    if isempty(curr_agv) || ~isstruct(curr_agv)
        return;
    end

    if isfield(curr_agv, 'max_load_capacity') && ~isempty(curr_agv.max_load_capacity) && ...
            isfinite(curr_agv.max_load_capacity) && curr_agv.max_load_capacity > 0
        capacity = curr_agv.max_load_capacity;
        return;
    end

    if isfield(curr_agv, 'load_capacity') && ~isempty(curr_agv.load_capacity) && ...
            isfinite(curr_agv.load_capacity) && curr_agv.load_capacity > 0
        capacity = curr_agv.load_capacity;
    end
end


%% ==================== 路径查询与A*后备 ====================
function [best_rc, best_dist, best_cost, feasible] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, phase, agv_type, payload_weight)
% 先尝试通过区域距离Oracle获取候选区域坐标和最优路径，
% 若失败则回退到A*搜索
    best_rc = [];
    best_dist = inf;
    best_cost = inf;
    feasible = false;

    if nargin >= 1 && ~isempty(path_oracle)
        try
            [best_rc, best_dist, best_cost, feasible] = ...
                region_distance_oracle('query', path_oracle, curr_pos, target_id, phase, agv_type);
        catch
            feasible = false;
        end
    end

    if feasible
        return;
    end

    % Oracle失败时调用A*计算
    [best_rc, best_dist, best_cost, feasible] = ...
        get_best_astar_segment(curr_pos, target_id, phase, agv_type, payload_weight);
end


function [best_rc, best_dist, best_cost, feasible] = get_best_astar_segment(curr_pos, target_id, phase, agv_type, payload_weight)
% 使用A*算法在候选区域中寻找最优路径段（带缓存机制）
    persistent segment_cache planning_map_cache;
    if isempty(segment_cache)
        segment_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end
    if isempty(planning_map_cache)
        planning_map_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    payload_key = sprintf('%.3f', payload_weight);
    cache_key = sprintf('%d|%d|%s|%d|%d|%s', agv_type, target_id, phase, curr_pos(1), curr_pos(2), payload_key);
    if isKey(segment_cache, cache_key)      % 命中缓存直接返回
        cached = segment_cache(cache_key);
        best_rc = cached.best_rc;
        best_dist = cached.best_dist;
        best_cost = cached.best_cost;
        feasible = cached.feasible;
        return;
    end

    % 获取AGV类型对应的代价地图
    [cost_map, map_rows, map_cols] = get_ga_costmap(agv_type);
    map_key = sprintf('%d', target_id);
    if isKey(planning_map_cache, map_key)
        planning_map = planning_map_cache(map_key);
    else
        planning_map = create_binary_grid_map(map_cols - 1, map_rows - 1, target_id);
        planning_map_cache(map_key) = planning_map;
    end

    % 获取取货/卸货区域的候选栅格坐标
    candidates = get_ga_target_candidates(target_id, phase);
    best_rc = [];
    best_dist = inf;
    best_cost = inf;
    feasible = false;

    for i = 1:size(candidates, 1)
        candidate = candidates(i, :);
        % 跳过越界或障碍物栅格
        if candidate(1) < 1 || candidate(1) > map_rows || candidate(2) < 1 || candidate(2) > map_cols
            continue;
        end
        if planning_map(candidate(1), candidate(2)) == 1
            continue;
        end

        eval_map = planning_map;
        eval_map(curr_pos(1), curr_pos(2)) = 0;   % 确保起点可行走
        [path, g_cost, ~, ~, path_length] = astar_planner_turn3(eval_map, curr_pos, candidate, payload_weight, cost_map);
        if isempty(path) || ~isfinite(g_cost)
            continue;
        end

        segment_dist = max(path_length - 1, 0);
        % 选择代价最小，若相同再比较距离
        if (g_cost < best_cost - 1e-9) || ...
           (abs(g_cost - best_cost) <= 1e-9 && segment_dist < best_dist) || ...
           (abs(g_cost - best_cost) <= 1e-9 && abs(segment_dist - best_dist) <= 1e-9 && isempty(best_rc))
            best_rc = candidate;
            best_dist = segment_dist;
            best_cost = g_cost;
            feasible = true;
        end
    end

    % 写入缓存
    segment_cache(cache_key) = struct('best_rc', best_rc, 'best_dist', best_dist, 'best_cost', best_cost, 'feasible', feasible);
end


function candidates = get_ga_target_candidates(target_id, phase)
% 根据目标区域ID和阶段（取货/卸货）获取区域内所有候选栅格坐标
    [pickup_anchor, dropoff_anchor, pickup_size, dropoff_size] = get_task_coordinates(target_id);
    if strcmpi(phase, 'pickup')
        anchor = pickup_anchor;
        area_size = pickup_size;
    else
        anchor = dropoff_anchor;
        area_size = dropoff_size;
    end

    rows = anchor(1):(anchor(1) + area_size(1) - 1);
    cols = anchor(2):(anchor(2) + area_size(2) - 1);
    [grid_cols, grid_rows] = meshgrid(cols, rows);
    candidates = [grid_rows(:), grid_cols(:)];
end


function [cost_map, map_rows, map_cols] = get_ga_costmap(agv_type)
% 获取对应AGV类型的全局代价地图（用于A*路径规划）
    global costmap_type1 costmap_type2;
    if isempty(costmap_type1) || isempty(costmap_type2)
        init_global_costmaps();      % 初始化全局代价地图
    end

    if agv_type == 1
        cost_map = costmap_type1;
    else
        cost_map = costmap_type2;
    end

    [map_rows, map_cols] = size(cost_map);
end


%% ==================== 自适应变异算子 (Fork-CPO) ====================
function child = mutate_fork_cpo(chrom, num_tasks, num_agvs, pm, g, G, parent_rank_idx, PN)
% 多策略自适应变异算子，根据父代排名和进化代数动态选择变异策略
% 输入:
%   chrom - 父代染色体 [1, 2*num_tasks]
%   pm    - 基础变异概率 (用于最后的强制负载均衡)
%   g, G  - 当前代数和最大代数
%   parent_rank_idx - 父代在多目标排序中的排名 (1=最优)
%   PN - 种群大小
% 输出: 变异后的子代染色体

    child = chrom;
    if num_tasks < 2
        return;
    end

    tau1 = rand();
    tau2 = rand();
    tau1_prime = tau1 - 0.3 * (1 - g/G);   % 随时间衰减的阈值

    if tau1_prime < tau2
        % ==================== 探索策略 (增加多样性) ====================
        if parent_rank_idx > 0.6 * PN
            % 1. 视觉防御：基因块翻转 (适用于排名靠后的个体)
            range = sort(randperm(num_tasks, 2));
            child(range(1):range(2)) = fliplr(child(range(1):range(2))); % 反转任务顺序
        else
            % 2. 声音防御：跨车交换 (交换两个任务的AGV指派)
            pos = randperm(num_tasks, 2);
            agv_pos = pos + num_tasks;
            ta = child(agv_pos(1));
            child(agv_pos(1)) = child(agv_pos(2));
            child(agv_pos(2)) = ta;
        end
    else
        % ==================== 开发策略 (局部精调) ====================
        if parent_rank_idx > 0.2 * PN
            % 3. 气味防御：插入变异 (移除一个任务并插入到新位置)
            pts = randperm(num_tasks, 2);
            extract_idx = pts(1);
            insert_idx = pts(2);
            extracted_task = child(extract_idx);
            extracted_agv = child(extract_idx + num_tasks);

            % 删除该任务及对应的AGV指派
            child(extract_idx) = [];
            child(extract_idx + num_tasks - 1) = [];

            % 重新插入到指定位置
            child = [child(1:insert_idx-1), extracted_task, child(insert_idx:num_tasks-1), ...
                     child(num_tasks:num_tasks+insert_idx-2), extracted_agv, child(num_tasks+insert_idx-1:end)];
        else
            % 4. 物理攻击：瓶颈定向转移 (将高负载AGV的一个任务转移给低负载AGV)
            agv_idx = (num_tasks + 1) : (2 * num_tasks);
            current_agvs = child(agv_idx);
            counts = histcounts(current_agvs, 1:num_agvs+1);
            [~, max_agv] = max(counts);
            [~, min_agv] = min(counts);
            heavy_tasks_idx = find(current_agvs == max_agv);
            if ~isempty(heavy_tasks_idx)
                transfer_idx = heavy_tasks_idx(randi(length(heavy_tasks_idx)));
                child(num_tasks + transfer_idx) = min_agv;
            end
        end
    end

    % ==================== 强制负载均衡 (安全网) ====================
    if rand < (pm + 0.05)
        agv_idx = (num_tasks + 1) : (2 * num_tasks);
        current_agvs = child(agv_idx);
        counts = zeros(1, num_agvs);
        for k = 1:num_agvs
            counts(k) = sum(current_agvs == k);
        end
        min_val = min(counts);
        candidates = find(counts == min_val);
        mutate_pos = randperm(num_tasks, 2);
        for p = 1:2
            child(num_tasks + mutate_pos(p)) = candidates(randi(length(candidates)));
        end
    end
end


%% ==================== 交叉算子 (IPOX-MPX) ====================
function [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks)
% 基于IPOX (改进的优先操作交叉) 和 MPX (多点混合) 的混合交叉算子
% 用于任务顺序和AGV分配的联合交叉
    if num_tasks < 2
        child1 = p1;
        child2 = p2;
        return;
    end

    child1 = zeros(1, num_tasks * 2);
    child2 = zeros(1, num_tasks * 2);

    seq1 = p1(1:num_tasks);         % 父代1任务顺序
    seq2 = p2(1:num_tasks);         % 父代2任务顺序
    agv1 = p1(num_tasks+1:end);     % 父代1 AGV分配
    agv2 = p2(num_tasks+1:end);     % 父代2 AGV分配

    % 随机选择两个交叉点
    points = sort(randperm(num_tasks, 2));
    pt1 = points(1);
    pt2 = points(2);
    
    c1_seq = zeros(1, num_tasks);
    c2_seq = zeros(1, num_tasks);

    % 保留父代交叉段内的任务顺序
    c1_seq(pt1:pt2) = seq1(pt1:pt2);
    c2_seq(pt1:pt2) = seq2(pt1:pt2);

    empty_idx = [1:pt1-1, pt2+1:num_tasks];
    
    % 父代2中未在c1_seq交叉段出现的任务按原序填入c1_seq的空位，反之亦然
    rem_seq2 = seq2(~ismember(seq2, c1_seq(pt1:pt2)));
    rem_seq1 = seq1(~ismember(seq1, c2_seq(pt1:pt2)));
    
    c1_seq(empty_idx) = rem_seq2;
    c2_seq(empty_idx) = rem_seq1;

    % 随机生成混合掩码，用于AGV分配的交叉
    M = randi([0, 1], 1, num_tasks);
    
    c1_agv = zeros(1, num_tasks);
    c2_agv = zeros(1, num_tasks);

    c1_agv(M == 0) = agv1(M == 0);   % 掩码0位置继承父1
    c2_agv(M == 0) = agv2(M == 0);   % 掩码0位置继承父2
    c1_agv(M == 1) = agv2(M == 1);   % 掩码1位置交叉
    c2_agv(M == 1) = agv1(M == 1);

    child1 = [c1_seq, c1_agv];
    child2 = [c2_seq, c2_agv];
end