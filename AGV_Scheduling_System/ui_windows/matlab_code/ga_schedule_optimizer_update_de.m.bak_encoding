function [best_schedule, batch_details, hist_lift, hist_fork, dist_lift, dist_fork] = ga_schedule_optimizer_update_de(task_list, num_agvs, depots, agv_params, weights, ga_params, agv_types)
%% 初始化参数    
    idx_lift_tasks = task_list(:,2) <= 12;
    % [数据剥离] 提取目标工位 ID <= 12 的任务逻辑索引（判定为小件/托举车专属任务）    
    idx_fork_tasks = task_list(:,2) > 12;
    % [数据剥离] 提取目标工位 ID > 12 的任务逻辑索引（判定为大件/叉车专属任务）    
    tasks_lift = task_list(idx_lift_tasks, :);
    % 利用逻辑索引，从总任务大盘中切分出纯净的“托举车任务池”   
    tasks_fork = task_list(idx_fork_tasks, :);
    % 利用逻辑索引，从总任务大盘中切分出纯净的“叉车任务池”    
    agvs_lift = find(agv_types == 1); 
    % 扫描全局 AGV 类型数组，获取所有托举车的真实物理 ID（如 [1, 2]）    
    agvs_fork = find(agv_types == 2); 
    % 扫描全局 AGV 类型数组，获取所有叉车的真实物理 ID（如 [3]）  
    best_schedule = cell(1, num_agvs);
    % 初始化最终输出的元胞数组，预留足够的空间存放所有车型的排班表
    batch_details = cell(1, num_agvs); 
    % 初始化批次详情输出容器
    % 【修复 4】：安全初始化输出变量，防止因为某类任务为空导致报错
    hist_lift = zeros(1, ga_params.max_gen);
    hist_fork = zeros(1, ga_params.max_gen);
    dist_lift = 0;
    dist_fork = 0;
%% 托举式AGV相关操作    
    % --- 1. 托举车：启用 NSGA-II 多目标引擎 ---
    if ~isempty(tasks_lift) && ~isempty(agvs_lift)
        % 防御性编程：只有当既有小件任务，又有托举车可用时，才启动此引擎    
        disp('   -> 启动 NSGA-II 引擎优化托举车 (多目标: 距离、时间、负载率)...');
        % 控制台打印日志，展示系统正在进行复杂的帕累托多目标寻优       
        eval_lift_moo = @(chrom) cost_func_lift_moo(chrom, tasks_lift, agvs_lift, depots, agv_params);
        % 定义匿名评价函数（闭包），把常量环境打包，只向底层算法暴露出染色体 chrom 作为入口    
        [pop_lift, objs_lift, fronts_lift, ~, hist_lift] = run_sub_nsga2_lift_with_de(tasks_lift, length(agvs_lift), ga_params, eval_lift_moo);
        % [核心调用] 唤醒 NSGA-II 引擎。输出最后一代的种群矩阵、三维目标值矩阵、以及非支配排序得到的前沿分层
        % (拥挤度数组在主函数后续不参与决策，故用 ~ 忽略以节省内存)
        front1_idx = fronts_lift{1}; 
        % 提取出绝对第一梯队（Rank 1 / 帕累托最优前沿）所有个体在种群中的局部索引     
        front1_objs = objs_lift(front1_idx, :);
        % 依据上述索引，提取出第一梯队所有个体的真实目标得分矩阵  
        % 【TOPSIS 妥协决策机制起始】
        min_objs = min(front1_objs, [], 1);
        max_objs = max(front1_objs, [], 1);
        obj_norm = (front1_objs - min_objs) ./ (max_objs - min_objs + 1e-6);
        compromise_scores = sqrt(sum(obj_norm.^2, 2));
        % 计算每个候选解到“乌托邦理想解（归一化后的原点[0,0,0]）”的欧几里得距离，代表综合妥协偏差        
        [~, best_idx_in_front1] = min(compromise_scores);
        % 在第一前沿中，挑出综合偏差得分最小（最折中、最均衡）的那个解的次级索引      
        best_lift_chrom = pop_lift(front1_idx(best_idx_in_front1), :);
        [sched_lift, best_objs_lift, batch_info_lift] = eval_lift_moo(best_lift_chrom);
        dist_lift = best_objs_lift(1); % f1 就是总距离
        % 拿着这个次级索引，反向追溯到全局种群库，提取出这个“天选之子”的染色体基因串        
        % 对天选染色体执行一次解码，剥离出其实际对应的局部任务排班表
        for i = 1:length(agvs_lift)
            best_schedule{agvs_lift(i)} = sched_lift{i};
            batch_details{agvs_lift(i)} = batch_info_lift{i}; % 【新增】：映射到全局输出
        end
    end
