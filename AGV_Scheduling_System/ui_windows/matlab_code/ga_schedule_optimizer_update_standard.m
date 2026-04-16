function [best_schedule, batch_details, metrics, history, pareto_fronts] = ga_schedule_optimizer_update_standard(task_list, num_agvs, depots, agv_params, ga_params, agv_types)

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
        disp('   -> 启动 NSGA-II 引擎优化托举车 (多目标: 距离、时间、能耗)...');
        
        eval_lift_moo = @(chrom) cost_func_lift_moo(chrom, tasks_lift, agvs_lift, depots, agv_params, path_oracle);
        
        [pop_lift, objs_lift, fronts_lift, ~, hist_lift_dist, hist_lift_time, hist_lift_energy,gen_fronts_lift] = run_sub_nsga2_lift(tasks_lift, length(agvs_lift), ga_params, eval_lift_moo);
        
        front1_idx = fronts_lift{1}; 
        front1_objs = objs_lift(front1_idx, :);
        min_front1_lift_objs = min(front1_objs, [], 1);
        
        % TOPSIS 妥协决策机制
        best_idx_in_front1 = select_compromise_index(front1_objs);
        best_lift_chrom = pop_lift(front1_idx(best_idx_in_front1), :);
        
        [sched_lift, ~, batch_info_lift] = eval_lift_moo(best_lift_chrom);
        dist_lift = min_front1_lift_objs(1);          
        time_lift = min_front1_lift_objs(2);          
        energy_lift = min_front1_lift_objs(3);        
        
        for i = 1:length(agvs_lift)
            best_schedule{agvs_lift(i)} = sched_lift{i};
            batch_details{agvs_lift(i)} = batch_info_lift{i}; 
        end
    end 
    %% 叉车式AGV相关操作   
    % --- 2. 叉车：全面升级为三维目标 (距离、时间、能耗) ---
    if ~isempty(tasks_fork) && ~isempty(agvs_fork)
        disp('   -> 启动 NSGA-II 引擎优化叉车 (多目标: 距离、时间、能耗)...');
        eval_fork_moo = @(chrom) cost_func_fork_moo(chrom, tasks_fork, agvs_fork, depots, agv_params, path_oracle);
        
        % 接收新增的能耗历史输出
        [pop_fork, objs_fork, fronts_fork, ~, hist_fork_dist, hist_fork_time, hist_fork_energy,gen_fronts_fork] = run_sub_nsga2_fork(tasks_fork, length(agvs_fork), ga_params, eval_fork_moo);
        
        % TOPSIS 妥协决策机制
        front1_idx = fronts_fork{1}; 
        front1_objs = objs_fork(front1_idx, :);
        
        best_idx_in_front1 = select_fork_compromise_index( ...
            front1_objs, pop_fork(front1_idx, :), size(tasks_fork, 1), length(agvs_fork));      
        best_fork_chrom = pop_fork(front1_idx(best_idx_in_front1), :);
        
        [sched_fork, best_objs_fork] = eval_fork_moo(best_fork_chrom);
        dist_fork = best_objs_fork(1);          
        time_fork = best_objs_fork(2);          
        energy_fork = best_objs_fork(3); 
        
        for i = 1:length(agvs_fork)
            best_schedule{agvs_fork(i)} = sched_fork{i};
        end
    end
    %% === 统一打包输出，结构体降维 ===
    % 1. 打包最终稳态指标 (Metrics)
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
% 函数功能：运行子种群NSGA-II算法（针对带提升操作的AGV任务调度）
% 输入参数：
%   tasks          - 任务矩阵，每一行代表一个任务的信息
%   num_sub_agvs   - 子AGV的数量（即车辆数）
%   ga_params      - 结构体，包含遗传算法的参数（pop_size种群大小，max_gen最大代数）
%   eval_func      - 函数句柄，用于评估个体，返回[~, obj]其中obj=[距离,时间,能量]
% 输出参数：
%   pop             - 最终种群（大小为pop_size × (2*任务数)）
%   pop_objs        - 最终种群的目标值矩阵（pop_size × 3）
%   fronts          - 最终种群的非支配前沿（元胞数组）
%   cd              - 最终种群的拥挤距离向量
%   dist_hist       - 每代Pareto前沿中最小距离的历史记录（1×max_gen）
%   time_hist       - 每代Pareto前沿中最小时间的历史记录
%   energy_hist     - 每代Pareto前沿中最小能量的历史记录
%   gen_fronts_history - 元胞数组，保存每一代第一前沿所有个体的目标值（用于后期分析）
% =========================================================================
   
    % 获取任务数量（即任务矩阵的行数）
    num_tasks = size(tasks, 1);
    % 从ga_params结构体中提取种群大小
    pop_size = ga_params.pop_size;
    % 从ga_params结构体中提取最大迭代代数
    max_gen = ga_params.max_gen;

    % 初始化历史记录数组：距离、时间、能量，每个都是1×max_gen的行向量，初始全0
    dist_hist = zeros(1, max_gen);
    time_hist = zeros(1, max_gen);
    energy_hist = zeros(1, max_gen);

    % 定义交叉概率的自适应范围：最大交叉率0.6，最小交叉率0.3
    pc_max = 0.6; pc_min = 0.3;
    % 定义变异概率的自适应范围：最大变异率0.2，最小变异率0.05
    pm_max = 0.2; pm_min = 0.05;

    % 预分配内存，用于存储每一代第一前沿的所有个体的目标值，提升运行速度
    gen_fronts_history = cell(1, max_gen); 
    max_obj_copies = 1;
    stagnation_counter = 0;
    last_signature = [];
    log_interval = max(1, ceil(max_gen / 20));

    %% 1.1 - 初始化种群
    % 种群矩阵 pop：大小为 pop_size × (2*num_tasks)
    % 每一行代表一个个体，编码方式：
    %   前 num_tasks 个基因：任务的访问顺序（1..num_tasks 的一个排列）
    %   后 num_tasks 个基因：每个任务分配的AGV编号（1..num_sub_agvs 的整数）
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        % 随机生成任务的访问顺序（排列）
        pop(i, 1:num_tasks) = randperm(num_tasks);
        % 随机为每个任务分配AGV（1到num_sub_agvs之间的随机整数）
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end

    %% 1.2 - 初始化评估（计算初始种群的目标值）
    % pop_objs：种群中每个个体的三个目标值（距离、时间、能量），大小为 pop_size × 3
    pop_objs = zeros(pop_size, 3);
    for i = 1:pop_size
        % 调用外部评估函数 eval_func，传入个体编码，得到该个体的目标值obj
        [~, obj] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;   % 存储三个目标值
    end

    % 对初始种群进行快速非支配排序，返回：
    %   fronts - 元胞数组，每个元素包含属于同一前沿的个体索引
    %   rank   - 每个个体所属的前沿编号（1为最优前沿，数值越小越优）
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    last_signature = quantize_moo_objectives(min(pop_objs(fronts{1}, :), [], 1));
    log_nsga_start('EXPSTD-LIFT', num_tasks, num_sub_agvs, pop_size, max_gen, log_interval);
    log_lift_front_summary('EXPSTD-LIFT', 'init', 0, max_gen, pop_objs, fronts{1}, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', stagnation_counter));
    % 计算每个个体的拥挤距离（基于目标空间），用于维持种群多样性
    cd = calc_crowding_distance(pop_objs, fronts);

    %% 主循环：进化迭代
    for gen = 1:max_gen
        % 初始化子代种群矩阵（大小与父代相同）
        offspring = zeros(pop_size, num_tasks * 2);

        % 计算当前种群的平均前沿等级（rank值）和最小前沿等级
        avg_rank = mean(rank);
        min_rank = min(rank);

        % 构建多目标排序依据：先按前沿等级rank升序，再按拥挤距离-cd降序（即距离大的优先）
        sort_criteria = [rank, -cd];
        % 对种群个体按上述标准排序，得到排序后的索引 sorted_moo_idx
        [~, sorted_moo_idx] = sortrows(sort_criteria);

        % 初始化 moo_ranks 向量，用于存储个体在多目标排序中的全局顺序（1为最好，pop_size为最差）
        moo_ranks = zeros(pop_size, 1);
        % 将排序后的位置赋值给对应个体：排在第一位（最好）的个体得到 moo_rank = 1
        moo_ranks(sorted_moo_idx) = 1:pop_size;

        % 采用锦标赛选择法产生子代，每次选两个父代，生成两个子代，直到填满 offspring
        i = 1;   % 子代计数索引
        while i <= pop_size
            % 通过锦标赛选择（基于rank和cd）选出第一个父代索引
            p1_idx = tournament_select_nsga2(rank, cd);
            % 选出第二个父代索引
            p2_idx = tournament_select_nsga2(rank, cd);
            % 初始子代设为父代个体的副本（后续根据交叉变异决定是否修改）
            child1 = pop(p1_idx, :);
            child2 = pop(p2_idx, :);

            % 获取两个父代的rank值
            rank_p1 = rank(p1_idx);
            rank_p2 = rank(p2_idx);
            % 取两个父代中较优的rank（数值较小）作为“better_rank”，用于自适应交叉率
            better_rank = min(rank_p1, rank_p2);

            % --- 自适应交叉概率 ---
            % 如果较优父代的rank不差于平均rank（即rank值 <= 平均rank），说明个体质量较好，
            % 此时交叉概率随rank值线性变化：rank越低（越好），交叉率越高（从pc_min到pc_max）
            if better_rank <= avg_rank
                pc = pc_max - (pc_max - pc_min) * (better_rank - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                % 如果较优父代的rank比平均rank差，则使用最大交叉率，以增强探索
                pc = pc_min;
            end

            % --- 自适应变异概率（分别对两个父代）---
            % 对于第一个父代，若其rank不差于平均rank，变异率随rank线性增加（越好的个体变异率越小）
            if rank_p1 <= avg_rank
                pm1 = pm_min + (pm_max - pm_min) * (rank_p1 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm1 = pm_max;   % 较差的个体使用最大变异率，增加扰动
            end
            % 同理计算第二个父代的变异率
            if rank_p2 <= avg_rank
                pm2 = pm_min + (pm_max - pm_min) * (rank_p2 - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pm2 = pm_max;
            end

            % --- 交叉操作 ---
            % 如果随机数小于当前交叉概率pc，则对两个父代进行 IPOX-MPX 交叉（一种针对任务排序和分配的特殊交叉）
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks);
            end
            % 注意：若未交叉，则child1,child2保留为父代副本

            % --- 变异操作 ---
            % 对第一个子代：如果随机数小于变异率pm1，则执行 fork-CPO 变异（一种结合任务顺序和AGV分配的变异）
            % 变异函数传入参数：子代个体、任务数、AGV数、变异率、当前代数、最大代数、父代的moo排名、种群大小
            if rand < pm1
                child1 = mutate_fork_cpo(child1, num_tasks, num_sub_agvs, pm1, gen, max_gen, moo_ranks(p1_idx), pop_size, eval_func);
            end
            % 对第二个子代同样操作
            if rand < pm2
                child2 = mutate_fork_cpo(child2, num_tasks, num_sub_agvs, pm2, gen, max_gen, moo_ranks(p2_idx), pop_size, eval_func);
            end

            % 将生成的两个子代存入 offspring 矩阵
            offspring(i, :) = child1;
            % 确保不越界（当pop_size为奇数时，最后一轮可能只有一个子代）
            if i+1 <= pop_size
                offspring(i+1, :) = child2;
            end
            % 子代索引前进2（每次生成两个子代）
            i = i + 2;
        end

        % --- 评估子代种群的目标值 ---
        off_objs = zeros(pop_size, 3);
        for i = 1:pop_size
            [~, obj] = eval_func(offspring(i,:));
            off_objs(i,:) = obj;
        end

        % --- 合并父代与子代，形成大小为 2*pop_size 的临时种群 ---
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        prev_unique_front = count_unique_front_objs(pop_objs(fronts{1}, :));
        immigrants_count = determine_lift_immigrant_count(prev_unique_front, stagnation_counter, pop_size);
        if immigrants_count > 0
            [immigrant_pop, immigrant_objs] = generate_random_population_moo(immigrants_count, num_tasks, num_sub_agvs, eval_func);
            combined_pop = [combined_pop; immigrant_pop];
            combined_objs = [combined_objs; immigrant_objs];
        end

        % 对合并后的种群进行快速非支配排序
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        % 计算合并种群的拥挤距离
        c_cd = calc_crowding_distance(combined_objs, c_fronts);

        % --- 环境选择：从合并种群中选出 pop_size 个个体构成下一代种群 ---
        % 清空 pop 和 pop_objs 以重新填充
        pop = zeros(pop_size, num_tasks * 2);
        pop_objs = zeros(pop_size, 3);
        current_idx = 1;      % 当前已选择的个体数量指针
        f = 1;                 % 前沿索引

        % 按照前沿等级从低到高依次选择个体，直到填满新种群
        while current_idx <= pop_size && f <= length(c_fronts)
            front = c_fronts{f};   % 当前前沿的所有个体索引
            % 如果当前前沿的所有个体都能被完整加入新种群而不超出大小
            if current_idx + length(front) - 1 <= pop_size
                % 将该前沿的所有个体直接加入
                pop(current_idx : current_idx + length(front) - 1, :) = combined_pop(front, :);
                pop_objs(current_idx : current_idx + length(front) - 1, :) = combined_objs(front, :);
                current_idx = current_idx + length(front);
            else
                % 如果当前前沿只能部分加入，则根据拥挤距离降序排序，选择距离最大的个体填充剩余位置
                [~, sort_idx] = sort(c_cd(front), 'descend');
                num_needed = pop_size - current_idx + 1;   % 还需要选择的个体数
                selected_front = front(sort_idx(1:num_needed));   % 选择拥挤距离最大的前num_needed个

                % 将选中的个体放入新种群
                pop(current_idx : end, :) = combined_pop(selected_front, :);
                pop_objs(current_idx : end, :) = combined_objs(selected_front, :);
                break;   % 已填满，退出循环
            end
            f = f + 1;   % 移动到下一个前沿
        end

        % --- 对新一代种群重新进行非支配排序和拥挤距离计算 ---
        replaced_count = 0;
        if prev_unique_front <= 4 || mod(gen, 6) == 0 || stagnation_counter >= 8
            [pop, pop_objs, replaced_count] = reduce_population_duplicates_moo(pop, pop_objs, num_tasks, num_sub_agvs, eval_func, max_obj_copies);
        end
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);

        % --- 记录本代第一前沿（Pareto最优前沿）的三个目标的最小值 ---
        front1 = fronts{1};
        min_objs_in_front = min(pop_objs(front1, :), [], 1); 
        
        % 分别记录三个目标的最小值
        dist_hist(gen) = min_objs_in_front(1);
        time_hist(gen) = min_objs_in_front(2);
        energy_hist(gen) = min_objs_in_front(3);

        % 【新增】：保存这一代的第一前沿所有解的目标值 (N × 3 矩阵)，用于后续分析或绘图
        gen_fronts_history{gen} = pop_objs(front1, :);
        current_signature = quantize_moo_objectives(min_objs_in_front);
        if isequal(current_signature, last_signature)
            stagnation_counter = stagnation_counter + 1;
        else
            stagnation_counter = 0;
            last_signature = current_signature;
        end

        if should_log_iteration(gen, max_gen, log_interval)
            log_lift_front_summary('EXPSTD-LIFT', 'gen', gen, max_gen, pop_objs, front1, ...
                struct('immigrants', immigrants_count, 'replaced', replaced_count, 'stall', stagnation_counter));
        end
    end
    log_lift_front_summary('EXPSTD-LIFT', 'done', max_gen, max_gen, pop_objs, fronts{1}, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', stagnation_counter));
    % 主循环结束

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
    
    pc_max = 0.78; pc_min = 0.42;  
    pm_max = 0.12; pm_min = 0.035; 
    max_obj_copies = 1;
    stagnation_counter = 0;
    last_signature = [];
    % 【新增】：预分配内存，提升运行速度
    gen_fronts_history = cell(1, max_gen);
    log_interval = max(1, ceil(max_gen / 20));
    %% 初始化种群
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end    
    
    %% 初始化评估 (变更为 3 维)
    pop_objs = zeros(pop_size, 3); 
    for i = 1:pop_size
        [~, obj] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;
    end    
    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);
    last_signature = min(pop_objs(fronts{1}, :), [], 1);
    log_nsga_start('EXPSTD-FORK', num_tasks, num_sub_agvs, pop_size, max_gen, log_interval);
    log_fork_front_summary('EXPSTD-FORK', 'init', 0, max_gen, pop, pop_objs, fronts{1}, num_tasks, num_sub_agvs, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', stagnation_counter));
    
    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);
        avg_rank = mean(rank);
        min_rank = min(rank); 
        % 与托举子问题保持一致：基于 NSGA-II 的 rank + crowding distance 生成多目标排序
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
            
            % 自适应概率
            if better_rank <= avg_rank
                pc = pc_max - (pc_max - pc_min) * (better_rank - min_rank) / (avg_rank - min_rank + 1e-6);
            else
                pc = pc_min;
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
            
            % 交叉 (保留原有的 IPOX_MPX)
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks); 
            end
            
            % 变异 (调用 CPO 算子，使用多目标排序而非单距离排序)
            if rand < pm1
                child1 = mutate_fork_cpo(child1, num_tasks, num_sub_agvs, pm1, gen, max_gen, moo_ranks(p1_idx), pop_size, eval_func); 
            end
            if rand < pm2
                child2 = mutate_fork_cpo(child2, num_tasks, num_sub_agvs, pm2, gen, max_gen, moo_ranks(p2_idx), pop_size, eval_func); 
            end
            
            offspring(i,:) = child1;
            if i+1 <= pop_size, offspring(i+1,:) = child2; end
            i = i + 2;
        end        
        
        % 评估子代 (变更为 3 维)
        off_objs = zeros(pop_size, 3);
        for i = 1:pop_size
            [~, obj] = eval_func(offspring(i,:));
            off_objs(i,:) = obj;
        end
        
        % 合并与非支配排序
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        prev_unique_front = count_unique_front_objs(pop_objs(fronts{1}, :));
        immigrants_count = determine_fork_immigrant_count(prev_unique_front, stagnation_counter, pop_size);
        if immigrants_count > 0
            [immigrant_pop, immigrant_objs] = generate_random_population_moo(immigrants_count, num_tasks, num_sub_agvs, eval_func);
            combined_pop = [combined_pop; immigrant_pop];
            combined_objs = [combined_objs; immigrant_objs];
        end
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);
        
        % 精英截断 (变更为 3 维)
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
        
        replaced_count = 0;
        if prev_unique_front <= 3 || mod(gen, 5) == 0 || stagnation_counter >= 10
            [pop, pop_objs, replaced_count] = reduce_population_duplicates_moo(pop, pop_objs, num_tasks, num_sub_agvs, eval_func, max_obj_copies);
        end
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);
        
        % 记录收敛曲线
        front1 = fronts{1};
        min_objs_in_front = min(pop_objs(front1, :), [], 1); 
        
        % 分别记录三个目标的最小值
        dist_hist(gen) = min_objs_in_front(1);
        time_hist(gen) = min_objs_in_front(2);
        energy_hist(gen) = min_objs_in_front(3);
        % 【新增】：保存这一代的第一前沿所有解的目标值 (N x 3 矩阵)
        gen_fronts_history{gen} = pop_objs(front1, :);
        if all(abs(min_objs_in_front - last_signature) <= 1e-9)
            stagnation_counter = stagnation_counter + 1;
        else
            stagnation_counter = 0;
            last_signature = min_objs_in_front;
        end
        if should_log_iteration(gen, max_gen, log_interval)
            log_fork_front_summary('EXPSTD-FORK', 'gen', gen, max_gen, pop, pop_objs, front1, num_tasks, num_sub_agvs, ...
                struct('immigrants', immigrants_count, 'replaced', replaced_count, 'stall', stagnation_counter));
        end
    end
    log_fork_front_summary('EXPSTD-FORK', 'done', max_gen, max_gen, pop, pop_objs, fronts{1}, num_tasks, num_sub_agvs, ...
        struct('immigrants', 0, 'replaced', 0, 'stall', stagnation_counter));
