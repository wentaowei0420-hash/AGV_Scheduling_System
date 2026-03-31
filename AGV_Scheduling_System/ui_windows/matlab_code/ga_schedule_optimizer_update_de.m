function [best_schedule, batch_details, hist_lift, hist_fork, dist_lift, dist_fork] = ga_schedule_optimizer_update_de(task_list, num_agvs, depots, agv_params, weights, ga_params, agv_types)
    idx_lift_tasks = task_list(:,2) <= 12;
    idx_fork_tasks = task_list(:,2) > 12;
    tasks_lift = task_list(idx_lift_tasks, :);
    tasks_fork = task_list(idx_fork_tasks, :);
    agvs_lift = find(agv_types == 1); 
    agvs_fork = find(agv_types == 2); 
    best_schedule = cell(1, num_agvs);
    batch_details = cell(1, num_agvs); 
    hist_lift = zeros(1, ga_params.max_gen);
    hist_fork = zeros(1, ga_params.max_gen);
    dist_lift = 0;
    dist_fork = 0;
    if ~isempty(tasks_lift) && ~isempty(agvs_lift)
        disp('   -> 启动 NSGA-II 引擎优化托举车（多目标：距离、时间、负载率）...');
        eval_lift_moo = @(chrom) cost_func_lift_moo(chrom, tasks_lift, agvs_lift, depots, agv_params);
        [pop_lift, objs_lift, fronts_lift, ~, hist_lift] = run_sub_nsga2_lift_with_de(tasks_lift, length(agvs_lift), ga_params, eval_lift_moo);
        front1_idx = fronts_lift{1}; 
        front1_objs = objs_lift(front1_idx, :);
        min_objs = min(front1_objs, [], 1);
        max_objs = max(front1_objs, [], 1);
        obj_norm = (front1_objs - min_objs) ./ (max_objs - min_objs + 1e-6);
        compromise_scores = sqrt(sum(obj_norm.^2, 2));
        [~, best_idx_in_front1] = min(compromise_scores);
        best_lift_chrom = pop_lift(front1_idx(best_idx_in_front1), :);
        [sched_lift, best_objs_lift, batch_info_lift] = eval_lift_moo(best_lift_chrom);
        dist_lift = best_objs_lift(1);
        for i = 1:length(agvs_lift)
            best_schedule{agvs_lift(i)} = sched_lift{i};
            batch_details{agvs_lift(i)} = batch_info_lift{i};
        end
    end
    if ~isempty(tasks_fork) && ~isempty(agvs_fork)
        disp('   -> 启动 HGA 引擎优化叉车（单目标：最短路径 + 时间惩罚）...');
        eval_fork = @(chrom) cost_func_fork(chrom, tasks_fork, agvs_fork, depots, agv_params, weights);
        [sched_fork, best_cost_fork, hist_fork] = run_sub_hga(tasks_fork, length(agvs_fork), ga_params, eval_fork);
        dist_fork = best_cost_fork;
        for i = 1:length(agvs_fork)
            best_schedule{agvs_fork(i)} = sched_fork{i};
        end
    end