%% 叉车式AGV相关操作   
    % --- 2. 叉车：保留 HGA 单目标引擎 ---
    if ~isempty(tasks_fork) && ~isempty(agvs_fork)
    % 防御性编程：只有当既有大件任务，又有叉车可用时，才启动此引擎    
        disp('   -> 启动 HGA 引擎优化叉车 (单目标: 最短路径+时间惩罚)...');
        % 控制台打印日志，展示系统正在利用模拟退火和罚函数进行严格时间窗寻优      
        eval_fork = @(chrom) cost_func_fork(chrom, tasks_fork, agvs_fork, depots, agv_params, weights);
        % 定义变异算子的匿名函数，绑定叉车专属的“时间窗引导插队”启发式变异机制      
        [sched_fork, best_cost_fork, hist_fork] = run_sub_hga(tasks_fork, length(agvs_fork), ga_params, eval_fork);
        dist_fork = best_cost_fork;
        % [核心调用] 唤醒 HGA 单目标引擎。由于是单目标，直接返回最优秀个体的解码排班表即可      
        for i = 1:length(agvs_fork)
            best_schedule{agvs_fork(i)} = sched_fork{i};
        % 映射缝合：将叉车的局部排班表，准确地填回全局最佳调度表对应的真实物理车号中
        end
    end
end
%% 托举式AGV相关函数
function [pop, pop_objs, fronts, cd, dist_hist] = run_sub_nsga2_lift_with_de(tasks, num_sub_agvs, ga_params, eval_func)
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    dist_hist = zeros(1, max_gen);
    pc_max = 0.8; pc_min = 0.6;  % 交叉概率范围
    pm_max = 0.2; pm_min = 0.05; % 变异概率范围    
    F_max = 1.2; F_min = 0.4; % 定义 F 的范围
    %% 初始化种群
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end    
    
    %% 初始化评估
    pop_objs = zeros(pop_size, 3);
    for i = 1:pop_size
        [~, obj] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;
    end    
    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);

    %% 迭代循环
    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);
        avg_rank = mean(rank);  % 当前代种群的平均 Rank
        min_rank = min(rank);   % 当前代最优的 Rank
        F = F_max - (F_max - F_min) * (gen / max_gen);
        i = 1;
        while i <= pop_size
            p1_idx = tournament_select_nsga2(rank, cd);
            p2_idx = tournament_select_nsga2(rank, cd);         
            child1 = pop(p1_idx, :); 
            child2 = pop(p2_idx, :);

            rank_p1 = rank(p1_idx);
            rank_p2 = rank(p2_idx);
            better_rank = min(rank_p1, rank_p2);  % 选择更优的个体
            
            % 动态调整交叉和变异概率
            pc = pc_min + (pc_max - pc_min) * (better_rank - min_rank) / (avg_rank - min_rank + 1e-6);
            pm1 = pm_min + (pm_max - pm_min) * (rank_p1 - min_rank) / (avg_rank - min_rank + 1e-6);
            pm2 = pm_min + (pm_max - pm_min) * (rank_p2 - min_rank) / (avg_rank - min_rank + 1e-6);
            
            % DE的变异和交叉操作
            if rand < pc
                [child1, child2] = crossover_de(pop(p1_idx,:), pop(p2_idx,:), num_tasks); % 使用DE交叉
            end
            if rand < pm1
                child1 = mutate_hybrid_de_cpo(child1, num_tasks, num_sub_agvs, pop, F, gen, max_gen, rank, rank_p1);  % 使用DE变异
            end
            if rand < pm2
                child2 = mutate_hybrid_de_cpo(child1, num_tasks, num_sub_agvs, pop, F, gen, max_gen, rank, rank_p1);  % 使用DE变异
            end
            
            offspring(i,:) = child1;
            if i+1 <= pop_size, offspring(i+1,:) = child2; end
            i = i + 2;
        end        
        
        %% 评估子代
        off_objs = zeros(pop_size, 3);
        for i = 1:pop_size
            [~, obj] = eval_func(offspring(i,:));
            off_objs(i,:) = obj;
        end
        
        %% 合并父代和子代进行排序
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);
        
        %% 精英选择
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
                [~, sort_idx] = sort(c_cd(front), 'descend');
                num_needed = pop_size - current_idx + 1;
                selected_front = front(sort_idx(1:num_needed));
                pop(current_idx : end, :) = combined_pop(selected_front, :);
                pop_objs(current_idx : end, :) = combined_objs(selected_front, :);
                break;
            end
            f = f + 1;
        end
        
        %% 更新新的Rank和拥挤度
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);
        
        % 记录每代最优解的总行驶距离
        front1 = fronts{1};
        dist_hist(gen) = min(pop_objs(front1, 1));
    end