end

%% 公共函数
function cd = calc_crowding_distance(pop_objs, fronts)
    pop_size = size(pop_objs, 1);
    num_objs = size(pop_objs, 2);
    cd = zeros(pop_size, 1);

    for f = 1:length(fronts)
        front = fronts{f};
        l = length(front);
        
        % 如果该面只有 1 或 2 个个体，直接设为无穷大
        if l <= 2
            cd(front) = inf;
            continue;
        end
        
        % 对每一个目标维度独立计算距离并累加
        for m = 1:num_objs
            [sorted_objs, idx] = sort(pop_objs(front, m));
            sorted_front = front(idx);
            
            % 边界个体拥挤度设为无穷大，确保其被保留
            cd(sorted_front(1)) = inf;
            cd(sorted_front(end)) = inf;
            
            f_min = sorted_objs(1);
            f_max = sorted_objs(end);
            
            if f_max - f_min == 0, continue; end % 防止除以 0
            
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
    
    % 规则 1：等级低的优先 (帕累托层面靠前)
    if rank(i1) < rank(i2)
        idx = i1;
    elseif rank(i1) > rank(i2)
        idx = i2;
    else
        % 规则 2：等级相同时，拥挤度大的优先 (保护多样性)
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
    domination_count = zeros(pop_size, 1); % 记录被多少人支配 (n_p)
    dominated_set = cell(pop_size, 1);     % 记录支配了哪些人 (S_p)
    rank = zeros(pop_size, 1);

    for i = 1:pop_size
        for j = 1:pop_size
            if i == j, continue; end
            % 支配条件：i 的所有目标都 <= j，且至少有一个目标 < j
            if all(pop_objs(i,:) <= pop_objs(j,:)) && any(pop_objs(i,:) < pop_objs(j,:))
                dominated_set{i} = [dominated_set{i}, j];
            elseif all(pop_objs(j,:) <= pop_objs(i,:)) && any(pop_objs(j,:) < pop_objs(i,:))
                domination_count(i) = domination_count(i) + 1;
            end
        end
        % 如果不被任何人支配，则属于第一前沿 (Rank 1)
        if domination_count(i) == 0
            rank(i) = 1;
            fronts{1} = [fronts{1}, i];
        end
    end

    % 逐层剥离构建后续前沿面
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
    fronts(cellfun(@isempty, fronts)) = []; % 清除空的前沿
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

