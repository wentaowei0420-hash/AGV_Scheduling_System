function [best_schedule, batch_details, metrics, history,pareto_fronts] = ga_schedule_optimizer_standard( ...
    task_list, num_agvs, depots, agv_params, ga_params, agv_types)
    % =========================================================
    % 函数定义：对比实验组 (Baseline)
    % 算法构成：无优化的标准 NSGA-II (托举车) + 标准 NSGA-II (叉车)
    % =========================================================
    
    oracle_options = struct();
    oracle_options.task_target_ids = unique(task_list(:, 2))';
    oracle_options.agv_types = unique(agv_types)';
    path_oracle = region_distance_oracle('build', oracle_options);

    idx_lift_tasks = task_list(:,2) <= 12;
    idx_fork_tasks = task_list(:,2) > 12;
    tasks_lift = task_list(idx_lift_tasks, :);
    tasks_fork = task_list(idx_fork_tasks, :);
    
    agvs_lift = find(agv_types == 1); 
    agvs_fork = find(agv_types == 2); 
    
    best_schedule = cell(1, num_agvs);
    batch_details = cell(1, num_agvs); 
    
    % 【修复 1】：安全初始化所有的历史与指标变量
    hist_lift_dist = zeros(1, ga_params.max_gen);
    hist_lift_time = zeros(1, ga_params.max_gen);
    hist_lift_energy = zeros(1, ga_params.max_gen);
    
    hist_fork_dist = zeros(1, ga_params.max_gen); 
    hist_fork_time = zeros(1, ga_params.max_gen);   
    hist_fork_energy = zeros(1, ga_params.max_gen); 
    
    % 【新增】：安全初始化前沿历史数组，防止某类任务为空时报错
    gen_fronts_lift = {};  
    gen_fronts_fork = {};
    
    dist_lift = 0; time_lift = 0; energy_lift = 0;
    dist_fork = 0; time_fork = 0; energy_fork = 0;
    
    %% --- 1. 托举车：标准 NSGA-II (无自适应，贪心分批) ---
    if ~isempty(tasks_lift) && ~isempty(agvs_lift)
        disp('   -> [对比组] 启动标准 NSGA-II 引擎 (托举车)...');
        eval_lift_moo = @(chrom) cost_func_lift_moo_baseline(chrom, tasks_lift, agvs_lift, depots, agv_params, path_oracle);
        
        % 【修改】：接收 gen_fronts_lift
        [pop_lift, objs_lift, fronts_lift, ~, hist_lift_dist, hist_lift_time, hist_lift_energy, gen_fronts_lift] = run_sub_nsga2_lift_baseline(tasks_lift, length(agvs_lift), ga_params, eval_lift_moo);
        
        front1_idx = fronts_lift{1}; 
        front1_objs = objs_lift(front1_idx, :);
        front1_violation = zeros(numel(front1_idx), 1);
        for ii = 1:numel(front1_idx)
            [~, ~, front1_violation(ii)] = eval_lift_moo(pop_lift(front1_idx(ii), :));
        end

        best_idx_in_front1 = select_feasible_compromise_index(front1_objs, front1_violation, @select_compromise_index);
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
    
    %% --- 2. 叉车：基础版 NSGA-II (Baseline) ---
    if ~isempty(tasks_fork) && ~isempty(agvs_fork)
        disp('   -> [对比组] 启动标准 NSGA-II 引擎 (叉车)...');
        eval_fork = @(chrom) cost_func_fork_baseline(chrom, tasks_fork, agvs_fork, depots, agv_params, path_oracle);
        
        % 【修改】：接收 gen_fronts_fork
        [pop_fork, objs_fork, fronts_fork, ~, hist_fork_dist, hist_fork_time, hist_fork_energy, gen_fronts_fork] = run_sub_nsga2_fork_baseline(tasks_fork, length(agvs_fork), ga_params, eval_fork);
        
        front1_idx = fronts_fork{1}; 
        front1_objs = objs_fork(front1_idx, :);
        front1_violation = zeros(numel(front1_idx), 1);
        for ii = 1:numel(front1_idx)
            [~, ~, front1_violation(ii)] = eval_fork(pop_fork(front1_idx(ii), :));
        end

        best_idx_in_front1 = select_feasible_compromise_index(front1_objs, front1_violation, @select_fork_baseline_compromise_index);
        best_fork_chrom = pop_fork(front1_idx(best_idx_in_front1), :);
        
        [sched_fork, best_objs_fork] = eval_fork(best_fork_chrom);
        
        dist_fork = best_objs_fork(1);
        time_fork = best_objs_fork(2);
        energy_fork = best_objs_fork(3);
        
        for i = 1:length(agvs_fork)
            best_schedule{agvs_fork(i)} = sched_fork{i};
            batch_details{agvs_fork(i)} = []; 
        end
    end
    
    %% === 统一结构体封装输出 ===
    metrics.lift.dist = dist_lift;       
    metrics.lift.time = time_lift;       
    metrics.lift.energy = energy_lift;   
    
    metrics.fork.dist = dist_fork;       
    metrics.fork.time = time_fork;       
    metrics.fork.energy = energy_fork;   
    
    history.lift.dist = hist_lift_dist;
    history.lift.time = hist_lift_time;
    history.lift.energy = hist_lift_energy;
    history.lift.gen_fronts = gen_fronts_lift; % 【新增】打包托举车历史前沿
    
    history.fork.dist = hist_fork_dist; 
    history.fork.time = hist_fork_time;
    history.fork.energy = hist_fork_energy;
    history.fork.gen_fronts = gen_fronts_fork; % 【新增】打包叉车历史前沿
    
    if ~isempty(tasks_lift)
        pareto_fronts.lift = objs_lift(fronts_lift{1}, :);
    end
    if ~isempty(tasks_fork)
        pareto_fronts.fork = objs_fork(fronts_fork{1}, :);
    end
end

