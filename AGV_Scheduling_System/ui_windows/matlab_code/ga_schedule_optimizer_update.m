function [best_schedule, batch_details, metrics, history, pareto_fronts] = ga_schedule_optimizer_update(task_list, num_agvs, depots, agv_params, ga_params, agv_types)

    oracle_options = struct();
    oracle_options.task_target_ids = unique(task_list(:, 2))';
    oracle_options.agv_types = unique(agv_types)';
    path_oracle = region_distance_oracle('build', oracle_options);
    report_parallel_evaluation_status();

    idx_lift_tasks = task_list(:,2) <= 12;
    idx_fork_tasks = task_list(:,2) > 12;
    
    tasks_lift = task_list(idx_lift_tasks, :);
    tasks_fork = task_list(idx_fork_tasks, :);
    
    agvs_lift = find(agv_types == 1); 
    agvs_fork = find(agv_types == 2); 
    
    best_schedule = cell(1, num_agvs);
    batch_details = cell(1, num_agvs); 
    
    dist_lift = 0; time_lift = 0; energy_lift = 0;
    dist_fork = 0; time_fork = 0; energy_fork = 0;
    
    hist_lift_dist = zeros(1, ga_params.max_gen);
    hist_lift_time = zeros(1, ga_params.max_gen);
    hist_lift_energy = zeros(1, ga_params.max_gen);
    
    hist_fork_dist = zeros(1, ga_params.max_gen);
    hist_fork_time = zeros(1, ga_params.max_gen);
    hist_fork_energy = zeros(1, ga_params.max_gen);

    gen_fronts_lift = {};  
    gen_fronts_fork = {};
    pareto_fronts = struct('lift', [], 'fork', []);

    %% 托举式AGV相关操作       
    if ~isempty(tasks_lift) && ~isempty(agvs_lift)
        disp('   -> 启动 NSGA-II 引擎优化托举车（多目标：距离、时间、能耗）...');
        
        eval_lift_moo = @(chrom) cost_func_lift_moo(chrom, tasks_lift, agvs_lift, depots, agv_params, path_oracle);
        
        [pop_lift, objs_lift, fronts_lift, ~, hist_lift_dist, hist_lift_time, hist_lift_energy,gen_fronts_lift] = run_sub_nsga2_lift(tasks_lift, length(agvs_lift), ga_params, eval_lift_moo);
        
        front1_idx = fronts_lift{1}; 
        front1_objs = objs_lift(front1_idx, :);
        
        % TOPSIS 折中解选择策略
        best_idx_in_front1 = select_compromise_index(front1_objs);
        best_lift_chrom = pop_lift(front1_idx(best_idx_in_front1), :);
        
        [sched_lift, best_objs_lift, batch_info_lift] = eval_lift_moo(best_lift_chrom);
        dist_lift = best_objs_lift(1);          
        time_lift = best_objs_lift(2);          
        energy_lift = best_objs_lift(3);        
        
        for i = 1:length(agvs_lift)
            best_schedule{agvs_lift(i)} = sched_lift{i};
            batch_details{agvs_lift(i)} = batch_info_lift{i}; 
        end
    end 
    %% 叉车式AGV相关操作   
    % --- 2. 叉车：升级为三维目标（距离、时间、能耗） ---
    if ~isempty(tasks_fork) && ~isempty(agvs_fork)
        disp('   -> 启动 NSGA-II 引擎优化叉车（多目标：距离、时间、能耗）...');
        eval_fork_moo = @(chrom) cost_func_fork_moo(chrom, tasks_fork, agvs_fork, depots, agv_params, path_oracle);
        
        % 接收新增的能耗历史输出
        [pop_fork, objs_fork, fronts_fork, ~, hist_fork_dist, hist_fork_time, hist_fork_energy,gen_fronts_fork] = run_sub_nsga2_fork(tasks_fork, length(agvs_fork), ga_params, eval_fork_moo);
        
        % TOPSIS 折中解选择策略
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
    %% === 统一打包输出：结构体封装 ===
    % 1. 打包最终稳态指标（Metrics）
    metrics.lift.dist = dist_lift;       
    metrics.lift.time = time_lift;       
    metrics.lift.energy = energy_lift;   
    
    metrics.fork.dist = dist_fork;       
    metrics.fork.time = time_fork;       
    metrics.fork.energy = energy_fork;   
    
    % 2. 打包算法迭代历史曲线 (History)
    history.lift.dist = hist_lift_dist;
    history.lift.time = hist_lift_time;
    history.lift.energy = hist_lift_energy;
    history.lift.gen_fronts = gen_fronts_lift;
    
    
    history.fork.dist = hist_fork_dist;
    history.fork.time = hist_fork_time;
    history.fork.energy = hist_fork_energy;
    history.fork.gen_fronts = gen_fronts_fork;

    if ~isempty(tasks_lift) && ~isempty(agvs_lift) && exist('objs_lift', 'var') && exist('fronts_lift', 'var') && ~isempty(fronts_lift)
        pareto_fronts.lift = objs_lift(fronts_lift{1}, :);
    end
    if ~isempty(tasks_fork) && ~isempty(agvs_fork) && exist('objs_fork', 'var') && exist('fronts_fork', 'var') && ~isempty(fronts_fork)
        pareto_fronts.fork = objs_fork(fronts_fork{1}, :);
    end
 end 
