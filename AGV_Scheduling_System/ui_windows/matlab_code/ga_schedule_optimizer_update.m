function [best_schedule, batch_details, metrics, history, pareto_fronts] = ga_schedule_optimizer_update(task_list, num_agvs, depots, agv_params, ga_params, agv_types)

    debug_opts = get_ga_debug_options();
    oracle_options = struct();
    oracle_options.task_target_ids = unique(task_list(:, 2))';
    oracle_options.agv_types = unique(agv_types)';
    if debug_opts.disable_oracle
        path_oracle = [];
        fprintf('[调试模式] 已禁用 region_distance_oracle，当前仅使用 A* 回退链路进行排查。\n');
    else
        path_oracle = region_distance_oracle('build', oracle_options);
    end
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

    if ~isempty(tasks_lift) && ~isempty(agvs_lift)
        disp('   -> 启动 NSGA-II 引擎优化托举车（多目标：距离、时间、能耗）...');
        
        eval_lift_moo = @(chrom) cost_func_lift_moo(chrom, tasks_lift, agvs_lift, depots, agv_params, path_oracle);
        
        [pop_lift, objs_lift, fronts_lift, ~, hist_lift_dist, hist_lift_time, hist_lift_energy,gen_fronts_lift] = run_sub_nsga2_lift(tasks_lift, length(agvs_lift), ga_params, eval_lift_moo);
        
        front1_idx = fronts_lift{1}; 
        front1_objs = objs_lift(front1_idx, :);
        warn_if_front_invalid_once('实验组-托举车', front1_objs);
        
        min_dist_idx_in_front1 = get_front_min_index(front1_objs, 1);
        best_lift_chrom = pop_lift(front1_idx(min_dist_idx_in_front1), :);
        
        [sched_lift, best_objs_lift, batch_info_lift] = eval_lift_moo(best_lift_chrom);
        dist_lift = min(front1_objs(:, 1));
        time_lift = min(front1_objs(:, 2));
        energy_lift = min(front1_objs(:, 3));
        
        for i = 1:length(agvs_lift)
            best_schedule{agvs_lift(i)} = sched_lift{i};
            batch_details{agvs_lift(i)} = batch_info_lift{i}; 
        end
    end 
    if ~isempty(tasks_fork) && ~isempty(agvs_fork)
        disp('   -> 启动 NSGA-II 引擎优化叉车（多目标：距离、时间、能耗）...');
        eval_fork_moo = @(chrom) cost_func_fork_moo(chrom, tasks_fork, agvs_fork, depots, agv_params, path_oracle);
        
        [pop_fork, objs_fork, fronts_fork, ~, hist_fork_dist, hist_fork_time, hist_fork_energy,gen_fronts_fork] = run_sub_nsga2_fork(tasks_fork, length(agvs_fork), ga_params, eval_fork_moo);
        
        front1_idx = fronts_fork{1}; 
        front1_objs = objs_fork(front1_idx, :);
        warn_if_front_invalid_once('实验组-叉车', front1_objs);
        
        min_dist_idx_in_front1 = get_front_min_index(front1_objs, 1);
        best_fork_chrom = pop_fork(front1_idx(min_dist_idx_in_front1), :);
        
        [sched_fork, best_objs_fork] = eval_fork_moo(best_fork_chrom);
        dist_fork = min(front1_objs(:, 1));
        time_fork = min(front1_objs(:, 2));
        energy_fork = min(front1_objs(:, 3));
        
        for i = 1:length(agvs_fork)
            best_schedule{agvs_fork(i)} = sched_fork{i};
        end
    end
    metrics.lift.dist = dist_lift;       
    metrics.lift.time = time_lift;       
    metrics.lift.energy = energy_lift;   
    
    metrics.fork.dist = dist_fork;       
    metrics.fork.time = time_fork;       
    metrics.fork.energy = energy_fork;   
    
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
function [pop, pop_objs, fronts, cd, dist_hist, time_hist, energy_hist, gen_fronts_history] = run_sub_nsga2_lift(tasks, num_sub_agvs, ga_params, eval_func)
   
    num_tasks = size(tasks, 1);
    pop_size = ga_params.pop_size;
    
    max_gen = ga_params.max_gen;

    dist_hist = zeros(1, max_gen);
    time_hist = zeros(1, max_gen);
    energy_hist = zeros(1, max_gen);

    pc_max = 0.6; pc_min = 0.3;
    pm_max = 0.2; pm_min = 0.05;

    gen_fronts_history = cell(1, max_gen);

    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end

    pop_objs = evaluate_population_parallel(pop, eval_func);


    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);

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

            
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks);
            end
            

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

        off_objs = evaluate_population_parallel(offspring, eval_func);


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

        
        [pop, pop_objs] = enforce_population_diversity(pop, pop_objs, num_tasks, num_sub_agvs, eval_func);
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);

        front1 = fronts{1};
        dist_hist(gen) = min(pop_objs(front1, 1));
        time_hist(gen) = min(pop_objs(front1, 2));
        energy_hist(gen) = min(pop_objs(front1, 3));

        gen_fronts_history{gen} = pop_objs(front1, :);
    end
    

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
            real_task_ids = [real_task_ids, tasks(batches{b}, 1)'];
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
                [pick_rc, segment_dist, ~, feasible, debug_msg] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 1, current_payload);
                if ~feasible
                    report_infeasible_segment_once('实验组-托举车', curr_pos, target_id, 'pickup', current_payload, debug_msg);
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
                [drop_rc, segment_dist, ~, feasible, debug_msg] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'dropoff', 1, current_payload);
                if ~feasible
                    report_infeasible_segment_once('实验组-托举车', curr_pos, target_id, 'dropoff', current_payload, debug_msg);
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

            [pick_rc, d1, ~, feasible_pick, debug_msg] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, 'pickup', 2, 0);
            if ~feasible_pick
                report_infeasible_segment_once('实验组-叉车', curr_pos, target_id, 'pickup', 0, debug_msg);
                objectives = [inf, inf, inf];
                return;
            end

            [drop_rc, d2, ~, feasible_drop, debug_msg] = query_region_oracle_or_astar(path_oracle, pick_rc, target_id, 'dropoff', 2, task_weight);
            if ~feasible_drop
                report_infeasible_segment_once('实验组-叉车', pick_rc, target_id, 'dropoff', task_weight, debug_msg);
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
    gen_fronts_history = cell(1, max_gen);
    pop = zeros(pop_size, num_tasks * 2);
    for i = 1:pop_size
        pop(i, 1:num_tasks) = randperm(num_tasks);
        pop(i, num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
    end    
    
    pop_objs = evaluate_population_parallel(pop, eval_func);

    
    [fronts, rank] = fast_non_dominated_sorting(pop_objs);
    cd = calc_crowding_distance(pop_objs, fronts);
    
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
            
            if rand < pc
                [child1, child2] = crossover_IPOX_MPX(pop(p1_idx,:), pop(p2_idx,:), num_tasks); 
            end
            
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
        
        off_objs = evaluate_population_parallel(offspring, eval_func);

        
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
        
        [pop, pop_objs] = enforce_population_diversity(pop, pop_objs, num_tasks, num_sub_agvs, eval_func);
        [fronts, rank] = fast_non_dominated_sorting(pop_objs);
        cd = calc_crowding_distance(pop_objs, fronts);
        
        
        front1 = fronts{1};
        dist_hist(gen) = min(pop_objs(front1, 1));
        time_hist(gen) = min(pop_objs(front1, 2));
        energy_hist(gen) = min(pop_objs(front1, 3));
        gen_fronts_history{gen} = pop_objs(front1, :);
    end
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

function idx = get_front_min_index(front_objs, obj_col)
    if isempty(front_objs)
        idx = 1;
        return;
    end
    [~, idx] = min(front_objs(:, obj_col));
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

function [best_rc, best_dist, best_cost, feasible, debug_msg] = query_region_oracle_or_astar(path_oracle, curr_pos, target_id, phase, agv_type, payload_weight)
    best_rc = [];
    best_dist = inf;
    best_cost = inf;
    feasible = false;
    debug_msg = '';
    oracle_error_msg = '';

    if nargin >= 1 && ~isempty(path_oracle)
        try
            [best_rc, best_dist, best_cost, feasible] = ...
                region_distance_oracle('query', path_oracle, curr_pos, target_id, phase, agv_type);
        catch ME
            feasible = false;
            oracle_error_msg = ME.message;
        end
    end

    if feasible
        return;
    end

    [best_rc, best_dist, best_cost, feasible] = ...
        get_best_astar_segment(curr_pos, target_id, phase, agv_type, payload_weight);

    if ~feasible
        if ~isempty(oracle_error_msg)
            debug_msg = sprintf(['oracle查询失败且A*回退失败: %s | 起点=[%d,%d], 目标=%d, ' ...
                '阶段=%s, 车型=%d, 载重=%.3f'], ...
                oracle_error_msg, curr_pos(1), curr_pos(2), target_id, phase, agv_type, payload_weight);
        else
            debug_msg = build_astar_failure_debug_msg(curr_pos, target_id, phase, agv_type, payload_weight);
        end
    end
end

function debug_msg = build_astar_failure_debug_msg(curr_pos, target_id, phase, agv_type, payload_weight)
    [~, map_rows, map_cols] = get_ga_costmap(agv_type);
    planning_map = create_binary_grid_map(map_cols - 1, map_rows - 1, target_id);
    candidates = get_ga_target_candidates(target_id, phase);

    in_bounds = 0;
    free_cells = 0;
    for i = 1:size(candidates, 1)
        candidate = candidates(i, :);
        if candidate(1) >= 1 && candidate(1) <= map_rows && candidate(2) >= 1 && candidate(2) <= map_cols
            in_bounds = in_bounds + 1;
            if planning_map(candidate(1), candidate(2)) ~= 1
                free_cells = free_cells + 1;
            end
        end
    end

    if curr_pos(1) < 1 || curr_pos(1) > map_rows || curr_pos(2) < 1 || curr_pos(2) > map_cols
        debug_msg = sprintf(['A*回退失败: 起点越界, 起点=[%d,%d], 地图尺寸=[%d,%d], 目标=%d, ' ...
            '阶段=%s, 车型=%d, 载重=%.3f'], ...
            curr_pos(1), curr_pos(2), map_rows, map_cols, target_id, phase, agv_type, payload_weight);
        return;
    end

    debug_msg = sprintf(['A*回退失败: 起点=[%d,%d], 目标=%d, 阶段=%s, 车型=%d, 载重=%.3f, ' ...
        '候选点总数=%d, 边界内=%d, 可通行候选点=%d'], ...
        curr_pos(1), curr_pos(2), target_id, phase, agv_type, payload_weight, size(candidates, 1), in_bounds, free_cells);
end

function opts = get_ga_debug_options()
    opts = struct();
    opts.disable_oracle = false;
    opts.force_serial_evaluation = false;
    opts.max_parallel_workers = 4;
    opts.min_parallel_population = 20;
    opts.report_cache_stats = true;
    opts.cache_stats_print_every = 20;
end

function opts = get_ga_diversity_options()
    opts = struct();
    opts.enable_duplicate_repair = true;
    opts.duplicate_trigger_ratio = 0.08;
    opts.max_immigrant_ratio = 0.12;
    opts.max_generation_attempts = 6;
    opts.objective_round_digits = 6;
end

function [pop, pop_objs] = enforce_population_diversity(pop, pop_objs, num_tasks, num_sub_agvs, eval_func)
    opts = get_ga_diversity_options();
    if ~opts.enable_duplicate_repair || size(pop, 1) <= 2
        return;
    end

    pop_size = size(pop, 1);
    [~, first_idx, group_idx] = unique(pop, 'rows', 'stable');
    unique_count = numel(first_idx);
    chromosome_duplicate_ratio = 1 - unique_count / pop_size;

    rounded_objs = round(pop_objs, opts.objective_round_digits);
    [~, first_obj_idx, obj_group_idx] = unique(rounded_objs, 'rows', 'stable');
    unique_obj_count = numel(first_obj_idx);
    objective_duplicate_ratio = 1 - unique_obj_count / pop_size;

    duplicate_ratio = max(chromosome_duplicate_ratio, objective_duplicate_ratio);
    if duplicate_ratio < opts.duplicate_trigger_ratio
        return;
    end

    counts = accumarray(group_idx, 1);
    duplicate_mask = counts(group_idx) > 1;
    duplicate_idx = setdiff(find(duplicate_mask), first_idx, 'stable');

    obj_counts = accumarray(obj_group_idx, 1);
    duplicate_obj_mask = obj_counts(obj_group_idx) > 1;
    duplicate_obj_idx = setdiff(find(duplicate_obj_mask), first_obj_idx, 'stable');

    duplicate_idx = union(duplicate_idx, duplicate_obj_idx, 'stable');
    if isempty(duplicate_idx)
        return;
    end

    [fronts_tmp, rank_tmp] = fast_non_dominated_sorting(pop_objs);
    cd_tmp = calc_crowding_distance(pop_objs, fronts_tmp);

    preferred_idx = duplicate_idx(rank_tmp(duplicate_idx) > 1);
    if numel(preferred_idx) < numel(duplicate_idx)
        fallback_idx = setdiff(duplicate_idx, preferred_idx, 'stable');
        sort_criteria = [rank_tmp(fallback_idx), cd_tmp(fallback_idx)];
        [~, order] = sortrows(sort_criteria, [1, 2]);
        candidate_pool = [preferred_idx; fallback_idx(order)];
    else
        candidate_pool = preferred_idx;
    end

    replace_limit = max(1, min(round(pop_size * opts.max_immigrant_ratio), ...
        pop_size - min(unique_count, unique_obj_count)));
    replace_count = min(numel(candidate_pool), replace_limit);
    replace_idx = candidate_pool(1:replace_count);

    immigrants = zeros(replace_count, size(pop, 2));
    seen = pop;
    for ii = 1:replace_count
        immigrants(ii, :) = generate_unique_immigrant(seen, num_tasks, num_sub_agvs, opts.max_generation_attempts);
        seen = [seen; immigrants(ii, :)];
    end

    immigrant_objs = evaluate_population_parallel(immigrants, eval_func);
    pop(replace_idx, :) = immigrants;
    pop_objs(replace_idx, :) = immigrant_objs;
end

function chrom = generate_unique_immigrant(existing_pop, num_tasks, num_sub_agvs, max_attempts)
    chrom = [];
    for attempt = 1:max_attempts
        candidate = zeros(1, num_tasks * 2);
        candidate(1:num_tasks) = randperm(num_tasks);
        candidate(num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
        if isempty(existing_pop) || ~ismember(candidate, existing_pop, 'rows')
            chrom = candidate;
            return;
        end
    end

    chrom = zeros(1, num_tasks * 2);
    chrom(1:num_tasks) = randperm(num_tasks);
    chrom(num_tasks+1:end) = randi([1, num_sub_agvs], 1, num_tasks);
end

function report_infeasible_segment_once(tag, curr_pos, target_id, phase, payload_weight, debug_msg)
    persistent reported_msgs;
    if isempty(reported_msgs)
        reported_msgs = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    end

    key = sprintf('%s|%d|%d|%d|%s|%.3f', tag, curr_pos(1), curr_pos(2), target_id, lower(phase), payload_weight);
    if isKey(reported_msgs, key)
        return;
    end

    reported_msgs(key) = true;
    if isempty(debug_msg)
        debug_msg = sprintf('路径不可行: 起点=[%d,%d], 目标=%d, 阶段=%s, 载重=%.3f', ...
            curr_pos(1), curr_pos(2), target_id, phase, payload_weight);
    end
    fprintf('[路径诊断][%s] %s\n', tag, debug_msg);
end

function warn_if_front_invalid_once(tag, front_objs)
    persistent warned_tags;
    if isempty(warned_tags)
        warned_tags = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    end

    if isempty(front_objs)
        if ~isKey(warned_tags, [tag '|empty'])
            warned_tags([tag '|empty']) = true;
            fprintf('[前沿诊断][%s] 第一前沿为空，当前指标无法正常统计。\n', tag);
        end
        return;
    end

    if all(all(~isfinite(front_objs)))
        if ~isKey(warned_tags, [tag '|allinf'])
            warned_tags([tag '|allinf']) = true;
            fprintf('[前沿诊断][%s] 第一前沿全部为 Inf，说明当前种群解被整体判为不可行。\n', tag);
        end
    end
end

function pop_objs = evaluate_population_parallel(population, eval_func)
    persistent eval_obj_cache eval_cache_stats;
    num_individuals = size(population, 1);
    pop_objs = zeros(num_individuals, 3);
    if num_individuals == 0
        return;
    end

    if isempty(eval_obj_cache)
        eval_obj_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    elseif eval_obj_cache.Count > 50000
        eval_obj_cache = containers.Map('KeyType', 'char', 'ValueType', 'any');
    end
    if isempty(eval_cache_stats)
        eval_cache_stats = struct('calls', 0, 'total_individuals', 0, 'total_unique', 0, ...
            'total_cache_hits', 0, 'total_new_evals', 0);
    end

    [unique_population, ~, population_map] = unique(population, 'rows', 'stable');
    num_unique = size(unique_population, 1);
    unique_objs = zeros(num_unique, 3);
    cache_prefix = sprintf('%s|L=%d|', func2str(eval_func), size(population, 2));
    missing_mask = true(num_unique, 1);
    missing_keys = cell(num_unique, 1);

    for idx = 1:num_unique
        cache_key = [cache_prefix, sprintf('%.12g,', unique_population(idx, :))];
        missing_keys{idx} = cache_key;
        if isKey(eval_obj_cache, cache_key)
            unique_objs(idx, :) = eval_obj_cache(cache_key);
            missing_mask(idx) = false;
        end
    end

    missing_idx = find(missing_mask);
    cache_hits = num_unique - numel(missing_idx);
    duplicate_count = num_individuals - num_unique;
    if isempty(missing_idx)
        eval_cache_stats.calls = eval_cache_stats.calls + 1;
        eval_cache_stats.total_individuals = eval_cache_stats.total_individuals + num_individuals;
        eval_cache_stats.total_unique = eval_cache_stats.total_unique + num_unique;
        eval_cache_stats.total_cache_hits = eval_cache_stats.total_cache_hits + cache_hits;
        maybe_report_eval_cache_stats('实验组', eval_cache_stats, num_individuals, num_unique, duplicate_count, cache_hits, 0, get_ga_debug_options());
        pop_objs = unique_objs(population_map, :);
        return;
    end

    debug_opts = get_ga_debug_options();
    if ~debug_opts.force_serial_evaluation && ...
       numel(missing_idx) >= debug_opts.min_parallel_population && ...
       use_parallel_evaluation_local()
        try
            missing_objs = zeros(numel(missing_idx), 3);
            parfor j = 1:numel(missing_idx)
                idx = missing_idx(j);
                [~, obj] = eval_func(unique_population(idx, :));
                missing_objs(j, :) = obj;
            end
            for j = 1:numel(missing_idx)
                idx = missing_idx(j);
                unique_objs(idx, :) = missing_objs(j, :);
                eval_obj_cache(missing_keys{idx}) = missing_objs(j, :);
            end
        catch ME
            warning('GA:ParallelEvalFallback', ...
                '实验组并行评估失败，已自动回退串行 for: %s', ME.message);
            for j = 1:numel(missing_idx)
                idx = missing_idx(j);
                [~, obj] = eval_func(unique_population(idx, :));
                unique_objs(idx, :) = obj;
                eval_obj_cache(missing_keys{idx}) = obj;
            end
        end
    else
        for j = 1:numel(missing_idx)
            idx = missing_idx(j);
            [~, obj] = eval_func(unique_population(idx, :));
            unique_objs(idx, :) = obj;
            eval_obj_cache(missing_keys{idx}) = obj;
        end
    end

    eval_cache_stats.calls = eval_cache_stats.calls + 1;
    eval_cache_stats.total_individuals = eval_cache_stats.total_individuals + num_individuals;
    eval_cache_stats.total_unique = eval_cache_stats.total_unique + num_unique;
    eval_cache_stats.total_cache_hits = eval_cache_stats.total_cache_hits + cache_hits;
    eval_cache_stats.total_new_evals = eval_cache_stats.total_new_evals + numel(missing_idx);
    maybe_report_eval_cache_stats('实验组', eval_cache_stats, num_individuals, num_unique, duplicate_count, cache_hits, numel(missing_idx), debug_opts);

    pop_objs = unique_objs(population_map, :);
end

function maybe_report_eval_cache_stats(tag, stats, num_individuals, num_unique, duplicate_count, cache_hits, new_evals, debug_opts)
    if ~isfield(debug_opts, 'report_cache_stats') || ~debug_opts.report_cache_stats
        return;
    end

    print_every = 20;
    if isfield(debug_opts, 'cache_stats_print_every') && ~isempty(debug_opts.cache_stats_print_every)
        print_every = max(1, round(debug_opts.cache_stats_print_every));
    end

    should_print = stats.calls <= 3 || mod(stats.calls, print_every) == 0 || cache_hits > 0;
    if ~should_print
        return;
    end

    duplicate_ratio = duplicate_count / max(num_individuals, 1);
    cumulative_hit_ratio = stats.total_cache_hits / max(stats.total_unique, 1);
    fprintf('[缓存统计][%s] 第%d次评估: 总个体=%d | 唯一=%d | 重复=%d(%.1f%%%%) | 缓存命中=%d | 新评估=%d | 累计命中率=%.1f%%%%\n', ...
        tag, stats.calls, num_individuals, num_unique, duplicate_count, duplicate_ratio * 100, ...
        cache_hits, new_evals, cumulative_hit_ratio * 100);
end

function report_parallel_evaluation_status()
    persistent status_reported;

    if isempty(status_reported)
        status_reported = false;
    end

    if status_reported
        return;
    end

    debug_opts = get_ga_debug_options();
    if debug_opts.force_serial_evaluation
        is_parallel = false;
        status_msg = '调试模式已强制关闭 parfor，当前固定使用串行 for。';
    elseif debug_opts.min_parallel_population > 0
        is_parallel = false;
        status_msg = sprintf('按规模启用并行：待评估个体数小于 %d 时直接使用串行 for。', ...
            debug_opts.min_parallel_population);
    else
        [is_parallel, status_msg] = use_parallel_evaluation_local(true);
    end

    if is_parallel
        fprintf('[并行评估] 已启用 parfor: %s\n', status_msg);
    else
        fprintf('[并行评估] 当前使用串行 for: %s\n', status_msg);
    end

    status_reported = true;
end

function [tf, status_msg] = use_parallel_evaluation_local(force_refresh)
    persistent parallel_ready parallel_enabled parallel_status_msg;
    debug_opts = get_ga_debug_options();

    if nargin < 1
        force_refresh = false;
    end

    if debug_opts.force_serial_evaluation
        tf = false;
        status_msg = '调试模式已强制关闭并行评估';
        return;
    end

    if isempty(parallel_ready) || force_refresh
        parallel_ready = true;
        parallel_enabled = false;
        parallel_status_msg = '未检测到 Parallel Computing Toolbox';

        has_toolbox = license('test', 'Distrib_Computing_Toolbox') && ~isempty(ver('parallel'));
        if has_toolbox
            try
                desired_workers = max(1, round(debug_opts.max_parallel_workers));
                pool = gcp('nocreate');
                if isempty(pool)
                    try
                        parpool('Processes', desired_workers);
                        parallel_status_msg = sprintf('已创建进程并行池（%d workers）', desired_workers);
                    catch ME_process
                        try
                            parpool();
                            parallel_status_msg = sprintf('进程并行池启动失败，已回退并创建默认并行池: %s', ...
                                ME_process.message);
                        catch ME_default
                            error('parallelPoolStartup:Failed', ...
                                '进程并行池启动失败: %s | 默认并行池启动失败: %s', ...
                                ME_process.message, ME_default.message);
                        end
                    end
                else
                    if isprop(pool, 'NumWorkers') && pool.NumWorkers > desired_workers
                        delete(pool);
                        pool = parpool('Processes', desired_workers); %#ok<NASGU>
                        parallel_status_msg = sprintf('检测到过大的现有并行池，已重建为 %d workers', desired_workers);
                    else
                        pool_type = class(pool);
                        if isprop(pool, 'NumWorkers')
                            parallel_status_msg = sprintf('复用已有并行池 (%s, %d workers)', pool_type, pool.NumWorkers);
                        else
                            parallel_status_msg = sprintf('复用已有并行池 (%s)', pool_type);
                        end
                    end
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
    cache_key = sprintf('%d|%d|%s|%d|%d|%s', ...
        agv_type, target_id, phase, curr_pos(1), curr_pos(2), payload_key);
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

    segment_cache(cache_key) = struct( ...
        'best_rc', best_rc, ...
        'best_dist', best_dist, ...
        'best_cost', best_cost, ...
        'feasible', feasible);
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
    global mapW mapH;
    global costmap_type1 costmap_type2;
    if isempty(mapW) || isempty(mapH)
        mapW = 70;
        mapH = 50;
    end
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








    child = chrom;
    if num_tasks < 2
        return;
    end

    tau1 = rand(); 
    tau2 = rand();

    
    tau1_prime = tau1 - 0.3 * (1 - g/G); 

    if tau1_prime < tau2
        if parent_rank_idx > 0.6 * PN
            
            
            range = sort(randperm(num_tasks, 2));
            
            child(range(1):range(2)) = fliplr(child(range(1):range(2)));
        else
            pos = randperm(num_tasks, 2);
            agv_pos = pos + num_tasks;

            ta = child(agv_pos(1)); 
            child(agv_pos(1)) = child(agv_pos(2)); 
            child(agv_pos(2)) = ta;
            
        end
    else
        if parent_rank_idx > 0.2 * PN
            
            pts = randperm(num_tasks, 2);
            extract_idx = pts(1); 
            insert_idx = pts(2);

            extracted_task = child(extract_idx);
            extracted_agv = child(extract_idx + num_tasks);

            
            child(extract_idx) = []; 
            
            
            child(extract_idx + num_tasks - 1) = [];

            
            
            
            
            child = [child(1:insert_idx-1), extracted_task, child(insert_idx:num_tasks-1), ...
                     child(num_tasks:num_tasks+insert_idx-2), extracted_agv, child(num_tasks+insert_idx-1:end)];
            
            
            
        else
            
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

function [child1, child2] = crossover_IPOX_MPX(p1, p2, num_tasks)
    if num_tasks < 2
        child1 = p1;
        child2 = p2;
        return;
    end
    
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