end

function [schedules, objectives, batch_info] = cost_func_lift_moo(chromosome, tasks, agv_ids, depots, agv_params)
    num_tasks = size(tasks, 1);
    num_agvs = length(agv_ids);
    
    % 提取任务顺序基因串和AGV分配基因串
    task_seq = chromosome(1:num_tasks); 
    agv_assign = chromosome(num_tasks+1:end);    
    
    schedules = cell(1, num_agvs); % 存放AGV的排班表
    batch_info = cell(1, num_agvs); % 批次信息
    agv_dists = zeros(1, num_agvs);               
    agv_times = zeros(1, num_agvs);               
    max_load_capacity = 80;                       
    total_omega_sum = 0; 
    
    for k = 1:num_agvs
        real_agv_id = agv_ids(k);                  
        curr_agv = agv_params(real_agv_id);                

        % 选择分配给当前AGV的任务
        my_tasks = task_seq(agv_assign == k);
        
        if isempty(my_tasks)
            schedules{k} = []; % 如果没有任务分配给此AGV，则跳过
            continue;                               
        end
        
        % 确保 my_tasks 包含有效的索引值
        my_tasks = my_tasks(my_tasks > 0 & my_tasks <= num_tasks); % 保证索引在合法范围内
        
        % 检查 my_tasks 是否为空或包含无效索引
        if isempty(my_tasks)
            schedules{k} = []; % 如果没有有效的任务索引，跳过
            continue;  
        end
        
        % 获取有效的任务ID
        real_task_ids = tasks(my_tasks, 1)'; % 获取任务ID
        schedules{k} = real_task_ids;
        
        % FFD (First Fit Decreasing) 启发式装箱逻辑
        batches = {};
        task_weights = tasks(my_tasks, 3);
        [~, sort_idx] = sort(task_weights, 'descend');
        sorted_my_tasks = my_tasks(sort_idx);
        batch_weights_list = []; % 记录每个批次的总重
        
        % 首次适应分配 (First Fit)
        for t = 1:length(sorted_my_tasks)
            row_idx = sorted_my_tasks(t);
            w = tasks(row_idx, 3);
            
            placed = false;
            % 寻找能放下该任务的现有批次
            for b = 1:length(batches)
                if batch_weights_list(b) + w <= max_load_capacity
                    batches{b}(end+1) = row_idx; %#ok<AGROW> 
                    batch_weights_list(b) = batch_weights_list(b) + w; 
                    placed = true;
                    break;
                end
            end             
            % 如果现有批次都装不下，则新开一个批次
            if ~placed
                batches{end+1} = row_idx; %#ok<AGROW>
                batch_weights_list(end+1) = w; %#ok<AGROW>
            end
        end
        
        % 生成最终的任务ID序列
        real_task_ids = [];
        for b = 1:length(batches)
            [~, loc] = ismember(batches{b}, my_tasks);
            [~, order] = sort(loc);
            batches{b} = batches{b}(order);
            real_task_ids = [real_task_ids, tasks(batches{b}, 1)']; %#ok<AGROW> 
        end
        
        % 记录每个AGV的任务批次信息
        schedules{k} = real_task_ids;
        real_task_batches = cell(1, length(batches));
        for b = 1:length(batches)
            real_task_batches{b} = tasks(batches{b}, 1)'; % 转换为实际订单ID
        end
        
        batch_info{k} = struct(... 
            'num_batches', length(batches), ...         % 批次数
            'task_batches', {real_task_batches}, ...    % 每批任务ID
            'batch_weights', batch_weights_list ...     % 每批次的总重
        );

        % 计算每个AGV的行驶距离
        curr_pos = depots(real_agv_id, :);             
        dist_sum = 0; time_spent = 0;
        agv_omega_i = 0; 
        
        % 计算任务的行驶距离
        for b = 1:length(batches)
            batch = batches{b};
            pick_dist = 0; drop_dist = 0;
            current_payload = 0; 
            
            % 取货阶段
            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);          
                [pick_rc, ~] = get_coords_simple(target_id, curr_pos); 
                
                pick_dist = pick_dist + sum(abs(curr_pos - pick_rc)); 
                curr_pos = pick_rc; % 更新位置：AGV已移动到取货点                     
                
                current_payload = current_payload + tasks(batch(j), 3);
                agv_omega_i = agv_omega_i + current_payload;
            end
            
            % 送货阶段
            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);
                [~, drop_rc] = get_coords_simple(target_id, curr_pos); 
                
                drop_dist = drop_dist + sum(abs(curr_pos - drop_rc));
                curr_pos = drop_rc; % 更新位置：AGV已移动到送货点                        
                
                current_payload = current_payload - tasks(batch(j), 3);
                agv_omega_i = agv_omega_i + current_payload;
            end
            
            dist_sum = dist_sum + pick_dist + drop_dist;   
            time_spent = time_spent + (pick_dist + drop_dist) / curr_agv.speed; 
        end
        
        % 更新AGV的行驶距离、最大时间和负载积分
        agv_dists(k) = dist_sum;                           
        agv_times(k) = time_spent;                          
        total_omega_sum = total_omega_sum + agv_omega_i;
    end
    
    % 返回优化目标：总距离、最大时间、负载积分
    f1 = sum(agv_dists);           % 目标1：总距离
    f2 = max(agv_times);           % 目标2：最大时间
    f3 = -total_omega_sum;        % 目标3：负载积分

    objectives = [f1, f2, f3];     % 返回目标向量
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