%% ================== 托举式AGV相关函数 (Baseline) ==================
% 【修改】：在返回值中增加 gen_fronts_history
function [pop, pop_objs, fronts, cd, dist_hist, time_hist, energy_hist, gen_fronts_history] = run_sub_nsga2_lift_baseline(tasks, num_sub_agvs, ga_params, eval_func)
    % 对照组参数设定：固定且缺乏探索性
    pc = 0.45;  % 进一步降低交叉概率，减少有效重组
    pm = 0.01; % 进一步压低变异率，加剧早熟收敛
    clone_bias = 0.00; % 关闭显式克隆，减少重复子代
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    
    % 适配三维目标历史记录
    dist_hist = zeros(1, max_gen);
    time_hist = zeros(1, max_gen);
    energy_hist = zeros(1, max_gen);
    
    % 【新增】：为每一代的帕累托前沿预分配内存
    gen_fronts_history = cell(1, max_gen); 
    log_interval = max(1, ceil(max_gen / 20));
    max_obj_copies = 2;
    
    % --- 初始化种群 ---
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end    
    
    % --- 初始评估 ---
    pop_objs = zeros(pop_size, 3);
    pop_violation = zeros(pop_size, 1);
    for i = 1:pop_size
        [~, obj, violation] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;
        pop_violation(i) = violation;
    end    
    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs, pop_violation);
    cd = calc_crowding_distance(pop_objs, fronts);
    stagnation_counter = 0;
    last_signature = build_front_signature(pop_objs(fronts{1}, :));
    log_nsga_start('BASESTD-LIFT', num_tasks, num_sub_agvs, pop_size, max_gen, log_interval);
    log_lift_front_summary('BASESTD-LIFT', 'init', 0, max_gen, pop_objs, fronts, fronts{1}, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', 0));
    
    % --- 迭代循环 ---
    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);
        i = 1;
        while i <= pop_size
            % 锦标赛选择保持不变
            p1_idx = tournament_select_nsga2(rank, cd, pop_violation);
            p2_idx = tournament_select_nsga2(rank, cd, pop_violation);
            child1 = pop(p1_idx, :); 
            child2 = pop(p2_idx, :);
            
            % 【交叉】：使用破坏性强、缺乏拓扑保护的简单交叉算子
            if rand < pc
                % 1. 任务序列：单点交叉 + 强制修复
                cp = randi(num_tasks); 
                temp_segment = child1(1:cp);
                child1(1:cp) = child2(1:cp);
                child2(1:cp) = temp_segment;
                
                % [关键适配]：修复因单点交叉产生的非法重复解
                child1(1:num_tasks) = simple_repair(child1(1:num_tasks));
                child2(1:num_tasks) = simple_repair(child2(1:num_tasks));
                
                % 2. AGV指派：单点交叉
                cp_agv = randi(num_tasks); 
                offset = num_tasks; 
                temp_agv_segment = child1(offset + 1 : offset + cp_agv);
                child1(offset + 1 : offset + cp_agv) = child2(offset + 1 : offset + cp_agv);
                child2(offset + 1 : offset + cp_agv) = temp_agv_segment;
            end
            if rand < clone_bias
                child2 = child1;
            end
            
            % 【变异】：弱化为极其简单的两点随机交换
            if rand < pm
                idx = randperm(num_tasks, 2);
                tmp = child1(idx(1)); child1(idx(1)) = child1(idx(2)); child1(idx(2)) = tmp;
                child1(num_tasks + randi(num_tasks)) = randi(num_sub_agvs);
            end
            if rand < pm
                idx = randperm(num_tasks, 2);
                tmp = child2(idx(1)); child2(idx(1)) = child2(idx(2)); child2(idx(2)) = tmp;
                child2(num_tasks + randi(num_tasks)) = randi(num_sub_agvs);
            end
            if rand < clone_bias
                child2 = child1;
            end

            child1 = diversify_child_chromosome(child1, child2, pop(p1_idx, :), pop(p2_idx, :), num_tasks, num_sub_agvs);
            child2 = diversify_child_chromosome(child2, child1, pop(p1_idx, :), pop(p2_idx, :), num_tasks, num_sub_agvs);
            
            offspring(i,:) = child1;
            if i+1 <= pop_size, offspring(i+1,:) = child2; end
            i = i + 2;
        end
        
        % --- 评估子代 ---
        off_objs = zeros(pop_size, 3);
        off_violation = zeros(pop_size, 1);
        for i = 1:pop_size
            [~, obj, violation] = eval_func(offspring(i,:));
            off_objs(i,:) = obj;
            off_violation(i) = violation;
        end
        
        % --- 合并、排序与精英截断 ---
        prev_unique_front = count_unique_front_objs(pop_objs(fronts{1}, :));
        immigrants_count = determine_baseline_lift_immigrant_count(prev_unique_front, stagnation_counter, pop_size);
        combined_pop=[pop; offspring];
        combined_objs=[pop_objs; off_objs];
        combined_violation = [pop_violation; off_violation];
        if immigrants_count > 0
            immigrant_pop = generate_random_population_moo(immigrants_count, num_tasks, num_sub_agvs);
            immigrant_objs = zeros(immigrants_count, 3);
            immigrant_violation = zeros(immigrants_count, 1);
            for ii = 1:immigrants_count
                [~, obj, violation] = eval_func(immigrant_pop(ii, :));
                immigrant_objs(ii, :) = obj;
                immigrant_violation(ii) = violation;
            end
            combined_pop = [combined_pop; immigrant_pop];
            combined_objs = [combined_objs; immigrant_objs];
            combined_violation = [combined_violation; immigrant_violation];
        end
        
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs, combined_violation);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);
        
        pop = zeros(pop_size, num_tasks * 2);
        pop_objs = zeros(pop_size, 3);
        pop_violation = zeros(pop_size, 1);
        current_idx = 1; f = 1;
        
        while current_idx <= pop_size && f <= length(c_fronts)
            front = c_fronts{f};
            if current_idx + length(front) - 1 <= pop_size
                pop(current_idx : current_idx + length(front) - 1, :) = combined_pop(front, :);
                pop_objs(current_idx : current_idx + length(front) - 1, :) = combined_objs(front, :);
                pop_violation(current_idx : current_idx + length(front) - 1, :) = combined_violation(front, :);
                current_idx = current_idx + length(front);
            else
                [~, sort_idx] = sort(c_cd(front), 'descend');
                num_needed = pop_size - current_idx + 1;
                selected_front = front(sort_idx(1:num_needed));
                pop(current_idx : end, :) = combined_pop(selected_front, :);
                pop_objs(current_idx : end, :) = combined_objs(selected_front, :);
                pop_violation(current_idx : end, :) = combined_violation(selected_front, :);
                break;
            end
            f = f + 1;
        end
        [pop, pop_objs, pop_violation, replaced_count_all] = reduce_population_duplicates_moo(pop, pop_objs, pop_violation, num_tasks, num_sub_agvs, eval_func, max_obj_copies);
        [fronts_tmp, ~] = fast_non_dominated_sorting(pop_objs, pop_violation);
        [pop, pop_objs, pop_violation, replaced_count_front] = reduce_front_duplicates_moo(pop, pop_objs, pop_violation, fronts_tmp{1}, num_tasks, num_sub_agvs, eval_func, max_obj_copies);
        replaced_count = replaced_count_all + replaced_count_front;
        [fronts, rank] = fast_non_dominated_sorting(pop_objs, pop_violation);
        cd = calc_crowding_distance(pop_objs, fronts);
        
        % --- 记录收敛历史 ---
        front1 = fronts{1};
        min_objs_in_front = min(pop_objs(front1, :), [], 1);
        current_signature = build_front_signature(pop_objs(front1, :));
        if isequal(current_signature, last_signature)
            stagnation_counter = stagnation_counter + 1;
        else
            stagnation_counter = 0;
            last_signature = current_signature;
        end
        dist_hist(gen) = min_objs_in_front(1);
        time_hist(gen) = min_objs_in_front(2);
        energy_hist(gen) = min_objs_in_front(3);
        
        % 【新增】：保存这一代的第一前沿所有解的目标值 (N x 3 矩阵)
        gen_fronts_history{gen} = pop_objs(front1, :);
        if should_log_iteration(gen, max_gen, log_interval)
            log_lift_front_summary('BASESTD-LIFT', 'gen', gen, max_gen, pop_objs, fronts, front1, ...
                struct('immigrants', immigrants_count, 'replaced', replaced_count, 'stall', stagnation_counter));
        end
    end
    log_lift_front_summary('BASESTD-LIFT', 'done', max_gen, max_gen, pop_objs, fronts, fronts{1}, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', stagnation_counter));
end

function [schedules, objectives, batch_info, constraint_violation] = cost_func_lift_moo_baseline(chromosome, tasks, agv_ids, depots, agv_params, path_oracle)
    num_tasks = size(tasks, 1);
    num_agvs = length(agv_ids);
    task_seq = chromosome(1:num_tasks); 
    agv_assign = chromosome(num_tasks+1:end);    
    
    schedules = cell(1, num_agvs); 
    batch_info = cell(1, num_agvs); 
    agv_dists = zeros(1, num_agvs);               
    agv_times = zeros(1, num_agvs);               
    agv_energy = zeros(1, num_agvs); 
    
    constraint_violation = 0;
    for k = 1:num_agvs
        real_agv_id = agv_ids(k);                  
        curr_agv = agv_params(real_agv_id);
        max_load_capacity = get_energy_capacity_by_agv_type(curr_agv, 1, 80);
        
        my_tasks = task_seq(agv_assign == k);
        real_task_ids = tasks(my_tasks, 1)';
        schedules{k} = real_task_ids;
        if isempty(my_tasks)
            schedules{k} = []; 
            continue;                               
        end
        
        % FFD (First Fit Decreasing) 启发式装箱逻辑
        batches = {};
        task_weights = tasks(my_tasks, 3);
        [~, sort_idx] = sort(task_weights, 'descend');
        sorted_my_tasks = my_tasks(sort_idx);
        batch_weights_list = []; 
        
        for t = 1:length(sorted_my_tasks)
            row_idx = sorted_my_tasks(t);
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
        for b = 1:length(batches)
            [~, loc] = ismember(batches{b}, my_tasks);
            [~, order] = sort(loc);
            batches{b} = batches{b}(order);
            real_task_ids = [real_task_ids, tasks(batches{b}, 1)']; 
        end
        
        schedules{k} = real_task_ids;
        real_task_batches = cell(1, length(batches));
        for b = 1:length(batches)
            real_task_batches{b} = tasks(batches{b}, 1)'; 
        end
        
        batch_info{k} = struct('num_batches', length(batches), 'task_batches', {real_task_batches}, 'batch_weights', batch_weights_list);
        
        curr_pos = depots(real_agv_id, :);             
        dist_sum = 0; time_spent = 0; energy_spent = 0;
        
        e_base = 0.3; e_load_factor = 0.2; 
        if isfield(curr_agv, 'e_base'), e_base = curr_agv.e_base; end
        if isfield(curr_agv, 'e_load_factor'), e_load_factor = curr_agv.e_load_factor; end
        for b = 1:length(batches)
            batch = batches{b};
            current_payload = 0; 
            speed = max(curr_agv.speed, 1e-6);
            
            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);          
                [pick_rc, segment_dist, ~, feasible] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 1, current_payload);
                if ~feasible
                    objectives = [inf, inf, inf];
                    constraint_violation = inf;
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
                    constraint_violation = inf;
                    return;
                end
                
                dist_sum = dist_sum + segment_dist;
                time_spent = time_spent + segment_dist / speed;
                energy_spent = energy_spent + segment_dist * (e_base + e_load_factor * (current_payload / max_load_capacity));
                
                curr_pos = drop_rc;                      
                current_payload = current_payload - tasks(batch(j), 3);
                if size(tasks, 2) >= 4
                    deadline = tasks(batch(j), 4);
                    if isfinite(deadline) && ~isnan(deadline)
                        constraint_violation = constraint_violation + max(0, time_spent - deadline);
                    end
                end
            end
        end
        agv_dists(k) = dist_sum;                           
        agv_times(k) = time_spent;                          
        agv_energy(k) = energy_spent;
    end
    
    f1 = sum(agv_dists);           
    f2 = max(agv_times);           
    f3 = sum(agv_energy);         
    objectives = [f1, f2, f3];     