end
function [pop, pop_objs, fronts, cd, dist_hist] = run_sub_nsga2_lift_with_de(tasks, num_sub_agvs, ga_params, eval_func)
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    dist_hist = zeros(1, max_gen);
    pc_max = 0.8; pc_min = 0.6;
    pm_max = 0.2; pm_min = 0.05;
    F_max = 1.2; F_min = 0.4;
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end    
    
    pop_objs = zeros(pop_size, 3);
    for i = 1:pop_size
        [~, obj] = eval_func(pop(i,:));
        pop_objs(i,:) = obj;
    end    
    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);

    for gen = 1:max_gen
        offspring = zeros(pop_size, num_tasks * 2);
        avg_rank = mean(rank);
        min_rank = min(rank);
        F = F_max - (F_max - F_min) * (gen / max_gen);
        i = 1;
        while i <= pop_size
            p1_idx = tournament_select_nsga2(rank, cd);
            p2_idx = tournament_select_nsga2(rank, cd);         
            child1 = pop(p1_idx, :); 
            child2 = pop(p2_idx, :);

            rank_p1 = rank(p1_idx);
            rank_p2 = rank(p2_idx);
            better_rank = min(rank_p1, rank_p2);
            
            pc = pc_min + (pc_max - pc_min) * (better_rank - min_rank) / (avg_rank - min_rank + 1e-6);
            pm1 = pm_min + (pm_max - pm_min) * (rank_p1 - min_rank) / (avg_rank - min_rank + 1e-6);
            pm2 = pm_min + (pm_max - pm_min) * (rank_p2 - min_rank) / (avg_rank - min_rank + 1e-6);
            
            if rand < pc
                [child1, child2] = crossover_de(pop(p1_idx,:), pop(p2_idx,:), num_tasks);
            end
            if rand < pm1
                child1 = mutate_hybrid_de_cpo(child1, num_tasks, num_sub_agvs, pop, F, gen, max_gen, rank, rank_p1);
            end
            if rand < pm2
                child2 = mutate_hybrid_de_cpo(child1, num_tasks, num_sub_agvs, pop, F, gen, max_gen, rank, rank_p1);
            end
            
            offspring(i,:) = child1;
            if i+1 <= pop_size, offspring(i+1,:) = child2; end
            i = i + 2;
        end        
        
        off_objs = zeros(pop_size, 3);
        for i = 1:pop_size
            [~, obj] = eval_func(offspring(i,:));
            off_objs(i,:) = obj;
        end
        
        combined_pop = [pop; offspring];
        combined_objs = [pop_objs; off_objs];
        
        [c_fronts, ~] = fast_non_dominated_sorting(combined_objs);
        c_cd = calc_crowding_distance(combined_objs, c_fronts);
        
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
        
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);
        
        front1 = fronts{1};
        dist_hist(gen) = min(pop_objs(front1, 1));
    end
end

function [schedules, objectives, batch_info] = cost_func_lift_moo(chromosome, tasks, agv_ids, depots, agv_params)
    num_tasks = size(tasks, 1);
    num_agvs = length(agv_ids);
    
    task_seq = chromosome(1:num_tasks); 
    agv_assign = chromosome(num_tasks+1:end);    
    
    schedules = cell(1, num_agvs);
    batch_info = cell(1, num_agvs);
    agv_dists = zeros(1, num_agvs);               
    agv_times = zeros(1, num_agvs);               
    max_load_capacity = 80;                       
    total_omega_sum = 0; 
    
    for k = 1:num_agvs
        real_agv_id = agv_ids(k);                  
        curr_agv = agv_params(real_agv_id);                

        my_tasks = task_seq(agv_assign == k);
        
        if isempty(my_tasks)
            schedules{k} = [];
            continue;                               
        end
        
        my_tasks = my_tasks(my_tasks > 0 & my_tasks <= num_tasks);
        
        if isempty(my_tasks)
            schedules{k} = [];
            continue;  
        end
        
        real_task_ids = tasks(my_tasks, 1)';
        schedules{k} = real_task_ids;
        
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
        
        batch_info{k} = struct(... 
            'num_batches', length(batches), ...
            'task_batches', {real_task_batches}, ...
            'batch_weights', batch_weights_list ...
        );

        curr_pos = depots(real_agv_id, :);             
        dist_sum = 0; time_spent = 0;
        agv_omega_i = 0; 
        
        for b = 1:length(batches)
            batch = batches{b};
            pick_dist = 0; drop_dist = 0;
            current_payload = 0; 
            
            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);          
                [pick_rc, ~] = get_coords_simple(target_id, curr_pos); 
                
                pick_dist = pick_dist + sum(abs(curr_pos - pick_rc)); 
                curr_pos = pick_rc;
                
                current_payload = current_payload + tasks(batch(j), 3);
                agv_omega_i = agv_omega_i + current_payload;
            end
            
            for j = 1:length(batch)
                target_id = tasks(batch(j), 2);
                [~, drop_rc] = get_coords_simple(target_id, curr_pos); 
                
                drop_dist = drop_dist + sum(abs(curr_pos - drop_rc));
                curr_pos = drop_rc;
                
                current_payload = current_payload - tasks(batch(j), 3);
                agv_omega_i = agv_omega_i + current_payload;
            end
            
            dist_sum = dist_sum + pick_dist + drop_dist;   
            time_spent = time_spent + (pick_dist + drop_dist) / curr_agv.speed; 
        end
        
        agv_dists(k) = dist_sum;                           
        agv_times(k) = time_spent;                          
        total_omega_sum = total_omega_sum + agv_omega_i;
    end
    
    f1 = sum(agv_dists);
    f2 = max(agv_times);
    f3 = -total_omega_sum;

    objectives = [f1, f2, f3];