function child = mutate_fork_cpo(chrom, num_tasks, num_agvs, pm, g, G, parent_rank_idx, PN, eval_func)
% =========================================================================
% 函数功能：多策略自适应变异算子（Fork-CPO变异，结合了探索与开发策略）
% 输入参数：
%   chrom          - 父代染色体向量，长度为 2*num_tasks
%   num_tasks      - 任务数量
%   num_agvs       - AGV数量
%   pm             - 基础变异概率（用于最后的强制负载均衡）
%   g              - 当前进化代数（从1开始）
%   G              - 最大进化代数
%   parent_rank_idx- 父代个体在多目标排序中的全局排名（1~PN，1表示最好）
%   PN             - 种群大小（pop_size）
% 输出参数：
%   child          - 变异后的子代染色体
% =========================================================================
    child = chrom;                       % 先复制父代，后续根据条件修改
    if num_tasks < 2
        return;
    end

    % 生成两个随机数 tau1 和 tau2，用于判断进入探索还是开发分支
    tau1 = rand(); 
    tau2 = rand();

    % tau1_prime 是 tau1 减去一个与进化代数相关的衰减项
    % 随着代数增加，0.3*(1 - g/G) 逐渐增大（从0.3到0），使得 tau1_prime 逐渐变小
    % 目的是：进化后期更倾向于进入 else 分支（开发策略）
    tau1_prime = tau1 - 0.3 * (1 - g/G); 

    % 判断分支：若 tau1_prime < tau2 则进入探索策略（exploration），否则进入开发策略（exploitation）
    if tau1_prime < tau2
        % ====== 探索策略（针对排名较后的个体，增加种群多样性） ======
        % 根据父代排名决定使用哪种探索操作
        if parent_rank_idx > 0.6 * PN
            % 1. 视觉防御：基因块翻转（强烈破坏，适用于排名靠后的个体）
            % 随机选择两个不同的位置，作为翻转区间的端点
            range = sort(randperm(num_tasks, 2));      % range(1) <= range(2)
            % 将任务序列中该区间的顺序反转（fliplr）
            child(range(1):range(2)) = fliplr(child(range(1):range(2)));
            % 注意：只翻转任务顺序，不改变AGV指派，AGV部分保持不变
        else
            % 2. 声音防御：跨车交换（改变AGV指派组合，但保持任务顺序不变）
            % 随机选择两个不同的任务位置（在任务序列中的索引）
            pos = randperm(num_tasks, 2);
            % 对应的AGV指派位置（在后半段染色体中）
            agv_pos = pos + num_tasks;

            % 仅仅交换这两个任务的AGV指派编号
            ta = child(agv_pos(1)); 
            child(agv_pos(1)) = child(agv_pos(2)); 
            child(agv_pos(2)) = ta;
            % 任务序列本身（前半段）不做任何改变
        end
    else
        % ====== 开发策略（针对排名优秀的个体，局部精细搜索） ======
        if parent_rank_idx > 0.2 * PN
            % 3. 气味防御：插入变异（模拟任务插队，优秀的局部寻优）
            % 随机选择两个不同的任务位置：提取点 extract_idx 和插入点 insert_idx
            pts = randperm(num_tasks, 2);
            extract_idx = pts(1); 
            insert_idx = pts(2);

            % 提取该位置的任务ID和对应的AGV指派
            extracted_task = child(extract_idx);
            extracted_agv = child(extract_idx + num_tasks);

            % 从任务序列中删除该任务（删除一个元素后，后面的元素向前移动）
            child(extract_idx) = []; 
            % 由于任务序列少了一个元素，对应的AGV指派序列也要删除相同位置（注意索引已变）
            % 此时任务序列长度为 num_tasks-1，对应的AGV指派序列起始索引为 num_tasks（原后半段整体前移了一位）
            % 原 extract_idx + num_tasks 现在变成了 extract_idx + num_tasks - 1
            child(extract_idx + num_tasks - 1) = [];

            % 重新插入：将提取的任务和其AGV指派插入到新的位置
            % 构造新染色体：
            % 前半部分（任务序列）：[1:insert_idx-1] 保持，然后插入 extracted_task，再接着原序列的 insert_idx 到末尾
            % 后半部分（AGV指派）：前半部分之后紧接着的是AGV指派部分
            % 由于任务序列长度恢复为 num_tasks，AGV指派序列的起始索引应为 num_tasks + 1
            % 这里用两个拼接：先拼接前半部分的任务和AGV部分，再拼接后半部分的任务和AGV部分
            % 注意：原 child 此时已经是删除后的状态，长度为 2*(num_tasks-1)
            % 插入后长度恢复为 2*num_tasks
            child = [child(1:insert_idx-1), extracted_task, child(insert_idx:num_tasks-1), ...
                     child(num_tasks:num_tasks+insert_idx-2), extracted_agv, child(num_tasks+insert_idx-1:end)];
            % 解释：
            %   child(1:insert_idx-1)                 : 插入点前的任务序列
            %   extracted_task                          : 插入的任务
            %   child(insert_idx:num_tasks-1)          : 插入点后的任务序列（原剩余任务）
            %   child(num_tasks:num_tasks+insert_idx-2): 插入点前的AGV指派序列
            %   extracted_agv                            : 插入的AGV指派
            %   child(num_tasks+insert_idx-1:end)       : 插入点后的AGV指派序列
        else
            % 4. 物理攻击：瓶颈定向转移（针对最精英的个体，微调AGV负载）
            % 计算AGV指派部分的索引范围
            agv_idx = (num_tasks + 1) : (2 * num_tasks);
            current_agvs = child(agv_idx);      % 当前的AGV指派向量

            % 统计每个AGV被分配的任务数量（粗略代表负载）
            counts = histcounts(current_agvs, 1:num_agvs+1);  % 返回长度为 num_agvs 的计数数组

            [~, max_agv] = max(counts);         % 找出任务数最多的AGV（负载最大）
            [~, min_agv] = min(counts);         % 找出任务数最少的AGV（负载最小）

            % 找出负载最大的AGV所承担的所有任务的位置索引
            heavy_tasks_idx = find(current_agvs == max_agv);

            if (counts(max_agv) - counts(min_agv)) >= 2 && ~isempty(heavy_tasks_idx)
                % 优先转移重载车序列靠后的任务，直接压低瓶颈车完工时间
                transfer_idx = choose_best_fork_transfer(child, num_tasks, heavy_tasks_idx, min_agv, eval_func);
                child(num_tasks + transfer_idx) = min_agv;
            end
            % 注意：此处仅改变AGV指派，不改变任务执行顺序，以保护精英个体的优良路径结构
        end
    end

    % ====== 底层的强制负载均衡机制（作为最后一道安全网）======
    % 以略高于基础变异率的概率（pm+0.05）执行一次强制均衡
    if rand < (pm + 0.05)
        agv_idx = (num_tasks + 1) : (2 * num_tasks);
        current_agvs = child(agv_idx);          % 当前的AGV指派

        % 重新统计各AGV的任务数量
        counts = zeros(1, num_agvs);
        for k = 1:num_agvs
            counts(k) = sum(current_agvs == k);
        end
        [max_val, max_agv] = max(counts);
        [min_val, min_agv] = min(counts);
        if (max_val - min_val) >= 2
            heavy_tasks_idx = find(current_agvs == max_agv);
            if ~isempty(heavy_tasks_idx)
                % 末尾任务通常更接近拖慢当前瓶颈车，优先将其迁移
                transfer_idx = choose_best_fork_transfer(child, num_tasks, heavy_tasks_idx, min_agv, eval_func);
                child(num_tasks + transfer_idx) = min_agv;
            end
        end
    end