end

%% ================== 叉车式AGV相关函数 (Baseline NSGA-II) ==================
% 【修改】：在返回值中增加 gen_fronts_history
function [pop, pop_objs, fronts, cd, cost_hist_dist, cost_hist_time, cost_hist_energy, gen_fronts_history] = run_sub_nsga2_fork_baseline(tasks, num_sub_agvs, ga_params, eval_func)
    % =========================================================================
    % 叉车 NSGA-II 对照组 (Baseline)
    % 特点：固定交叉/变异概率，使用基础单点交叉(带强行修复)与简单两点交换变异
    % =========================================================================
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    
    pc = 0.50; 
    pm = 0.020; 
    clone_bias = 0.05; % 保留少量基线特征，但减少对子代多样性的抑制
    
    clone_bias = 0.18; % keep baseline intentionally weaker
    cost_hist_dist = zeros(1, max_gen);
    cost_hist_time = zeros(1, max_gen);
    cost_hist_energy = zeros(1, max_gen);
    
    % 【新增】：为每一代的帕累托前沿预分配内存
    gen_fronts_history = cell(1, max_gen); 
    log_interval = max(1, ceil(max_gen / 20));
    max_obj_copies = 1;
    
    % --- 1. 初始化种群 ---
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);                
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks); 
    end
    
    % --- 2. 初始评估 (三维目标: 距离, 时间, 能耗) ---
    pop_objs = zeros(pop_size, 3);
    pop_violation = zeros(pop_size, 1);
    for i = 1:pop_size
        [~, obj, violation] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;
        pop_violation(i) = violation;
    end
    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs, pop_violation);
    cd = calc_crowding_distance(pop_objs, fronts);
    stagnation_counter = 0;
    last_signature = build_front_signature(pop_objs(fronts{1}, :));
    log_nsga_start('BASESTD-FORK', num_tasks, num_sub_agvs, pop_size, max_gen, log_interval);
    log_fork_front_summary('BASESTD-FORK', 'init', 0, max_gen, pop, pop_objs, fronts, fronts{1}, num_tasks, num_sub_agvs, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', 0));
    
    % --- 3. 进化迭代循环 ---
    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);
        i = 1;
        while i <= pop_size
            % 锦标赛选择
            p1_idx = tournament_select_nsga2(rank, cd, pop_violation);
            p2_idx = tournament_select_nsga2(rank, cd, pop_violation);
            
            child1 = pop(p1_idx, :); 
            child2 = pop(p2_idx, :);          
            
            % =========================================================
            % 【降级交叉】：单点交叉 + 强制修复 (真正的基因重组，但会破坏优良结构)
            % =========================================================
            if rand < pc
                % 1. 任务序列：单点截断交叉
                cp = randi(num_tasks); 
                temp_segment = child1(1:cp);
                child1(1:cp) = child2(1:cp);
                child2(1:cp) = temp_segment;
                
                % [必须执行]：修复因单点交叉产生的任务编号重复/缺失
                child1(1:num_tasks) = simple_repair(child1(1:num_tasks));
                child2(1:num_tasks) = simple_repair(child2(1:num_tasks));
                
                % 2. AGV指派：单点截断交叉
                cp_agv = randi(num_tasks); 
                offset = num_tasks; 
                temp_agv_segment = child1(offset + 1 : offset + cp_agv);
                child1(offset + 1 : offset + cp_agv) = child2(offset + 1 : offset + cp_agv);
                child2(offset + 1 : offset + cp_agv) = temp_agv_segment;
            end
            if rand < clone_bias
                child2 = child1;
            end
            
            % =========================================================
            % 【降级变异】：基础的两点盲目互换 + 随机改变一辆车的指派
            % =========================================================
            if rand < pm
                % 任务互换
                idx = randperm(num_tasks, 2);
                tmp = child1(idx(1)); child1(idx(1)) = child1(idx(2)); child1(idx(2)) = tmp;
                % 随机改变某个任务的AGV
                child1(num_tasks + randi(num_tasks)) = randi(num_sub_agvs);
            end
            
            if rand < pm
                % 任务互换
                idx = randperm(num_tasks, 2);
                tmp = child2(idx(1)); child2(idx(1)) = child2(idx(2)); child2(idx(2)) = tmp;
                % 随机改变某个任务的AGV
                child2(num_tasks + randi(num_tasks)) = randi(num_sub_agvs);
            end

            child1 = diversify_child_chromosome(child1, child2, pop(p1_idx, :), pop(p2_idx, :), num_tasks, num_sub_agvs);
            child2 = diversify_child_chromosome(child2, child1, pop(p1_idx, :), pop(p2_idx, :), num_tasks, num_sub_agvs);
            
            offspring(i,:) = child1;
            if i + 1 <= pop_size
                offspring(i+1,:) = child2; 
            end
            i = i + 2;                            
        end
        
        % --- 4. 评估子代 ---
        off_objs = zeros(pop_size, 3);
        off_violation = zeros(pop_size, 1);
        for j = 1:pop_size
            [~, obj, violation] = eval_func(offspring(j,:));
            off_objs(j,:) = obj;
            off_violation(j) = violation;
        end
        
        % --- 5. 合并与非支配排序 ---
        prev_unique_front = count_unique_front_objs(pop_objs(fronts{1}, :));
        immigrants_count = determine_baseline_fork_immigrant_count(prev_unique_front, stagnation_counter, pop_size);
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        combined_violation = [pop_violation; off_violation];
        if immigrants_count > 0
            immigrant_pop = generate_random_population_moo(immigrants_count, num_tasks, num_sub_agvs);
            immigrant_objs = zeros(immigrants_count, 3);
            immigrant_violation = zeros(immigrants_count, 1);
            for ii = 1:immigrants_count
                [~, obj, violation] = eval_func(immigrant_pop(ii, :));
                immigrant_objs(ii, :) = obj;
                immigrant_violation(ii) = violation;
            end
            combined_pop = [combined_pop; immigrant_pop];
            combined_objs = [combined_objs; immigrant_objs];
            combined_violation = [combined_violation; immigrant_violation];
        end
        
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs, combined_violation);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);
        
        % --- 6. 精英截断 (Elitism) ---
        pop = zeros(pop_size, num_tasks * 2);
        pop_objs = zeros(pop_size, 3);
        pop_violation = zeros(pop_size, 1);
        current_idx = 1; 
        f = 1;
        
        while current_idx <= pop_size && f <= length(c_fronts)
            front = c_fronts{f};
            if current_idx + length(front) - 1 <= pop_size
                pop(current_idx : current_idx + length(front) - 1, :) = combined_pop(front, :);
                pop_objs(current_idx : current_idx + length(front) - 1, :) = combined_objs(front, :);
                pop_violation(current_idx : current_idx + length(front) - 1, :) = combined_violation(front, :);
                current_idx = current_idx + length(front);
            else
                [~, sort_idx] = sort(c_cd(front), 'descend');
                num_needed = pop_size - current_idx + 1;
                selected_front = front(sort_idx(1:num_needed));
                pop(current_idx : end, :) = combined_pop(selected_front, :);
                pop_objs(current_idx : end, :) = combined_objs(selected_front, :);
                pop_violation(current_idx : end, :) = combined_violation(selected_front, :);
                break;
            end
            f = f + 1;
        end

        [pop, pop_objs, pop_violation, replaced_count_all] = reduce_population_duplicates_moo(pop, pop_objs, pop_violation, num_tasks, num_sub_agvs, eval_func, max_obj_copies);
        [fronts_tmp, ~] = fast_non_dominated_sorting(pop_objs, pop_violation);
        [pop, pop_objs, pop_violation, replaced_count_front] = reduce_front_duplicates_moo(pop, pop_objs, pop_violation, fronts_tmp{1}, num_tasks, num_sub_agvs, eval_func, max_obj_copies);
        replaced_count = replaced_count_all + replaced_count_front;
        
        [fronts, rank] = fast_non_dominated_sorting(pop_objs, pop_violation);
        cd = calc_crowding_distance(pop_objs, fronts);
        
        % --- 7. 记录收敛历史 ---
        front1 = fronts{1};
        min_objs_in_front = min(pop_objs(front1, :), [], 1);
        current_signature = build_front_signature(pop_objs(front1, :));
        if isequal(current_signature, last_signature)
            stagnation_counter = stagnation_counter + 1;
        else
            stagnation_counter = 0;
            last_signature = current_signature;
        end
        cost_hist_dist(gen) = min_objs_in_front(1);
        cost_hist_time(gen) = min_objs_in_front(2);
        cost_hist_energy(gen) = min_objs_in_front(3);
        
        % 【新增】：保存这一代的第一前沿所有解的目标值 (N x 3 矩阵)
        gen_fronts_history{gen} = pop_objs(front1, :);
        if should_log_iteration(gen, max_gen, log_interval)
            log_fork_front_summary('BASESTD-FORK', 'gen', gen, max_gen, pop, pop_objs, fronts, front1, num_tasks, num_sub_agvs, ...
                struct('immigrants', immigrants_count, 'replaced', replaced_count, 'stall', stagnation_counter));
        end
    end
    log_fork_front_summary('BASESTD-FORK', 'done', max_gen, max_gen, pop, pop_objs, fronts, fronts{1}, num_tasks, num_sub_agvs, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', stagnation_counter));
end

function [schedules, objectives, constraint_violation] = cost_func_fork_baseline(chromosome, tasks, agv_ids, depots, agv_params, path_oracle)
    num_tasks = size(tasks, 1); num_agvs = length(agv_ids);
    task_seq = chromosome(1:num_tasks); agv_assign = chromosome(num_tasks+1:end);
    schedules = cell(1, num_agvs); 
    
    agv_dists = zeros(1, num_agvs);
    agv_times = zeros(1, num_agvs);
    agv_energy = zeros(1, num_agvs);
    
    constraint_violation = 0;
    for k = 1:num_agvs
        real_agv_id = agv_ids(k); curr_agv = agv_params(real_agv_id);
        max_load_capacity = get_energy_capacity_by_agv_type(curr_agv, 2, 500);
        my_tasks = task_seq(agv_assign == k);
        real_task_ids = tasks(my_tasks, 1)'; schedules{k} = real_task_ids;
        if isempty(my_tasks), continue; end
        
        curr_pos = depots(real_agv_id, :);
        dist_sum = 0; time_spent = 0; energy_spent = 0;
        
        e_base = 1.0; e_load_factor = 0.3; 
        if isfield(curr_agv, 'e_base'), e_base = curr_agv.e_base; end
        if isfield(curr_agv, 'e_load_factor'), e_load_factor = curr_agv.e_load_factor; end
        speed = max(curr_agv.speed, 1e-6);
        
        for t = 1:length(my_tasks)
            row_idx = my_tasks(t);
            target_id = tasks(row_idx, 2);
            task_weight = tasks(row_idx, 3);
            [pick_rc, d1, ~, feasible_pick] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 2, 0);
            if ~feasible_pick
                objectives = [inf, inf, inf];
                constraint_violation = inf;
                return;
            end

            [drop_rc, d2, ~, feasible_drop] = query_region_oracle_or_astar(path_oracle, pick_rc, target_id, 'dropoff', 2, task_weight);
            if ~feasible_drop
                objectives = [inf, inf, inf];
                constraint_violation = inf;
                return;
            end
            
            dist_sum = dist_sum + d1;              
            energy_spent = energy_spent + (d1 * e_base);
            
            dist_sum = dist_sum + d2;
            energy_spent = energy_spent + (d2 * (e_base + e_load_factor * (task_weight / max_load_capacity)));
            
            time_spent = time_spent + (d1 + d2) / speed;
            if size(tasks, 2) >= 4
                deadline = tasks(row_idx, 4);
                if isfinite(deadline) && ~isnan(deadline)
                    constraint_violation = constraint_violation + max(0, time_spent - deadline);
                end
            end
            curr_pos = drop_rc;                               
        end
        agv_dists(k) = dist_sum;
        agv_times(k) = time_spent;
        agv_energy(k) = energy_spent;
    end
    
    f1 = sum(agv_dists);           
    f2 = max(agv_times);           
    f3 = sum(agv_energy);          
    objectives = [f1, f2, f3]; 