end

function [fronts, rank] = fast_non_dominated_sorting(pop_objs)
    pop_size = size(pop_objs, 1);
    fronts = cell(pop_size, 1);
    domination_count = zeros(pop_size, 1);
    dominated_set = cell(pop_size, 1);
    rank = zeros(pop_size, 1);

    for i = 1:pop_size
        for j = 1:pop_size
            if i == j, continue; end
            if all(pop_objs(i,:) <= pop_objs(j,:)) && any(pop_objs(i,:) < pop_objs(j,:))
                dominated_set{i} = [dominated_set{i}, j];
            elseif all(pop_objs(j,:) <= pop_objs(i,:)) && any(pop_objs(j,:) < pop_objs(i,:))
                domination_count(i) = domination_count(i) + 1;
            end
        end
        if domination_count(i) == 0
            rank(i) = 1;
            fronts{1} = [fronts{1}, i];
        end
    end

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
    fronts(cellfun(@isempty, fronts)) = [];
end

function cd = calc_crowding_distance(pop_objs, fronts)
    pop_size = size(pop_objs, 1);
    num_objs = size(pop_objs, 2);
    cd = zeros(pop_size, 1);

    for f = 1:length(fronts)
        front = fronts{f};
        l = length(front);
        
        if l <= 2
            cd(front) = inf;
            continue;
        end
        
        for m = 1:num_objs
            [sorted_objs, idx] = sort(pop_objs(front, m));
            sorted_front = front(idx);
            
            cd(sorted_front(1)) = inf;
            cd(sorted_front(end)) = inf;
            
            f_min = sorted_objs(1);
            f_max = sorted_objs(end);
            
            if f_max - f_min == 0, continue; end
            
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

function child = mutate_hybrid_de_cpo(chrom, num_tasks, num_agvs, pop, F, g, G, pop_ranks, curr_rank)
    child = chrom;
    PN = length(pop_ranks);
    
    indices = randperm(size(pop, 1), 3);
    r1 = pop(indices(1), :);
    r2 = pop(indices(2), :);
    r3 = pop(indices(3), :);

    tau1 = rand(); tau2 = rand();
    tau1_prime = tau1 - 0.3 * (1 - g/G); 
    
    relative_rank = sum(pop_ranks < curr_rank) / PN; 

    if tau1_prime < tau2
        if relative_rank > 0.6
            range = sort(randperm(num_tasks, 2));
            child(1:num_tasks) = chrom(1:num_tasks);
            child(range(1):range(2)) = fliplr(child(range(1):range(2)));
        else
            pos = randperm(num_tasks, 2);
            child(pos(1)) = chrom(pos(2));
            child(pos(2)) = chrom(pos(1));
        end
    else
        if relative_rank < 0.2
            pos = sort(randperm(num_tasks, 4));
            child(pos(1)) = chrom(pos(2)); child(pos(2)) = chrom(pos(1));
            child(pos(3)) = chrom(pos(4)); child(pos(4)) = chrom(pos(3));
        else
            idx = randi(num_tasks - 1);
            child(idx) = chrom(idx+1); child(idx+1) = chrom(idx);
        end
    end

    agv_idx = (num_tasks + 1) : (2 * num_tasks);
    
    mutated_agv_part = r1(agv_idx) + F * (r2(agv_idx) - r3(agv_idx));
    
    mutated_agv_part = round(mutated_agv_part);
    mutated_agv_part = max(1, min(num_agvs, mutated_agv_part));
    
    cr_mask = rand(1, num_tasks) < 0.5;
    child(num_tasks + find(cr_mask)) = mutated_agv_part(cr_mask);
end