end

function [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks)
    if num_tasks < 2
        child1 = p1;
        child2 = p2;
        return;
    end
    % 初始化子代
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

function idx = select_fork_compromise_index(front_objs, front_pop, num_tasks, num_agvs)
    if isempty(front_objs)
        idx = 1;
        return;
    end

    % 对时间目标给予更高权重，避免只为少量距离/能耗收益牺牲大量完工时间
    min_objs = min(front_objs, [], 1);
    max_objs = max(front_objs, [], 1);
    obj_norm = (front_objs - min_objs) ./ (max_objs - min_objs + 1e-9);
    obj_weights = [0.28, 0.50, 0.22];
    ideal_best = min(obj_norm, [], 1);
    ideal_worst = max(obj_norm, [], 1);
    d_best = sqrt(sum(((obj_norm - ideal_best) .* obj_weights).^2, 2));
    d_worst = sqrt(sum(((obj_norm - ideal_worst) .* obj_weights).^2, 2));
    closeness = d_worst ./ (d_best + d_worst + 1e-9);

    if nargin < 4 || isempty(front_pop)
        [~, idx] = max(closeness);
        return;
    end

    % 在折中度相近时，额外偏好任务分配更均衡的解
    assign_mat = front_pop(:, num_tasks+1:end);
    count_span = zeros(size(assign_mat, 1), 1);
    count_std = zeros(size(assign_mat, 1), 1);
    for i = 1:size(assign_mat, 1)
        counts = histcounts(assign_mat(i, :), 1:num_agvs+1);
        count_span(i) = max(counts) - min(counts);
        count_std(i) = std(counts);
    end

    if max(count_span) > min(count_span)
        span_norm = (count_span - min(count_span)) ./ (max(count_span) - min(count_span));
    else
        span_norm = zeros(size(count_span));
    end

    if max(count_std) > min(count_std)
        std_norm = (count_std - min(count_std)) ./ (max(count_std) - min(count_std));
    else
        std_norm = zeros(size(count_std));
    end

    balance_score = 1 - 0.7 * span_norm - 0.3 * std_norm;
    combined_score = 0.985 * closeness + 0.015 * balance_score;
    [~, idx] = max(combined_score);