end

%% ================== 公共函数 (Baseline) ==================
function [fronts, rank] = fast_non_dominated_sorting(pop_objs, pop_violation)
    pop_size = size(pop_objs, 1); fronts = cell(pop_size, 1); domination_count = zeros(pop_size, 1); dominated_set = cell(pop_size, 1); rank = zeros(pop_size, 1);
    if nargin < 2 || isempty(pop_violation)
        pop_violation = zeros(pop_size, 1);
    end
    for i = 1:pop_size
        for j = 1:pop_size
            if i == j, continue; end
            if constraint_dominates(pop_objs(i,:), pop_violation(i), pop_objs(j,:), pop_violation(j))
                dominated_set{i} = [dominated_set{i}, j];
            elseif constraint_dominates(pop_objs(j,:), pop_violation(j), pop_objs(i,:), pop_violation(i))
                domination_count(i) = domination_count(i) + 1;
            end
        end
        if domination_count(i) == 0, rank(i) = 1; fronts{1} = [fronts{1}, i]; end
    end
    current_front = 1;
    while ~isempty(fronts{current_front})
        next_front = [];
        for i = fronts{current_front}
            for j = dominated_set{i}
                domination_count(j) = domination_count(j) - 1;
                if domination_count(j) == 0, rank(j) = current_front + 1; next_front = [next_front, j]; end
            end
        end
        current_front = current_front + 1; fronts{current_front} = next_front;
    end
    fronts(cellfun(@isempty, fronts)) = []; 