%% 托举式AGV相关函数
function [pop, pop_objs, fronts, cd, dist_hist, time_hist, energy_hist, gen_fronts_history] = run_sub_nsga2_lift(tasks, num_sub_agvs, ga_params, eval_func)
% =========================================================================
% 注释已修复
% 注释已修复
%   tasks          - 任务矩阵，每一行代表一个任务的信息
% 注释已修复
%   ga_params          - 遗传算法参数结构体，包含种群规模与最大迭代代数
%   eval_func          - 个体评估函数，返回 [~, obj]，其中 obj=[距离, 时间, 能耗]
% 注释已修复
%   pop                - 最终种群，大小为 pop_size × (2*任务数)
% 注释已修复
% 注释已修复
%   cd                 - 最终种群的拥挤距离向量
% 注释已修复
%   time_hist       - 每代Pareto前沿中最小时间的历史记录
%   energy_hist     - 每代Pareto前沿中最小能量的历史记录
%   gen_fronts_history - 保存每代第一前沿全部目标值的元胞数组
% =========================================================================
   
    % 获取任务数量（即任务矩阵的行数）
    num_tasks = size(tasks, 1);
    % 从ga_params结构体中提取种群大小
    pop_size = ga_params.pop_size;
    % 注释已修复
    max_gen = ga_params.max_gen;

    % 初始化历史记录数组：距离、时间、能耗
    dist_hist = zeros(1, max_gen);
    time_hist = zeros(1, max_gen);
    energy_hist = zeros(1, max_gen);

    % 交叉概率自适应范围：pc_max=0.6，pc_min=0.3
    pc_max = 0.6; pc_min = 0.3;
    % 变异概率自适应范围：pm_max=0.2，pm_min=0.05
    pm_max = 0.2; pm_min = 0.05;

    % 预分配内存，用于存储每一代第一前沿的所有个体的目标值，提升运行速度
    gen_fronts_history = cell(1, max_gen);

    %% 注释已修复
    % 注释已修复
    % 注释已修复
    %   前 num_tasks 个基因：任务访问顺序（1..num_tasks 的排列）
    %   后 num_tasks 个基因：任务分配的 AGV 编号（1..num_sub_agvs）
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        % 注释已修复
        pop(i, 1:num_tasks) = randperm(num_tasks);
        % 注释已修复
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end

    %% 1.2 - 初始化评估（计算初始种群的目标值）
    % 注释已修复
    pop_objs = evaluate_population_parallel(pop, eval_func);


    % 对初始种群执行快速非支配排序
    % 注释已修复
    %   rank - 个体所属前沿编号，数值越小表示越优
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    % 注释已修复
    cd = calc_crowding_distance(pop_objs, fronts);

    %% 主循环：进化迭代
    for gen = 1:max_gen
        % 初始化子代种群矩阵（大小与父代相同）
        offspring = zeros(pop_size, num_tasks * 2);

        % 注释已修复
        avg_rank = mean(rank);
        min_rank = min(rank);

        % 注释已修复
        sort_criteria = [rank, -cd];
        % 注释已修复
        [~, sorted_moo_idx] = sortrows(sort_criteria);

        % 初始化多目标排序索引
        moo_ranks = zeros(pop_size, 1);
        % 注释已修复
        moo_ranks(sorted_moo_idx) = 1:pop_size;

        % 注释已修复
        i = 1;   % 子代写入位置
        while i <= pop_size
            % 注释已修复
            p1_idx = tournament_select_nsga2(rank, cd);
            % 注释已修复
            p2_idx = tournament_select_nsga2(rank, cd);
            % 先复制父代个体，后续再依据交叉和变异进行修改
            child1 = pop(p1_idx, :);
            child2 = pop(p2_idx, :);

            % 注释已修复
            rank_p1 = rank(p1_idx);
            rank_p2 = rank(p2_idx);
            % 注释已修复
            better_rank = min(rank_p1, rank_p2);

            % 注释已修复
            % 自适应交叉概率：优良个体降低扰动，较差个体增强探索
            % 注释已修复
            if better_rank <= avg_rank
                pc = pc_min + (pc_max - pc_min) * (better_rank - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                % 较差个体使用较大的交叉概率，增强全局搜索能力
                pc = pc_max;
            end

            % --- 自适应变异概率（分别针对两个父代） ---
            % 注释已修复
            if rank_p1 <= avg_rank
                pm1 = pm_min + (pm_max - pm_min) * (rank_p1 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm1 = pm_max;
            end
            % 注释已修复
            if rank_p2 <= avg_rank
                pm2 = pm_min + (pm_max - pm_min) * (rank_p2 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm2 = pm_max;
            end

            % --- 交叉操作 ---
            % 注释已修复
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks);
            end
            % 注释已修复

            % --- 变异操作 ---
            % 根据个体质量选择不同的变异策略
            % 对优秀个体执行局部精细搜索，对一般个体执行更强扰动
            if rand < pm1
                child1 = mutate_fork_cpo(child1, num_tasks, num_sub_agvs, pm1, gen, max_gen, moo_ranks(p1_idx), pop_size);
            end
            % 初始化子代种群写入位置
            if rand < pm2
                child2 = mutate_fork_cpo(child2, num_tasks, num_sub_agvs, pm2, gen, max_gen, moo_ranks(p2_idx), pop_size);
            end

            % 构造临时子代种群 offspring
            offspring(i, :) = child1;
            % 注释已修复
            if i+1 <= pop_size
                offspring(i+1, :) = child2;
            end
            % 父代与子代合并后的临时种群
            i = i + 2;
        end

        % --- 评估子代种群的目标值 ---
        off_objs = evaluate_population_parallel(offspring, eval_func);


        % --- 合并父代与子代，形成 2*pop_size 的临时种群 ---
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];

        % 重新进行非支配排序并更新拥挤距离
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        % 注释已修复
        c_cd = calc_crowding_distance(combined_objs, c_fronts);

        % --- 精英保留：按前沿顺序依次填充新种群 ---
        % combined_pop 与 combined_objs 为父代和子代的合并结果
        pop = zeros(pop_size, num_tasks * 2);
        pop_objs = zeros(pop_size, 3);
        current_idx = 1;      % 当前已写入的新种群位置
        f = 1;                 % 前沿索引

        % 按照前沿等级从低到高依次选择个体，直到填满新种群
        while current_idx <= pop_size && f <= length(c_fronts)
            front = c_fronts{f};
            % 若整个前沿都可以保留，则整层写入新种群
            if current_idx + length(front) - 1 <= pop_size
                % 注释已修复
                pop(current_idx : current_idx + length(front) - 1, :) = combined_pop(front, :);
                pop_objs(current_idx : current_idx + length(front) - 1, :) = combined_objs(front, :);
                current_idx = current_idx + length(front);
            else
                % 如果当前前沿只能部分加入，则根据拥挤距离降序排序，选择距离最大的个体填充剩余位置
                [~, sort_idx] = sort(c_cd(front), 'descend');
                % 只补足当前仍然需要的个体数量
                selected_front = front(sort_idx(1:num_needed));

                % 按拥挤距离降序截取当前前沿中的个体
                pop(current_idx : end, :) = combined_pop(selected_front, :);
                pop_objs(current_idx : end, :) = combined_objs(selected_front, :);
                break;   % 新种群已填满，结束当前代构造
            end
            f = f + 1;   % 转入下一前沿
        end

        % 注释已修复
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);

        % --- 记录当前代的代表解与第一前沿全部目标值 ---
        front1 = fronts{1};
        rep_idx = get_representative_front_index(pop_objs, front1);
        dist_hist(gen) = pop_objs(rep_idx, 1);
        time_hist(gen) = pop_objs(rep_idx, 2);
        energy_hist(gen) = pop_objs(rep_idx, 3);

        % 保存本代第一前沿全部目标值（N×3 矩阵）
        gen_fronts_history{gen} = pop_objs(front1, :);
    end
    % 注释已修复