end

function transfer_idx = choose_best_fork_transfer(chrom, num_tasks, heavy_tasks_idx, target_agv, eval_func)
    candidate_positions = heavy_tasks_idx(max(1, end - min(2, length(heavy_tasks_idx) - 1)):end);
    transfer_idx = candidate_positions(end);
    best_score = [inf, inf, inf];

    for i = 1:length(candidate_positions)
        trial = chrom;
        trial_idx = candidate_positions(i);
        trial(num_tasks + trial_idx) = target_agv;
        [~, trial_obj] = eval_func(trial);
        trial_score = [trial_obj(2), trial_obj(1), trial_obj(3)];
        if lexicographic_less(trial_score, best_score)
            best_score = trial_score;
            transfer_idx = trial_idx;
        end
    end
end

function [pop, pop_objs, replaced_count] = reduce_population_duplicates_moo(pop, pop_objs, num_tasks, num_agvs, eval_func, max_obj_copies)
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
            [~, obj] = eval_func(pop(idx, :));
            pop_objs(idx, :) = obj;
            replaced_count = replaced_count + 1;
        end
    end
end

function [rand_pop, rand_objs] = generate_random_population_moo(count, num_tasks, num_agvs, eval_func)
    rand_pop = zeros(count, num_tasks * 2);
    rand_objs = zeros(count, 3);
    for i = 1:count
        rand_pop(i, 1:num_tasks) = randperm(num_tasks);
        rand_pop(i, num_tasks+1:end) = randi([1, num_agvs], 1, num_tasks);
        [~, obj] = eval_func(rand_pop(i, :));
        rand_objs(i, :) = obj;
    end