end
function cd = calc_crowding_distance(pop_objs, fronts)
    pop_size = size(pop_objs, 1); num_objs = size(pop_objs, 2); cd = zeros(pop_size, 1);
    for f = 1:length(fronts)
        front = fronts{f}; l = length(front);
        if l <= 2, cd(front) = inf; continue; end
        for m = 1:num_objs
            [sorted_objs, idx] = sort(pop_objs(front, m)); sorted_front = front(idx);
            cd(sorted_front(1)) = inf; cd(sorted_front(end)) = inf;
            f_min = sorted_objs(1); f_max = sorted_objs(end);
            if f_max - f_min == 0, continue; end 
            for i = 2:l-1, cd(sorted_front(i)) = cd(sorted_front(i)) + (sorted_objs(i+1) - sorted_objs(i-1)) / (f_max - f_min); end
        end
    end
end
function idx = tournament_select_nsga2(rank, cd, violation)
    pop_size = length(rank); i1 = randi(pop_size); i2 = randi(pop_size);
    if nargin >= 3 && ~isempty(violation)
        tol = 1e-9;
        feas1 = isfinite(violation(i1)) && violation(i1) <= tol;
        feas2 = isfinite(violation(i2)) && violation(i2) <= tol;
        if feas1 && ~feas2
            idx = i1;
            return;
        elseif ~feas1 && feas2
            idx = i2;
            return;
        elseif ~feas1 && ~feas2 && abs(violation(i1) - violation(i2)) > tol
            if violation(i1) < violation(i2)
                idx = i1;
            else
                idx = i2;
            end
            return;
        end
    end
    if rank(i1) < rank(i2), idx = i1; elseif rank(i1) > rank(i2), idx = i2; else
        if cd(i1) > cd(i2), idx = i1; else, idx = i2; end
    end