% 函数结束
end

function [schedules, objectives, batch_info] = cost_func_lift_moo(chromosome, tasks, agv_ids, depots, agv_params, path_oracle)
    num_tasks = size(tasks, 1);
    num_agvs = length(agv_ids);
    task_seq = chromosome(1:num_tasks);
    agv_assign = chromosome(num_tasks+1:end);

    schedules = cell(1, num_agvs);
    batch_info = cell(1, num_agvs);
    agv_dists = zeros(1, num_agvs);
    agv_times = zeros(1, num_agvs);
    agv_energy = zeros(1, num_agvs);

    for k = 1:num_agvs
        real_agv_id = agv_ids(k);
        curr_agv = agv_params(real_agv_id);
        my_tasks = task_seq(agv_assign == k);
        real_task_ids = tasks(my_tasks, 1)';
        schedules{k} = real_task_ids;

        if isempty(my_tasks)
            schedules{k} = [];
            continue;
        end

        batches = {};
        batch_weights_list = [];
        max_load_capacity = get_energy_capacity_by_agv_type(curr_agv, 1, 80);
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

        curr_pos = depots(real_agv_id, :);
        dist_sum = 0;
        time_spent = 0;
        energy_spent = 0;
        e_base = 0.3;
        e_load_factor = 0.2;
        if isfield(curr_agv, 'e_base'), e_base = curr_agv.e_base; end
        if isfield(curr_agv, 'e_load_factor'), e_load_factor = curr_agv.e_load_factor; end
        speed = max(curr_agv.speed, 1e-6);

        for b = 1:length(batches)
            batch = batches{b};
            current_payload = 0;

            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);
                [pick_rc, segment_dist, ~, feasible] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 1, current_payload);
                if ~feasible
                    objectives = [inf, inf, inf];
                    return;
                end
                dist_sum = dist_sum + segment_dist;
                time_spent = time_spent + segment_dist / speed;
                energy_spent = energy_spent + segment_dist * (e_base + e_load_factor * (current_payload / max_load_capacity));
                curr_pos = pick_rc;
                current_payload = current_payload + tasks(batch(j), 3);
            end

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

    objectives = [sum(agv_dists), max(agv_times), sum(agv_energy)];