end

function immigrants_count = determine_fork_immigrant_count(unique_front, stagnation_counter, pop_size)
    immigrants_count = 0;
    if unique_front <= 2
        immigrants_count = max(6, ceil(0.08 * pop_size));
    elseif unique_front <= 4
        immigrants_count = max(3, ceil(0.04 * pop_size));
    end

    if stagnation_counter >= 12
        immigrants_count = max(immigrants_count, ceil(0.10 * pop_size));
    elseif stagnation_counter >= 6
        immigrants_count = max(immigrants_count, ceil(0.06 * pop_size));
    end

    if stagnation_counter > 0 && mod(stagnation_counter, 3) ~= 0
        immigrants_count = min(immigrants_count, 2);
    elseif stagnation_counter >= 4
        immigrants_count = max(immigrants_count, ceil(0.04 * pop_size));
    end
end

function immigrants_count = determine_lift_immigrant_count(unique_front, stagnation_counter, pop_size)
    immigrants_count = 0;
    if unique_front <= 2
        immigrants_count = max(4, ceil(0.05 * pop_size));
    elseif unique_front <= 4
        immigrants_count = max(2, ceil(0.03 * pop_size));
    end

    if stagnation_counter >= 12
        immigrants_count = max(immigrants_count, ceil(0.08 * pop_size));
    elseif stagnation_counter >= 6
        immigrants_count = max(immigrants_count, ceil(0.05 * pop_size));
    end

    if stagnation_counter > 0 && mod(stagnation_counter, 4) ~= 0
        immigrants_count = min(immigrants_count, 1);
    end