function [child1, child2] = crossover_de(p1, p2, num_tasks)
    num_sub = randi([round(num_tasks/3), round(num_tasks/2)]);
    subset = randperm(num_tasks, num_sub);
    
    child1 = zeros(1, 2*num_tasks);
    child2 = zeros(1, 2*num_tasks);
    
    child1(subset) = p1(subset);
    remaining_vals2 = setdiff(p2(1:num_tasks), child1(subset), 'stable');
    child1(child1(1:num_tasks) == 0) = remaining_vals2;
    
    child2(subset) = p2(subset);
    remaining_vals1 = setdiff(p1(1:num_tasks), child2(subset), 'stable');
    child2(child2(1:num_tasks) == 0) = remaining_vals1;
    
    mask = rand(1, num_tasks) < 0.5;
    p1_agv = p1(num_tasks+1:end);
    p2_agv = p2(num_tasks+1:end);
    
    c1_agv = p1_agv; c1_agv(mask) = p2_agv(mask);
    c2_agv = p2_agv; c2_agv(mask) = p1_agv(mask);
    
    child1(num_tasks+1:end) = c1_agv;
    child2(num_tasks+1:end) = c2_agv;
end


function [best_sched, best_cost, cost_hist] = run_sub_hga(tasks, num_sub_agvs, ga_params, eval_func)
    
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    max_gen = ga_params.max_gen;
    
    pc1 = 0.8; pc2 = 0.5;
    pm = 0.3; 
    T = 2000; alpha_T = 0.995;

    population = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        population(i, 1:num_tasks) = randperm(num_tasks);
        population(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end

    best_cost = Inf;
    best_sched = cell(1, num_sub_agvs);
    cost_hist = zeros(1, max_gen);

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

        mutate_handle = @(chrom, pm, curr_c) mutate_fork_time_guided(chrom, tasks, num_sub_agvs, pm, gen, max_gen, costs, curr_c);

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

    [~, idx] = sort(costs);
    new_pop(1,:) = pop(idx(1), :);
    new_pop(2,:) = pop(idx(2), :);

    i = 3;
    while i <= pop_size
        p1_idx = tournament_select(costs);
        p2_idx = tournament_select(costs);
        p1 = pop(p1_idx, :);
        p2 = pop(p2_idx, :);

        c_parent = min(costs(p1_idx), costs(p2_idx));
        if c_parent <= cost_avg
            ratio = (cost_avg - c_parent) / (cost_avg - cost_min + 1e-6);
            pc = pc1 - (pc1 - pc2) * ratio;
        else
            pc = pc1; 
        end

        child1 = p1; 
        child2 = p2;
        if rand < pc
            [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks);
        end
        [~, c1_cost_pre] = eval_func(child1);
        [~, c2_cost_pre] = eval_func(child2);
        if rand < pm
            child1 = mutate_func(child1, pm, c1_cost_pre); 
        end
        if rand < pm
            child2 = mutate_func(child2, pm, c2_cost_pre);
        end

        new_pop(i, :) = metropolis_accept(p1, child1, costs(p1_idx), T, eval_func);
        if i + 1 <= pop_size
            new_pop(i+1, :) = metropolis_accept(p2, child2, costs(p2_idx), T, eval_func);
        end
        i = i + 2;
    end
end

function [schedules, total_cost] = cost_func_fork(chromosome, tasks, agv_ids, depots, agv_params, weights)
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
        for t = 1:length(my_tasks)
            row_idx = my_tasks(t);
            target_id = tasks(row_idx, 2);
            deadline = tasks(row_idx, 4);
            
            [pick_rc, drop_rc] = get_coords_simple(target_id, curr_pos);
            
            d1 = sum(abs(curr_pos - pick_rc));
            d2 = sum(abs(pick_rc - drop_rc));
            dist_leg = d1 + d2;
            total_dist = total_dist + dist_leg;
            
            time_spent = time_spent + dist_leg / curr_agv.speed;
            if time_spent > deadline
                total_penalty = total_penalty + (time_spent - deadline) * weights.w_penalty * 5;
            end
            
            curr_pos = drop_rc;                               
        end
    end

    total_cost = total_dist * weights.w_dist + total_penalty;
end

function idx = tournament_select(costs)
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
    PN = length(pop_costs);
    
    tau1 = rand(); 
    tau2 = rand();
    tau1_prime = tau1 - 0.3 * (1 - g/G);
    
    sorted_costs = sort(pop_costs);
    rank_idx = find(sorted_costs == current_cost, 1, 'first');
    
    if isempty(rank_idx)
        [~, rank_idx] = min(abs(sorted_costs - current_cost));
    end
    
    if tau1_prime < tau2
        if rank_idx > 0.6 * PN
            range = sort(randperm(num_tasks, 2));
            child(range(1):range(2)) = fliplr(child(range(1):range(2)));
        else
            pos = randperm(num_tasks, 2);
            t = child(pos(1)); child(pos(1)) = child(pos(2)); child(pos(2)) = t;
        end
    else
        if rank_idx > 0.2 * PN && rank_idx <= 0.4 * PN
            idx = randi(num_tasks - 1);
            t = child(idx); child(idx) = child(idx+1); child(idx+1) = t;
        else
            pos = sort(randperm(num_tasks, 4));
            t1 = child(pos(1)); child(pos(1)) = child(pos(2)); child(pos(2)) = t1;
            t2 = child(pos(3)); child(pos(3)) = child(pos(4)); child(pos(4)) = t2;
        end
    end

    if rand < (pm + 0.1)
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

function selected = metropolis_accept(parent, child, p_cost, T, eval_func)
    [~, c_cost] = eval_func(child);
    delta = c_cost - p_cost;
    if delta <= 0 || rand < exp(-delta / T)
        selected = child;
    else
        selected = parent;
    end
end

function [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks)
    child1 = zeros(1, num_tasks * 2);
    child2 = zeros(1, num_tasks * 2);

    seq1 = p1(1:num_tasks);
    seq2 = p2(1:num_tasks);

    mask = randi([0, 1], 1, num_tasks);
    set1 = seq1(mask == 1);
    c1_seq = zeros(1, num_tasks);
    c1_seq(mask == 1) = set1;
    c1_seq(mask == 0) = seq2(~ismember(seq2, set1));

    set2 = seq2(mask == 1);
    c2_seq = zeros(1, num_tasks);
    c2_seq(mask == 1) = set2;
    c2_seq(mask == 0) = seq1(~ismember(seq1, set2));

    agv1 = p1(num_tasks+1:end);
    agv2 = p2(num_tasks+1:end);
    mpx_mask = randi([0, 1], 1, num_tasks);
    c1_agv = agv1;
    c2_agv = agv2;
    c1_agv(mpx_mask == 1) = agv2(mpx_mask == 1);
    c2_agv(mpx_mask == 1) = agv1(mpx_mask == 1);

    child1 = [c1_seq, c1_agv];
    child2 = [c2_seq, c2_agv];
end

function [pick, drop] = get_coords_simple(target_id, current_pos)

    if target_id <= 12
        if target_id <= 6
            offset = target_id - 1;
            pick_base = [3 + offset * 4, 18];
            drop_base = [17 + offset * 5, 43];
        else
            offset = target_id - 7;
            pick_base = [3 + offset * 4, 10];
            drop_base = [17 + offset * 5, 33];
        end
        
        pick = find_nearest_grid_custom(pick_base, current_pos, 2);
        drop = find_nearest_grid_custom(drop_base, pick, 2);
        
    else
        w_bases = [4, 42; 18, 4; 40, 23; 47, 11];
        s_bases = [40, 11; 4, 36; 5, 23; 47, 23];
        
        idx = target_id - 12;
        pick_base = w_bases(idx, :); 
        drop_base = s_bases(idx, :); 
        
        pick = find_nearest_grid_custom(pick_base, current_pos, 3);
        drop = find_nearest_grid_custom(drop_base, pick, 3);
    end
end

function best_pt = find_nearest_grid_custom(base_xy, reference_pos, size_n)
    min_dist = inf;
    best_pt = base_xy;
    
    for dx = 0:size_n-1
        for dy = 0:size_n-1
            test_pt = [base_xy(1) + dx, base_xy(2) + dy];
            dist = sum(abs(test_pt - reference_pos));
            
            if dist < min_dist
                min_dist = dist;
                best_pt = test_pt;
            end
        end
    end
end