end

function [schedules, objectives] = cost_func_fork_moo(chromosome, tasks, agv_ids, depots, agv_params, path_oracle)
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
        max_load_capacity = get_energy_capacity_by_agv_type(curr_agv, 2, 500);
        speed = max(curr_agv.speed, 1e-6);

        for t = 1:length(my_tasks)
            row_idx = my_tasks(t);
            target_id = tasks(row_idx, 2);
            task_weight = tasks(row_idx, 3);

            [pick_rc, d1, ~, feasible_pick] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 2, 0);
            if ~feasible_pick
                objectives = [inf, inf, inf];
                return;
            end

            [drop_rc, d2, ~, feasible_drop] = query_region_oracle_or_astar(path_oracle, pick_rc, target_id, 'dropoff', 2, task_weight);
            if ~feasible_drop
                objectives = [inf, inf, inf];
                return;
            end

            dist_sum = dist_sum + d1 + d2;
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

function [pop, pop_objs, fronts, cd, dist_hist, time_hist, energy_hist,gen_fronts_history] = run_sub_nsga2_fork(tasks, num_sub_agvs, ga_params, eval_func)  
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    
    dist_hist = zeros(1, max_gen);
    time_hist = zeros(1, max_gen); 
    energy_hist = zeros(1, max_gen); 
    
    pc_max = 0.7; pc_min = 0.4;  
    pm_max = 0.15; pm_min = 0.05; 
    % 【新增】：预分配内存，提升运行速度
    gen_fronts_history = cell(1, max_gen);
    %% 注释已修复
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end    
    
    %% 初始评估（三维目标）
    pop_objs = evaluate_population_parallel(pop, eval_func);

    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);
    
    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);
        avg_rank = mean(rank);
        min_rank = min(rank); 
        % 注释已修复
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
            
            % 閼奉亪鈧倸绨插鍌滃芳
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
            
            % 交叉：使用 IPOX_MPX 算子
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks); 
            end
            
            % 变异：基于 CPO 思想的自适应变异
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
        
        % 评估子代（三维目标）
        off_objs = evaluate_population_parallel(offspring, eval_func);

        
        % 合并并执行非支配排序
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);
        
        % 精英保留（三维目标）
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
        
        % 注释已修复
        front1 = fronts{1};
        rep_idx = get_representative_front_index(pop_objs, front1);
        dist_hist(gen) = pop_objs(rep_idx, 1);
        time_hist(gen) = pop_objs(rep_idx, 2);
        energy_hist(gen) = pop_objs(rep_idx, 3);
        % 保存本代第一前沿全部目标值（N×3）
        gen_fronts_history{gen} = pop_objs(front1, :);
    end