end

function unique_front = count_unique_front_objs(front_objs)
    unique_front = size(unique(quantize_moo_objectives(front_objs), 'rows'), 1);
end

function rounded_objs = quantize_moo_objectives(pop_objs)
    rounded_objs = [round(pop_objs(:, 1), 0), round(pop_objs(:, 2), 1), round(pop_objs(:, 3), 3)];
end

function tf = lexicographic_less(a, b)
    tf = false;
    for i = 1:numel(a)
        if a(i) < b(i) - 1e-9
            tf = true;
            return;
        elseif a(i) > b(i) + 1e-9
            return;
        end
    end
end

function tf = should_log_iteration(gen, max_gen, log_interval)
    tf = (gen == 1) || (gen == max_gen) || (mod(gen, log_interval) == 0);
end

function log_nsga_start(tag, num_tasks, num_agvs, pop_size, max_gen, log_interval)
    fprintf('      [%s] start | tasks=%d | agvs=%d | pop=%d | gen=%d | logInterval=%d\n', ...
        tag, num_tasks, num_agvs, pop_size, max_gen, log_interval);
end

function log_front_summary(tag, phase, gen, max_gen, pop_objs, front_idx, compromise_selector)
    front_objs = pop_objs(front_idx, :);
    raw_front = size(front_objs, 1);
    unique_front = size(unique(front_objs, 'rows'), 1);
    min_objs = min(front_objs, [], 1);
    rep_idx = compromise_selector(front_objs);
    compromise = front_objs(rep_idx, :);

    if strcmp(phase, 'gen')
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end
end