end
function p = simple_repair(p)
    % 用于修复单点交叉后产生的重复任务编号，使其恢复为合法的全排列
    num = length(p);
    [~, unique_idx] = unique(p, 'first');
    
    % 如果去重后的长度小于总长度，说明有重复基因
    if length(unique_idx) < num
        all_vals = 1:num;
        % 找出缺失的任务编号
        missing_vals = setdiff(all_vals, p(unique_idx));
        
        % 找出重复位置的逻辑掩码
        duplicate_mask = true(1, num);
        duplicate_mask(unique_idx) = false;
        
        % 用缺失的任务号随机填充那些重复的位置
        p(duplicate_mask) = missing_vals(randperm(length(missing_vals)));
    end
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

function idx = select_fork_baseline_compromise_index(front_objs)
    if isempty(front_objs)
        idx = 1;
        return;
    end

    best_time = min(front_objs(:, 2));
    time_gate = best_time * 1.04 + 1e-9;
    candidate_idx = find(front_objs(:, 2) <= time_gate);
    if isempty(candidate_idx)
        candidate_idx = 1:size(front_objs, 1);
    end

    candidate_objs = front_objs(candidate_idx, :);
    min_objs = min(candidate_objs, [], 1);
    max_objs = max(candidate_objs, [], 1);
    obj_norm = (candidate_objs - min_objs) ./ (max_objs - min_objs + 1e-9);

    weights = [0.22, 0.56, 0.22];
    weighted_scores = obj_norm * weights';
    [~, local_idx] = min(weighted_scores);
    idx = candidate_idx(local_idx);
end