end

%% 公共函数
function cd = calc_crowding_distance(pop_objs, fronts)
    pop_size = size(pop_objs, 1);
    num_objs = size(pop_objs, 2);
    cd = zeros(pop_size, 1);

    for f = 1:length(fronts)
        front = fronts{f};
        l = length(front);
        
        % 随机选择 1 或 2 个任务进行交换
        if l <= 2
            cd(front) = inf;
            continue;
        end
        
        % 对每一个目标维度独立计算距离并累加
        for m = 1:num_objs
            [sorted_objs, idx] = sort(pop_objs(front, m));
            sorted_front = front(idx);
            
            % 注释已修复
            cd(sorted_front(1)) = inf;
            cd(sorted_front(end)) = inf;
            
            f_min = sorted_objs(1);
            f_max = sorted_objs(end);
            
            if f_max - f_min == 0, continue; end
            
            % 内部个体根据相邻个体的目标差值计算拥挤度
            for i = 2:l-1
                cd(sorted_front(i)) = cd(sorted_front(i)) + (sorted_objs(i+1) - sorted_objs(i-1)) / (f_max - f_min);
            end
        end
    end
end

function idx = tournament_select_nsga2(rank, cd)
    pop_size = length(rank);
    i1 = randi(pop_size);
    i2 = randi(pop_size);
    
    % 第一阶段：偏向全局探索
    if rank(i1) < rank(i2)
        idx = i1;
    elseif rank(i1) > rank(i2)
        idx = i2;
    else
    % 第二阶段：偏向局部开发
        if cd(i1) > cd(i2)
            idx = i1;
        else
            idx = i2;
        end
    end
end

function [fronts, rank] = fast_non_dominated_sorting(pop_objs)
    pop_size = size(pop_objs, 1);
    fronts = cell(pop_size, 1);
    domination_count = zeros(pop_size, 1); % 鐠佹澘缍嶇悮顐㈩樋鐏忔垳姹夐弨顖炲帳 (n_p)
    dominated_set = cell(pop_size, 1);     % 鐠佹澘缍嶉弨顖炲帳娴滃棗鎽㈡禍娑楁眽 (S_p)
    rank = zeros(pop_size, 1);

    for i = 1:pop_size
        for j = 1:pop_size
            if i == j, continue; end
            % 若个体 i 支配个体 j，则记录支配关系
            if all(pop_objs(i,:) <= pop_objs(j,:)) && any(pop_objs(i,:) < pop_objs(j,:))
                dominated_set{i} = [dominated_set{i}, j];
            elseif all(pop_objs(j,:) <= pop_objs(i,:)) && any(pop_objs(j,:) < pop_objs(i,:))
                domination_count(i) = domination_count(i) + 1;
            end
        end
        % 提取第一前沿（Rank 1）
        if domination_count(i) == 0
            rank(i) = 1;
            fronts{1} = [fronts{1}, i];
        end
    end

    % 注释已修复
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
    fronts(cellfun(@isempty, fronts)) = []; % 删除空前沿
end

function idx = select_compromise_index(front_objs)
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
    closeness = d_worst ./ (d_best + d_worst + 1e-9);
    [~, idx] = max(closeness);
end

function rep_idx = get_representative_front_index(pop_objs, front_idx)
    if isempty(front_idx)
        rep_idx = 1;
        return;
    end
    best_idx_in_front = select_compromise_index(pop_objs(front_idx, :));
    rep_idx = front_idx(best_idx_in_front);
end

function capacity = get_energy_capacity_by_agv_type(curr_agv, agv_type, default_capacity)
    if nargin < 3 || isempty(default_capacity)
        if agv_type == 1
            default_capacity = 80;
        else
            default_capacity = 500;
        end
    end

    capacity = default_capacity;
    if isempty(curr_agv) || ~isstruct(curr_agv)
        return;
    end

    if isfield(curr_agv, 'max_load_capacity') && ~isempty(curr_agv.max_load_capacity) && isfinite(curr_agv.max_load_capacity) && curr_agv.max_load_capacity > 0
        capacity = curr_agv.max_load_capacity;
        return;
    end

    if isfield(curr_agv, 'load_capacity') && ~isempty(curr_agv.load_capacity) && isfinite(curr_agv.load_capacity) && curr_agv.load_capacity > 0
        capacity = curr_agv.load_capacity;
    end