function child = mutate_hybrid_de_cpo(chrom, num_tasks, num_agvs, pop, F, g, G, pop_ranks, curr_rank)
    child = chrom;
    PN = length(pop_ranks);
    
    % 随机选择三个不同的个体用于 DE 算子
    indices = randperm(size(pop, 1), 3);
    r1 = pop(indices(1), :);
    r2 = pop(indices(2), :);
    r3 = pop(indices(3), :);

    % =========================================================
    % 策略 1：任务序列部分 (1:num_tasks) -> 采用 CPO 自适应策略
    % =========================================================
    tau1 = rand(); tau2 = rand();
    tau1_prime = tau1 - 0.3 * (1 - g/G); 
    
    % 在 NSGA-II 中，Rank 越小越优秀
    % 计算当前个体在种群中的相对性能排名（百分比）
    relative_rank = sum(pop_ranks < curr_rank) / PN; 

    if tau1_prime < tau2
        % --- 探索阶段 ---
        if relative_rank > 0.6  % 性能较差的个体
            % 视觉防御：基因块翻转（彻底打破局部结构）
            range = sort(randperm(num_tasks, 2));
            child(1:num_tasks) = chrom(1:num_tasks);
            child(range(1):range(2)) = fliplr(child(range(1):range(2)));
        else
            % 声音防御：随机交换
            pos = randperm(num_tasks, 2);
            child(pos(1)) = chrom(pos(2));
            child(pos(2)) = chrom(pos(1));
        end
    else
        % --- 开发阶段 ---
        if relative_rank < 0.2 % 性能极好的个体
            % 物理攻击：四点两两交换（精细调整）
            pos = sort(randperm(num_tasks, 4));
            child(pos(1)) = chrom(pos(2)); child(pos(2)) = chrom(pos(1));
            child(pos(3)) = chrom(pos(4)); child(pos(4)) = chrom(pos(3));
        else
            % 气味防御：相邻交换
            idx = randi(num_tasks - 1);
            child(idx) = chrom(idx+1); child(idx+1) = chrom(idx);
        end
    end

    % =========================================================
    % 策略 2：AGV 分配部分 (num_tasks+1:end) -> 采用 DE 算子
    % =========================================================
    agv_idx = (num_tasks + 1) : (2 * num_tasks);
    
    % DE 变异算子：x_new = r1 + F * (r2 - r3)
    % DE 能够很好地在不同的车辆分配方案之间寻找平衡
    mutated_agv_part = r1(agv_idx) + F * (r2(agv_idx) - r3(agv_idx));
    
    % 取整并限制边界，防止索引失效
    mutated_agv_part = round(mutated_agv_part);
    mutated_agv_part = max(1, min(num_agvs, mutated_agv_part));
    
    % 二进制交叉（DE 风格）：决定哪些位置接受 DE 变异
    cr_mask = rand(1, num_tasks) < 0.5; % 交叉概率 0.5
    child(num_tasks + find(cr_mask)) = mutated_agv_part(cr_mask);