function idx = select_feasible_compromise_index(front_objs, front_violation, compromise_selector)
    if isempty(front_objs)
        idx = 1;
        return;
    end

    if nargin < 3 || isempty(compromise_selector)
        compromise_selector = @select_compromise_index;
    end

    tol = 1e-9;
    feasible_idx = find(isfinite(front_violation) & front_violation <= tol);
    if ~isempty(feasible_idx)
        local_idx = compromise_selector(front_objs(feasible_idx, :));
        idx = feasible_idx(local_idx);
        return;
    end

    min_violation = min(front_violation);
    candidate_idx = find(abs(front_violation - min_violation) <= tol);
    local_idx = compromise_selector(front_objs(candidate_idx, :));
    idx = candidate_idx(local_idx);
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

function child = diversify_child_chromosome(child, sibling, parent1, parent2, num_tasks, num_agvs)
    if nargin < 2
        sibling = [];
    end

    is_duplicate = isequal(child, parent1) || isequal(child, parent2) || (~isempty(sibling) && isequal(child, sibling));
    if ~is_duplicate
        return;
    end

    child = force_diversify_chromosome(child, num_tasks, num_agvs);
    if isequal(child, parent1) || isequal(child, parent2) || (~isempty(sibling) && isequal(child, sibling))
        child = force_diversify_chromosome(child, num_tasks, num_agvs);
    end
end

function chrom = force_diversify_chromosome(chrom, num_tasks, num_agvs)
    if num_tasks >= 2
        idx = randperm(num_tasks, 2);
        tmp = chrom(idx(1));
        chrom(idx(1)) = chrom(idx(2));
        chrom(idx(2)) = tmp;
    end

    if num_tasks >= 4 && rand < 0.7
        seg = sort(randperm(num_tasks, 2));
        chrom(seg(1):seg(2)) = fliplr(chrom(seg(1):seg(2)));
    end

    assign_count = min(num_tasks, max(1, ceil(0.15 * num_tasks)));
    assign_idx = randperm(num_tasks, assign_count);
    chrom(num_tasks + assign_idx) = randi([1, num_agvs], 1, assign_count);
end

function [pop, pop_objs, pop_violation, replaced_count] = reduce_population_duplicates_moo(pop, pop_objs, pop_violation, num_tasks, num_agvs, eval_func, max_obj_copies)
    replaced_count = 0;
    rounded_objs = quantize_moo_objectives(pop_objs);
    [~, ~, obj_group] = unique(rounded_objs, 'rows', 'stable');
    for group_id = 1:max(obj_group)
        members = find(obj_group == group_id);
        if numel(members) <= max_obj_copies
            continue;
        end
        overflow = members(max_obj_copies + 1:end);
        for k = 1:numel(overflow)
            idx = overflow(k);
            pop(idx, 1:num_tasks) = randperm(num_tasks);
            pop(idx, num_tasks+1:end) = randi([1, num_agvs], 1, num_tasks);
            [~, obj, violation] = eval_func(pop(idx, :));
            pop_objs(idx, :) = obj;
            pop_violation(idx) = violation;
            replaced_count = replaced_count + 1;
        end
    end
end

function [pop, pop_objs, pop_violation, replaced_count] = reduce_front_duplicates_moo(pop, pop_objs, pop_violation, front_idx, num_tasks, num_agvs, eval_func, max_obj_copies)
    replaced_count = 0;
    if isempty(front_idx)
        return;
    end

    rounded_front = quantize_moo_objectives(pop_objs(front_idx, :));
    [~, ~, obj_group] = unique(rounded_front, 'rows', 'stable');
    for group_id = 1:max(obj_group)
        members = front_idx(obj_group == group_id);
        if numel(members) <= max_obj_copies
            continue;
        end
        overflow = members(max_obj_copies + 1:end);
        for k = 1:numel(overflow)
            idx = overflow(k);
            pop(idx, 1:num_tasks) = randperm(num_tasks);
            pop(idx, num_tasks+1:end) = randi([1, num_agvs], 1, num_tasks);
            [~, obj, violation] = eval_func(pop(idx, :));
            pop_objs(idx, :) = obj;
            pop_violation(idx) = violation;
            replaced_count = replaced_count + 1;
        end
    end
end

function pop = generate_random_population_moo(pop_size, num_tasks, num_agvs)
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_agvs], 1, num_tasks);
    end
end

function immigrants = determine_baseline_lift_immigrant_count(unique_front, stagnation_counter, pop_size)
    immigrants = 0;
    if unique_front <= 2
        if stagnation_counter >= 30 && mod(stagnation_counter, 10) == 0
            immigrants = max(immigrants, ceil(0.07 * pop_size));
        elseif stagnation_counter >= 12 && mod(stagnation_counter, 6) == 0
            immigrants = max(immigrants, ceil(0.05 * pop_size));
        elseif stagnation_counter == 0
            immigrants = max(immigrants, max(2, ceil(0.03 * pop_size)));
        end
    elseif unique_front <= 4
        if stagnation_counter >= 36 && mod(stagnation_counter, 12) == 0
            immigrants = max(immigrants, ceil(0.06 * pop_size));
        elseif stagnation_counter >= 18 && mod(stagnation_counter, 9) == 0
            immigrants = max(immigrants, ceil(0.04 * pop_size));
        end
    elseif stagnation_counter >= 45 && mod(stagnation_counter, 15) == 0
        immigrants = max(immigrants, ceil(0.03 * pop_size));
    end

    immigrants = min(immigrants, ceil(0.10 * pop_size));
end

function immigrants = determine_baseline_fork_immigrant_count(unique_front, stagnation_counter, pop_size)
    immigrants = 0;
    if unique_front <= 2
        if stagnation_counter >= 48 && mod(stagnation_counter, 16) == 0
            immigrants = max(immigrants, ceil(0.06 * pop_size));
        elseif stagnation_counter >= 24 && mod(stagnation_counter, 8) == 0
            immigrants = max(immigrants, ceil(0.04 * pop_size));
        elseif stagnation_counter == 0
            immigrants = max(immigrants, max(2, ceil(0.02 * pop_size)));
        end
    elseif unique_front <= 4
        if stagnation_counter >= 54 && mod(stagnation_counter, 18) == 0
            immigrants = max(immigrants, ceil(0.05 * pop_size));
        elseif stagnation_counter >= 27 && mod(stagnation_counter, 9) == 0
            immigrants = max(immigrants, ceil(0.03 * pop_size));
        end
    elseif stagnation_counter >= 60 && mod(stagnation_counter, 20) == 0
        immigrants = max(immigrants, ceil(0.02 * pop_size));
    end

    immigrants = min(immigrants, ceil(0.08 * pop_size));