end

function [best_rc, best_dist, best_cost, feasible] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, phase, agv_type, payload_weight)
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

    [best_rc, best_dist, best_cost, feasible] = ...
        get_best_astar_segment(curr_pos, target_id, phase, agv_type, payload_weight);
end

function pop_objs = evaluate_population_parallel(population, eval_func)
    num_individuals = size(population, 1);
    pop_objs = zeros(num_individuals, 3);

    if use_parallel_evaluation_local()
        parfor idx = 1:num_individuals
            [~, obj] = eval_func(population(idx, :));
            pop_objs(idx, :) = obj;
        end
    else
        for idx = 1:num_individuals
            [~, obj] = eval_func(population(idx, :));
            pop_objs(idx, :) = obj;
        end
    end
end

function report_parallel_evaluation_status()
    persistent status_reported;

    if isempty(status_reported)
        status_reported = false;
    end

    if status_reported
        return;
    end

    [is_parallel, status_msg] = use_parallel_evaluation_local(true);
    if is_parallel
        fprintf('[并行评估] 已启用 parfor: %s\n', status_msg);
    else
        fprintf('[并行评估] 当前使用串行 for: %s\n', status_msg);
    end

    status_reported = true;
end

function [tf, status_msg] = use_parallel_evaluation_local(force_refresh)
    persistent parallel_ready parallel_enabled parallel_status_msg;

    if nargin < 1
        force_refresh = false;
    end

    if isempty(parallel_ready) || force_refresh
        parallel_ready = true;
        parallel_enabled = false;
        parallel_status_msg = '未检测到 Parallel Computing Toolbox';

        has_toolbox = license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
        if has_toolbox
            try
                pool = gcp('nocreate');
                if isempty(pool)
                    try
                        parpool('Processes');
                        parallel_status_msg = '已创建进程并行池';
                    catch ME_process
                        try
                            parpool();
                            parallel_status_msg = sprintf('进程并行池启动失败，已回退并创建默认并行池: %s', ME_process.message);
                        catch ME_default
                            error('parallelPoolStartup:Failed', ...
                                '进程并行池启动失败: %s | 默认并行池启动失败: %s', ...
                                ME_process.message, ME_default.message);
                        end
                    end
                else
                    parallel_status_msg = sprintf('复用已有并行池 (%s)', pool.Cluster.Type);
                end
                parallel_enabled = true;
            catch ME
                parallel_enabled = false;
                parallel_status_msg = sprintf('检测到工具箱，但并行池启动失败，已自动回退串行: %s', ME.message);
            end
        else
            parallel_status_msg = '未安装 Parallel Computing Toolbox 或许可证不可用';
        end
    end

    tf = parallel_enabled;
    status_msg = parallel_status_msg;
end

function [best_rc, best_dist, best_cost, feasible] = get_best_astar_segment(curr_pos, target_id, phase, agv_type, payload_weight)
    persistent segment_cache planning_map_cache;
    if isempty(segment_cache)
        segment_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end
    if isempty(planning_map_cache)
        planning_map_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end

    payload_key = sprintf('%.3f', payload_weight);
    cache_key = sprintf('%d|%d|%s|%d|%d|%s', agv_type, target_id, phase, curr_pos(1), curr_pos(2), payload_key);
    if isKey(segment_cache, cache_key)
        cached = segment_cache(cache_key);
        best_rc = cached.best_rc;
        best_dist = cached.best_dist;
        best_cost = cached.best_cost;
        feasible = cached.feasible;
        return;
    end

    [cost_map, map_rows, map_cols] = get_ga_costmap(agv_type);
    map_key = sprintf('%d', target_id);
    if isKey(planning_map_cache, map_key)
        planning_map = planning_map_cache(map_key);
    else
        planning_map = create_binary_grid_map(map_cols - 1, map_rows - 1, target_id);
        planning_map_cache(map_key) = planning_map;
    end

    candidates = get_ga_target_candidates(target_id, phase);
    best_rc = [];
    best_dist = inf;
    best_cost = inf;
    feasible = false;

    for i = 1:size(candidates, 1)
        candidate = candidates(i, :);
        if candidate(1) < 1 || candidate(1) > map_rows || candidate(2) < 1 || candidate(2) > map_cols
            continue;
        end
        if planning_map(candidate(1), candidate(2)) == 1
            continue;
        end

        eval_map = planning_map;
        eval_map(curr_pos(1), curr_pos(2)) = 0;
        [path, g_cost, ~, ~, path_length] = astar_planner_turn3(eval_map, curr_pos, candidate, payload_weight, cost_map);
        if isempty(path) || ~isfinite(g_cost)
            continue;
        end

        segment_dist = max(path_length - 1, 0);
        if (g_cost < best_cost - 1e-9) || ...
           (abs(g_cost - best_cost) <= 1e-9 && segment_dist < best_dist) || ...
           (abs(g_cost - best_cost) <= 1e-9 && abs(segment_dist - best_dist) <= 1e-9 && isempty(best_rc))
            best_rc = candidate;
            best_dist = segment_dist;
            best_cost = g_cost;
            feasible = true;
        end
    end

    segment_cache(cache_key) = struct('best_rc', best_rc, 'best_dist', best_dist, 'best_cost', best_cost, 'feasible', feasible);