end

function [child1, child2] = crossover_de(p1, p2, num_tasks)
    % 任务序列部分：执行 IPOX 交叉（保留任务的偏序关系，不产生非法索引）
    % 随机选一组任务
    num_sub = randi([round(num_tasks/3), round(num_tasks/2)]);
    subset = randperm(num_tasks, num_sub);
    
    child1 = zeros(1, 2*num_tasks);
    child2 = zeros(1, 2*num_tasks);
    
    % 子代 1 继承父代 1 的部分位置
    child1(subset) = p1(subset);
    % 剩余位置按父代 2 的顺序填充
    remaining_vals2 = setdiff(p2(1:num_tasks), child1(subset), 'stable');
    child1(child1(1:num_tasks) == 0) = remaining_vals2;
    
    % 子代 2 同理
    child2(subset) = p2(subset);
    remaining_vals1 = setdiff(p1(1:num_tasks), child2(subset), 'stable');
    child2(child2(1:num_tasks) == 0) = remaining_vals1;
    
    % AGV 分配部分：直接执行均匀交叉（因为 AGV 编号允许重复）
    mask = rand(1, num_tasks) < 0.5;
    p1_agv = p1(num_tasks+1:end);
    p2_agv = p2(num_tasks+1:end);
    
    c1_agv = p1_agv; c1_agv(mask) = p2_agv(mask);
    c2_agv = p2_agv; c2_agv(mask) = p1_agv(mask);
    
    child1(num_tasks+1:end) = c1_agv;
    child2(num_tasks+1:end) = c2_agv;
end