end

function unique_front = count_unique_front_objs(front_objs)
    unique_front = size(unique(quantize_moo_objectives(front_objs), 'rows'), 1);
end

function rounded_objs = quantize_moo_objectives(pop_objs)
    rounded_objs = [round(pop_objs(:, 1), 0), round(pop_objs(:, 2), 2), round(pop_objs(:, 3), 4)];
end

function tf = constraint_dominates(obj_a, violation_a, obj_b, violation_b)
    tol = 1e-9;
    feasible_a = isfinite(violation_a) && violation_a <= tol;
    feasible_b = isfinite(violation_b) && violation_b <= tol;

    if feasible_a && ~feasible_b
        tf = true;
        return;
    elseif ~feasible_a && feasible_b
        tf = false;
        return;
    elseif ~feasible_a && ~feasible_b
        if violation_a < violation_b - tol
            tf = true;
            return;
        elseif violation_a > violation_b + tol
            tf = false;
            return;
        end
    end

    tf = all(obj_a <= obj_b) && any(obj_a < obj_b);
end

function signature = build_front_signature(front_objs)
    rounded_front = quantize_moo_objectives(front_objs);
    signature = sortrows(unique(rounded_front, 'rows'), [1 2 3]);
end

function tf = should_log_iteration(gen, max_gen, log_interval)
    tf = (gen == 1) || (gen == max_gen) || (mod(gen, log_interval) == 0);
end

function log_nsga_start(tag, num_tasks, num_agvs, pop_size, max_gen, log_interval)
    fprintf('      [%s] start | tasks=%d | agvs=%d | pop=%d | gen=%d | logInterval=%d\n', ...
        tag, num_tasks, num_agvs, pop_size, max_gen, log_interval);
end

function log_front_summary(tag, phase, gen, max_gen, pop_objs, fronts, front_idx, compromise_selector)
    front_objs = pop_objs(front_idx, :);
    raw_front = size(front_objs, 1);
    unique_front = count_unique_front_objs(front_objs);
    min_objs = min(front_objs, [], 1);
    rep_idx = compromise_selector(front_objs);
    compromise = front_objs(rep_idx, :);
    [front_levels, front_sizes_str] = summarize_front_layers(fronts);

    if strcmp(phase, 'gen')
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end
    fprintf('      [%s] %-5s | frontLevels=%d | frontSizes=%s\n', ...
        tag, phase, front_levels, front_sizes_str);
end

function log_lift_front_summary(tag, phase, gen, max_gen, pop_objs, fronts, front_idx, stats)
    if nargin < 8 || isempty(stats)
        stats = struct('immigrants', 0, 'replaced', 0, 'stall', 0);
    end
    front_objs = pop_objs(front_idx, :);
    raw_front = size(front_objs, 1);
    unique_front = count_unique_front_objs(front_objs);
    min_objs = min(front_objs, [], 1);
    rep_idx = select_compromise_index(front_objs);
    compromise = front_objs(rep_idx, :);
    [front_levels, front_sizes_str] = summarize_front_layers(fronts);

    if strcmp(phase, 'gen')
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end
    fprintf('      [%s] %-5s | frontLevels=%d | frontSizes=%s\n', ...
        tag, phase, front_levels, front_sizes_str);

    fprintf('      [%s] %-5s | immigrants=%d | replaced=%d | stall=%d\n', ...
        tag, phase, stats.immigrants, stats.replaced, stats.stall);
end

function log_fork_front_summary(tag, phase, gen, max_gen, pop, pop_objs, fronts, front_idx, num_tasks, num_agvs, stats)
    if nargin < 11 || isempty(stats)
        stats = struct('immigrants', 0, 'replaced', 0, 'stall', 0);
    end
    front_objs = pop_objs(front_idx, :);
    front_pop = pop(front_idx, :);
    raw_front = size(front_objs, 1);
    unique_front = count_unique_front_objs(front_objs);
    min_objs = min(front_objs, [], 1);

    rep_idx = select_fork_baseline_compromise_index(front_objs);
    compromise = front_objs(rep_idx, :);
    compromise_load = histcounts(front_pop(rep_idx, num_tasks+1:end), 1:num_agvs+1);

    [~, best_time_idx] = min(front_objs(:, 2));
    best_time = front_objs(best_time_idx, :);
    best_time_load = histcounts(front_pop(best_time_idx, num_tasks+1:end), 1:num_agvs+1);
    [front_levels, front_sizes_str] = summarize_front_layers(fronts);

    if strcmp(phase, 'gen')
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end
    fprintf('      [%s] %-5s | frontLevels=%d | frontSizes=%s\n', ...
        tag, phase, front_levels, front_sizes_str);

    fprintf('      [%s] %-5s | compromiseLoad=%s | bestTime=[%.1f %.1f %.3f] | bestTimeLoad=%s\n', ...
        tag, phase, mat2str(compromise_load), best_time(1), best_time(2), best_time(3), mat2str(best_time_load));
    fprintf('      [%s] %-5s | immigrants=%d | replaced=%d | stall=%d\n', ...
        tag, phase, stats.immigrants, stats.replaced, stats.stall);
end

function [front_levels, front_sizes_str] = summarize_front_layers(fronts)
    front_levels = numel(fronts);
    if front_levels == 0
        front_sizes_str = '[]';
        return;
    end

    front_sizes = zeros(1, front_levels);
    for i = 1:front_levels
        front_sizes(i) = numel(fronts{i});
    end
    front_sizes_str = mat2str(front_sizes);
end