end

function candidates = get_ga_target_candidates(target_id, phase)
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
    global costmap_type1 costmap_type2;
    if isempty(costmap_type1) || isempty(costmap_type2)
        init_global_costmaps();
    end

    if agv_type == 1
        cost_map = costmap_type1;
    else
        cost_map = costmap_type2;
    end

    [map_rows, map_cols] = size(cost_map);
end

function child = mutate_fork_cpo(chrom, num_tasks, num_agvs, pm, g, G, parent_rank_idx, PN)
% =========================================================================
% 函数功能：多策略自适应变异算子（Fork-CPO变异，结合了探索与开发策略）
% 注释已修复
% 注释已修复
%   num_tasks      - 任务数量
% 注释已修复
% 注释已修复
%   g              - 当前迭代代数
%   G              - 最大迭代代数
% 注释已修复
% 注释已修复
% 注释已修复
% 注释已修复
% =========================================================================
    child = chrom;                       % 以父代为基础生成子代
    if num_tasks < 2
        return;
    end

    % 计算分段阈值 tau1 和 tau2
    tau1 = rand(); 
    tau2 = rand();

    % tau1_prime 用于在探索与开发之间动态平衡
    % 其中 0.3*(1 - g/G) 表示随迭代推进逐步减小的探索强度
    % 注释已修复
    tau1_prime = tau1 - 0.3 * (1 - g/G); 

    % 根据 tau1_prime 与 tau2 的关系选择探索或开发模式
    if tau1_prime < tau2
        % ====== 探索策略：针对排名较差个体执行更强扰动 ======
        % 根据父代排名决定使用哪种探索操作
        if parent_rank_idx > 0.6 * PN
            % 注释已修复
            % 注释已修复
            range = sort(randperm(num_tasks, 2));      % range(1) <= range(2)
            % 注释已修复
            child(range(1):range(2)) = fliplr(child(range(1):range(2)));
            % 随机交换两个任务的 AGV 指派
        else
            % 2. 跨车交换：改变 AGV 指派组合，但保持任务顺序不变
            % 随机选择两个不同任务位置
            pos = randperm(num_tasks, 2);
            % 交换这两个任务的 AGV 指派
            agv_pos = pos + num_tasks;

            % 仅仅交换这两个任务的AGV指派编号
            ta = child(agv_pos(1)); 
            child(agv_pos(1)) = child(agv_pos(2)); 
            child(agv_pos(2)) = ta;
            % 注释已修复
        end
    else
        % ====== 开发策略（针对排名优秀的个体，局部精细搜索） ======
        if parent_rank_idx > 0.2 * PN
            % 3. 气味防御：插入变异（模拟任务插队，优秀的局部寻优）
            % 注释已修复
            pts = randperm(num_tasks, 2);
            extract_idx = pts(1); 
            insert_idx = pts(2);

            % 找出负载最大的 AGV 所承担任务的位置索引
            extracted_task = child(extract_idx);
            extracted_agv = child(extract_idx + num_tasks);

            % 注释已修复
            child(extract_idx) = []; 
            % 由于任务序列少了一个元素，对应的AGV指派序列也要删除相同位置（注意索引已变）
            % 注释已修复
            % 注释已修复
            child(extract_idx + num_tasks - 1) = [];

            % 注释已修复
            % 注释已修复
            % 构造新染色体：将提取的任务插入到新位置
            % 后半部分（AGV指派）：前半部分之后紧接着的是AGV指派部分
            % 注释已修复
            % 插入后染色体长度恢复为 2*num_tasks
            % 注释已修复
            % 插入后长度恢复为 2*num_tasks
            child = [child(1:insert_idx-1), extracted_task, child(insert_idx:num_tasks-1), ...
                     child(num_tasks:num_tasks+insert_idx-2), extracted_agv, child(num_tasks+insert_idx-1:end)];
            % 注释已修复
            % 注释已修复
            % 注释已修复
            %   child(insert_idx:num_tasks-1)          : 插入点后的任务序列（原剩余任务）
            %   child(num_tasks:num_tasks+insert_idx-2): 插入点前的AGV指派序列
            %   extracted_agv : 被插入任务对应的 AGV 指派
            %   child(num_tasks+insert_idx-1:end)       : 插入点后的AGV指派序列
        else
            % 4. 负载平衡调整：对优秀个体微调 AGV 指派
            % 注释已修复
            agv_idx = (num_tasks + 1) : (2 * num_tasks);
            current_agvs = child(agv_idx);      % 当前的AGV指派向量

            % 统计每个AGV被分配的任务数量（粗略代表负载）
            counts = histcounts(current_agvs, 1:num_agvs+1);

            [~, max_agv] = max(counts);         % 找出任务数最多的AGV（负载最大）
            [~, min_agv] = min(counts);         % 找出任务数最少的 AGV

            % 找出负载最大的AGV所承担的所有任务的位置索引
            heavy_tasks_idx = find(current_agvs == max_agv);

            if ~isempty(heavy_tasks_idx)
                % 随机选择一个任务，将其指派给负载最小的AGV
                transfer_idx = heavy_tasks_idx(randi(length(heavy_tasks_idx)));
                child(num_tasks + transfer_idx) = min_agv;
            end
            % 这里只改变 AGV 指派，不改变任务执行顺序
        end
    end

    % 注释已修复
    % 注释已修复
    if rand < (pm + 0.05)
        agv_idx = (num_tasks + 1) : (2 * num_tasks);
        current_agvs = child(agv_idx);          % 当前 AGV 指派向量

        % 注释已修复
        counts = zeros(1, num_agvs);
        for k = 1:num_agvs
            counts(k) = sum(current_agvs == k);
        end
        min_val = min(counts);
        candidates = find(counts == min_val);    % 所有当前负载最小的 AGV

        % 随机选择两个不同任务位置，强制调整其 AGV 指派
        mutate_pos = randperm(num_tasks, 2);
        for p = 1:2
            % 将这两个任务随机指派给当前负载最小的 AGV
            child(num_tasks + mutate_pos(p)) = candidates(randi(length(candidates)));
        end
    end