%% 叉车式AGV相关函数
function [best_sched, best_cost, cost_hist] = run_sub_hga(tasks, num_sub_agvs, ga_params, eval_func)
    % 输入说明：
    % tasks: 任务矩阵
    % num_sub_agvs: 子系统AGV数量
    % ga_params: 包含 pop_size, max_gen 等
    % eval_func: 成本计算函数句柄
    
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    
    % 算子参数
    pc1 = 0.8; pc2 = 0.5;
    pm = 0.3; 
    T = 2000; alpha_T = 0.995;

    % 1. 初始化种群 (双层编码)
    % 前 num_tasks 位：任务顺序 (1~N排列)
    % 后 num_tasks 位：AGV分配 (1~M随机)
    population = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        population(i, 1:num_tasks) = randperm(num_tasks);
        population(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end

    best_cost = Inf;
    best_sched = cell(1, num_sub_agvs);
    cost_hist = zeros(1, max_gen);

    % 2. 进化循环
    for gen = 1:max_gen
        costs = zeros(pop_size, 1);
        for i = 1:pop_size
            [scheds, t_cost] = eval_func(population(i,:));
            costs(i) = t_cost;
            if t_cost < best_cost
                best_cost = t_cost;
                best_sched = scheds;
            end
        end
        cost_hist(gen) = best_cost;

        % 封装变异句柄，将 tasks 和 num_sub_agvs 提前注入
        % 这样在 evolve 函数内部只需要传入 (chromosome, current_pm)
        mutate_handle = @(chrom, pm, curr_c) mutate_fork_time_guided(chrom, tasks, num_sub_agvs, pm, gen, max_gen, costs, curr_c);

        % 调用演化操作
        population = evolve_population_sub(population, costs, num_sub_agvs, num_tasks, ...
                                          pc1, pc2, pm, T, eval_func, mutate_handle);
        T = T * alpha_T;
    end
end

function new_pop = evolve_population_sub(pop, costs, ~, num_tasks, pc1, pc2, pm, T, eval_func, mutate_func)
    pop_size = size(pop, 1);
    new_pop = zeros(size(pop));
    cost_min = min(costs);
    cost_avg = mean(costs);

    % 精英保留
    [~, idx] = sort(costs);
    new_pop(1,:) = pop(idx(1), :);
    new_pop(2,:) = pop(idx(2), :);

    i = 3;
    while i <= pop_size
        % 选择
        p1_idx = tournament_select(costs);
        p2_idx = tournament_select(costs);
        p1 = pop(p1_idx, :);
        p2 = pop(p2_idx, :);

        % 计算自适应概率
        c_parent = min(costs(p1_idx), costs(p2_idx));
        if c_parent <= cost_avg
            ratio = (cost_avg - c_parent) / (cost_avg - cost_min + 1e-6);
            pc = pc1 - (pc1 - pc2) * ratio;
        else
            pc = pc1; 
        end

        % 交叉 (此处需确保 crossover_IPOX_MPX 函数在路径中)
        child1 = p1; 
        child2 = p2;
        if rand < pc
            [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks);
        end
        % 2. 变异 (适配 CPO 自适应机制)
        % 获取交叉后子代的基本成本，用于变异策略的初步排名判断
        [~, c1_cost_pre] = eval_func(child1);
        [~, c2_cost_pre] = eval_func(child2);
        % 变异 (调用封装好的 mutate_fork_time_guided)
        if rand < pm
            % 传入个体成本 c1_cost_pre 以执行对应的防御策略
            child1 = mutate_func(child1, pm, c1_cost_pre); 
        end
        if rand < pm
            child2 = mutate_func(child2, pm, c2_cost_pre);
        end

        % Metropolis 准则 (接受子代)
        new_pop(i, :) = metropolis_accept(p1, child1, costs(p1_idx), T, eval_func);
        if i + 1 <= pop_size
            new_pop(i+1, :) = metropolis_accept(p2, child2, costs(p2_idx), T, eval_func);
        end
        i = i + 2;
    end
end

function [schedules, total_cost] = cost_func_fork(chromosome, tasks, agv_ids, depots, agv_params, weights)
    % 输入输出同 cost_func_lift，但针对叉车特点设计
    num_tasks = size(tasks, 1);
    num_agvs = length(agv_ids);
    task_seq = chromosome(1:num_tasks);
    agv_assign = chromosome(num_tasks+1:end);

    schedules = cell(1, num_agvs);
    total_dist = 0;
    total_penalty = 0;

    for k = 1:num_agvs
        real_agv_id = agv_ids(k);
        curr_agv = agv_params(real_agv_id);

        my_tasks = task_seq(agv_assign == k);
        real_task_ids = tasks(my_tasks, 1)';
        schedules{k} = real_task_ids;

        if isempty(my_tasks)
            continue;
        end

        curr_pos = depots(real_agv_id, :);
        time_spent = 0;
        % 叉车无批次，绝对串行 (一次一件)
        for t = 1:length(my_tasks)
            row_idx = my_tasks(t);
            target_id = tasks(row_idx, 2);
            deadline = tasks(row_idx, 4);                   % 任务截止时间
            
            % 【核心更新】：传入 curr_pos 进行 3x3 区域曼哈顿距离寻优
            [pick_rc, drop_rc] = get_coords_simple(target_id, curr_pos);
            
            d1 = sum(abs(curr_pos - pick_rc));               % 当前位置到最优取货点
            d2 = sum(abs(pick_rc - drop_rc));                % 最优取货点到最优送货点
            dist_leg = d1 + d2;
            total_dist = total_dist + dist_leg;              % 累加总距离
            
            % 累加时间并计算严苛的超时惩罚
            time_spent = time_spent + dist_leg / curr_agv.speed;
            if time_spent > deadline
                % 【目标函数设计】：超时即重罚，迫使算法优化顺序
                total_penalty = total_penalty + (time_spent - deadline) * weights.w_penalty * 5;
            end
            
            % 更新位置：叉车完成当前任务的送货，处于送货点位置
            curr_pos = drop_rc;                               
        end
    end

    % 【目标函数设计】：只追求跑得距离最短，且绝对不允许超时！
    total_cost = total_dist * weights.w_dist + total_penalty;
end

function idx = tournament_select(costs)
    % 锦标赛选择：随机选两个个体，返回成本较小的索引
    i1 = randi(length(costs));
    i2 = randi(length(costs));
    if costs(i1) < costs(i2)
        idx = i1;
    else
        idx = i2;
    end
end

function child = mutate_fork_time_guided(chrom, tasks, num_agvs, pm, g, G, pop_costs, current_cost)

    num_tasks = size(tasks, 1);
    child = chrom;
    PN = length(pop_costs); % 当前种群数量
    
    % --- 1. 任务基因串变异 (融合 CPO 防御策略优化) ---
    % Step 1: 生成随机数并根据迭代次数更新
    tau1 = rand(); 
    tau2 = rand();
    tau1_prime = tau1 - 0.3 * (1 - g/G); % 公式 (4.27)
    
    % 获取当前个体在种群中的排名 (升序排名，成本越低排名越靠前)
    sorted_costs = sort(pop_costs);
    rank_idx = find(sorted_costs == current_cost, 1, 'first');
    
    % 如果因为浮点数精度没找到（极端情况），给一个默认排名
    if isempty(rank_idx)
        [~, rank_idx] = min(abs(sorted_costs - current_cost));
    end
    
    if tau1_prime < tau2
        % --- 执行探索策略 ---
        if rank_idx > 0.6 * PN
            % 视觉防御策略：基因块翻转 (图 4.3)
            range = sort(randperm(num_tasks, 2));
            child(range(1):range(2)) = fliplr(child(range(1):range(2)));
        else
            % 声音防御策略：交换变异 (图 4.4)
            pos = randperm(num_tasks, 2);
            t = child(pos(1)); child(pos(1)) = child(pos(2)); child(pos(2)) = t;
        end
    else
        % --- 执行开发策略 ---
        if rank_idx > 0.2 * PN && rank_idx <= 0.4 * PN
            % 气味防御策略：相邻基因交换 (图 4.5)
            idx = randi(num_tasks - 1);
            t = child(idx); child(idx) = child(idx+1); child(idx+1) = t;
        else
            % 物理攻击策略: 选取 4 个点，两两交换距离相近位置点 (图 3.7)
            pos = sort(randperm(num_tasks, 4));
            t1 = child(pos(1)); child(pos(1)) = child(pos(2)); child(pos(2)) = t1;
            t2 = child(pos(3)); child(pos(3)) = child(pos(4)); child(pos(4)) = t2;
        end
    end

    % 2. AGV 基因串变异 (图 3.8)
    if rand < (pm + 0.1)
        agv_idx = (num_tasks + 1) : (2 * num_tasks);
        current_agvs = child(agv_idx);
        
        % 统计频率
        counts = zeros(1, num_agvs);
        for k = 1:num_agvs
            counts(k) = sum(current_agvs == k);
        end
        
        % 找频率最低的（可能有多个）
        min_val = min(counts);
        candidates = find(counts == min_val);
        
        % 随机覆盖两个位置
        mutate_pos = randperm(num_tasks, 2);
        for p = 1:2
            child(num_tasks + mutate_pos(p)) = candidates(randi(length(candidates)));
        end
    end
end

function selected = metropolis_accept(parent, child, p_cost, T, eval_func)
% M准则
    [~, c_cost] = eval_func(child);
    delta = c_cost - p_cost;
    if delta <= 0 || rand < exp(-delta / T)
        selected = child;
    else
        selected = parent;
    end
end

%% 两种AGV共同使用的函数
function [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks)
    % 混合交叉：IPOX (顺序部分) 用于任务顺序，MPX (多点交叉) 用于AGV分配
    child1 = zeros(1, num_tasks * 2);
    child2 = zeros(1, num_tasks * 2);

    % ---- IPOX 交叉 (任务顺序部分) ----
    seq1 = p1(1:num_tasks);
    seq2 = p2(1:num_tasks);

    mask = randi([0, 1], 1, num_tasks);          % 随机生成0/1掩码
    set1 = seq1(mask == 1);                       % 从父代1选取掩码为1的位置上的任务
    % 构建子代1的顺序：掩码为1的位置保持父代1的任务，掩码为0的位置按父代2中未在set1中的任务顺序填充
    c1_seq = zeros(1, num_tasks);
    c1_seq(mask == 1) = set1;
    c1_seq(mask == 0) = seq2(~ismember(seq2, set1));

    set2 = seq2(mask == 1);                       % 从父代2选取掩码为1的任务
    c2_seq = zeros(1, num_tasks);
    c2_seq(mask == 1) = set2;
    c2_seq(mask == 0) = seq1(~ismember(seq1, set2));

    % ---- MPX 交叉 (AGV分配部分) ----
    agv1 = p1(num_tasks+1:end);
    agv2 = p2(num_tasks+1:end);
    mpx_mask = randi([0, 1], 1, num_tasks);       % 随机掩码
    c1_agv = agv1;
    c2_agv = agv2;
    c1_agv(mpx_mask == 1) = agv2(mpx_mask == 1); % 交换掩码为1位置的AGV编号
    c2_agv(mpx_mask == 1) = agv1(mpx_mask == 1);

    % 合并两部分形成完整子代
    child1 = [c1_seq, c1_agv];
    child2 = [c2_seq, c2_agv];
end

function [pick, drop] = get_coords_simple(target_id, current_pos)
    % 输入: 
    %   target_id   - 任务工位ID (1-12为小件, 13-16为大件)
    %   current_pos - AGV当前坐标 [x, y]
    % 输出:
    %   pick        - 曼哈顿距离最短的取货点 [x, y]
    %   drop        - 曼哈顿距离最短的送货点 [x, y]

    if target_id <= 12
        % --- 小件区动态寻优逻辑 (ID 1-12, 2x2 区域) ---
        if target_id <= 6
            offset = target_id - 1;
            % 左下仓库基准 (X起始:3, 间隔:4, Y:18)
            pick_base = [3 + offset * 4, 18];
            % 中间U型工位基准 (X起始:17, 间隔:5, Y:43)
            drop_base = [17 + offset * 5, 43];
        else
            offset = target_id - 7;
            % 左下仓库基准 (X起始:3, 间隔:4, Y:10)
            pick_base = [3 + offset * 4, 10];
            % 中间U型工位基准 (X起始:17, 间隔:5, Y:33)
            drop_base = [17 + offset * 5, 33];
        end
        
        % 在 2x2 区域内寻找曼哈顿距离最短的点
        pick = find_nearest_grid_custom(pick_base, current_pos, 2);
        drop = find_nearest_grid_custom(drop_base, pick, 2);
        
    else
        % --- 大件区动态寻优逻辑 (ID 13-16, 3x3 区域) ---
        % 同步更新为分散式地图布局坐标
        w_bases = [4, 42; 18, 4; 40, 23; 47, 11]; % 仓库取货基准
        s_bases = [40, 11; 4, 36; 5, 23; 47, 23]; % 工位送货基准
        
        idx = target_id - 12; % 映射到 bases 矩阵索引 (1-4)
        pick_base = w_bases(idx, :); 
        drop_base = s_bases(idx, :); 
        
        % 在 3x3 区域内寻找曼哈顿距离最短的取货点
        pick = find_nearest_grid_custom(pick_base, current_pos, 3);
        % 根据取货后的位置寻找曼哈顿距离最短的送货点
        drop = find_nearest_grid_custom(drop_base, pick, 3);
    end
end

function best_pt = find_nearest_grid_custom(base_xy, reference_pos, size_n)
    % 在 n x n 区域内寻找曼哈顿距离最短的栅格点
    min_dist = inf;
    best_pt = base_xy;
    
    for dx = 0:size_n-1
        for dy = 0:size_n-1
            test_pt = [base_xy(1) + dx, base_xy(2) + dy];
            % 计算曼哈顿距离: |x1-x2| + |y1-y2|
            dist = sum(abs(test_pt - reference_pos));
            
            if dist < min_dist
                min_dist = dist;
                best_pt = test_pt;
            end
        end
    end
end