function log_lift_front_summary(tag, phase, gen, max_gen, pop_objs, front_idx, stats)
    if nargin < 7 || isempty(stats)
        stats = struct('immigrants', 0, 'replaced', 0, 'stall', 0);
    end
    front_objs = pop_objs(front_idx, :);
    raw_front = size(front_objs, 1);
    unique_front = count_unique_front_objs(front_objs);
    min_objs = min(front_objs, [], 1);
    rep_idx = select_compromise_index(front_objs);
    compromise = front_objs(rep_idx, :);

    if strcmp(phase, 'gen')
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end

    fprintf('      [%s] %-5s | immigrants=%d | replaced=%d | stall=%d\n', ...
        tag, phase, stats.immigrants, stats.replaced, stats.stall);
end

function log_fork_front_summary(tag, phase, gen, max_gen, pop, pop_objs, front_idx, num_tasks, num_agvs, stats)
    if nargin < 10 || isempty(stats)
        stats = struct('immigrants', 0, 'replaced', 0, 'stall', 0);
    end
    front_objs = pop_objs(front_idx, :);
    front_pop = pop(front_idx, :);
    raw_front = size(front_objs, 1);
    unique_front = size(unique(front_objs, 'rows'), 1);
    min_objs = min(front_objs, [], 1);

    rep_idx = select_fork_compromise_index(front_objs, front_pop, num_tasks, num_agvs);
    compromise = front_objs(rep_idx, :);
    compromise_load = histcounts(front_pop(rep_idx, num_tasks+1:end), 1:num_agvs+1);

    [~, best_time_idx] = min(front_objs(:, 2));
    best_time = front_objs(best_time_idx, :);
    best_time_load = histcounts(front_pop(best_time_idx, num_tasks+1:end), 1:num_agvs+1);

    if strcmp(phase, 'gen')
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end

    fprintf('      [%s] %-5s | compromiseLoad=%s | bestTime=[%.1f %.1f %.3f] | bestTimeLoad=%s\n', ...
        tag, phase, mat2str(compromise_load), best_time(1), best_time(2), best_time(3), mat2str(best_time_load));
    fprintf('      [%s] %-5s | immigrants=%d | replaced=%d | stall=%d\n', ...
        tag, phase, stats.immigrants, stats.replaced, stats.stall);
end