end

function [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks)
    if num_tasks < 2
        child1 = p1;
        child2 = p2;
        return;
    end
    % 注释已修复
    child1 = zeros(1, num_tasks * 2);
    child2 = zeros(1, num_tasks * 2);

    seq1 = p1(1:num_tasks);
    seq2 = p2(1:num_tasks);
    agv1 = p1(num_tasks+1:end);
    agv2 = p2(num_tasks+1:end);

    points = sort(randperm(num_tasks, 2));
    pt1 = points(1);
    pt2 = points(2);
    
    c1_seq = zeros(1, num_tasks);
    c2_seq = zeros(1, num_tasks);

    c1_seq(pt1:pt2) = seq1(pt1:pt2);
    c2_seq(pt1:pt2) = seq2(pt1:pt2);

    empty_idx = [1:pt1-1, pt2+1:num_tasks];
    
    rem_seq2 = seq2(~ismember(seq2, c1_seq(pt1:pt2)));
    rem_seq1 = seq1(~ismember(seq1, c2_seq(pt1:pt2)));
    
    c1_seq(empty_idx) = rem_seq2;
    c2_seq(empty_idx) = rem_seq1;

    M = randi([0, 1], 1, num_tasks);
    
    c1_agv = zeros(1, num_tasks);
    c2_agv = zeros(1, num_tasks);

    c1_agv(M == 0) = agv1(M == 0);
    c2_agv(M == 0) = agv2(M == 0);
    
    c1_agv(M == 1) = agv2(M == 1);
    c2_agv(M == 1) = agv1(M == 1);

    child1 = [c1_seq, c1_agv];
    child2 = [c2_seq, c2_agv];
end


