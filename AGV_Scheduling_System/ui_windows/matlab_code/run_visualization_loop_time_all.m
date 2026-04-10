function run_visualization_loop_time_all(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    
    global mapW mapH; 
    
    % --- 1. 初始化图形界面 ---
    generate_beautiful_factory_map();   
    f_map = gcf;                        
    ax = findobj(f_map, 'Type', 'Axes'); 
    hold(ax, 'on');                      
    set(f_map, 'Name', '实时动态调度仿真', 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', 'Position', [50, 200, 1000, 700]);
    
    [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs);
    
    % --- 2. 初始化 AGV 对象 ---
    [AGVs, props, ~] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax);
    
    % --- 3. 实时仿真主循环 ---
    disp('>> [系统] 实时仿真启动...'); 

    for k = 1:num_agvs
        AGVs(k).total_turns = 0;           % 运行转弯总数
        AGVs(k).last_dir = [0, 0];         % 上一步方向矢量
        
        AGVs(k).pick_queue = [];           % 取货任务队列
        AGVs(k).drop_queue = [];           % 卸货任务队列
        AGVs(k).active_task_id = 0;        % 当前正在导航的具体子任务ID
        AGVs(k).interrupted_status = '';   % 记忆因没电去充电前被中断的状态
    end 
    sim_running = true;      
    MAX_STEPS = 500000;      
    t = 0;                   
    frames_per_step = 2;
    max_task_id = max(task_list(:,1));
    task_row_map = zeros(max_task_id, 1);
    for row_idx = 1:size(task_list, 1)
        task_id = task_list(row_idx, 1);
        if task_id >= 1 && task_id <= max_task_id
            task_row_map(task_id) = row_idx;
        end
    end
    task_times = zeros(max_task_id, 2); 
    task_executor = zeros(max_task_id, 1);     
    task_start_dist = zeros(max_task_id, 1);   
    task_dist_record = zeros(max_task_id, 1);  
    for k = 1:num_agvs, AGVs(k).total_dist = 0; end
    task_trajectories = cell(max_task_id, 1);
    reported_conflict_keys = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    while sim_running && t < MAX_STEPS   
        t = t + 1;                       
        all_finished = true;   
        run_sliding_window_radar(t, task_list);
        % --- A. 逻辑更新 ---
        for k = 1:num_agvs   
            if AGVs(k).move_timer > 0      
                AGVs(k).move_timer = AGVs(k).move_timer - 1; 
                all_finished = false;       
                continue;                    
            end
            
            % 动态设置专属车位/充电桩尺寸
            if AGVs(k).type == 2
                agv_area_sz = [3, 3]; % 叉车大尺寸
            else
                agv_area_sz = [2, 2]; % 托举小尺寸
            end
            
            % 根据当前状态执行相应行为
            switch AGVs(k).status
                case 'Idle'   % 空闲状态
                    if AGVs(k).battery < 20   
                        plan_to_charge(k,t);     
                        all_finished = false;
                        
                    elseif AGVs(k).active_task_id > 0
                        tid = AGVs(k).active_task_id;
                        row_idx = get_task_row(tid);
                        if row_idx == 0
                            AGVs(k).active_task_id = 0;
                            all_finished = false;
                            continue;
                        end
                        target_id = task_list(row_idx, 2);
                        
                        if strcmp(AGVs(k).interrupted_status, 'Moving_Drop')
                            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
                            if plan_path(k, drop_anchor, drop_size, t) 
                                AGVs(k).status = 'Moving_Drop';
                                AGVs(k).interrupted_status = ''; 
                            end
                        elseif strcmp(AGVs(k).interrupted_status, 'Moving_Pick')
                            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
                            if plan_path(k, pick_anchor, pick_size, t)
                                AGVs(k).status = 'Moving_Pick';
                                AGVs(k).interrupted_status = '';
                            end     
                        else
                            AGVs(k).active_task_id = 0; % 非法记忆则重置
                        end
                        all_finished = false;
                        
                    elseif ~isempty(AGVs(k).tasks)  
                        max_load_capacity = 80;
                        batch_tasks = [];
                        current_batch_weight = 0;
                        
                        for i = 1:length(AGVs(k).tasks)
                            tid = AGVs(k).tasks(i);
                            row_idx = get_task_row(tid);
                            if row_idx == 0
                                continue;
                            end
                            w = task_list(row_idx, 3);
                            
                            if AGVs(k).type == 2 && i > 1
                                break; 
                            end
                            
                            if i == 1 || (current_batch_weight + w <= max_load_capacity)
                                batch_tasks = [batch_tasks, tid];
                                current_batch_weight = current_batch_weight + w;
                            else
                                break;
                            end
                        end
                        
                        AGVs(k).pick_queue = batch_tasks;
                        AGVs(k).drop_queue = batch_tasks;
                        
                        first_tid = AGVs(k).pick_queue(1);
                        AGVs(k).pick_queue(1) = [];
                        AGVs(k).active_task_id = first_tid;
                        
                        row_idx = get_task_row(first_tid);
                        if row_idx == 0
                            AGVs(k).pick_queue = [];
                            AGVs(k).drop_queue = [];
                            AGVs(k).active_task_id = 0;
                            all_finished = false;
                            continue;
                        end
                        target_id = task_list(row_idx, 2);
                        [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); 
                        
                        if plan_path(k, pick_anchor, pick_size, t)
                            AGVs(k).status = 'Moving_Pick';      
                        else
                            AGVs(k).pick_queue = [];
                            AGVs(k).drop_queue = [];
                            AGVs(k).active_task_id = 0;
                        end
                        all_finished = false;
                        
                    else   
                        charge_pos = props(AGVs(k).type).charge; 
                        home_pos = AGVs(k).home_pos;              
                        if AGVs(k).battery < 95                    
                            if check_in_area(AGVs(k).pos, charge_pos, agv_area_sz)      
                                AGVs(k).status = 'Charging';          
                                AGVs(k).wait_timer = 5;                
                            else
                                plan_to_charge(k,t);                     
                            end
                            all_finished = false;
                        elseif ~check_in_area(AGVs(k).pos, home_pos, agv_area_sz)        
                            if plan_path(k, home_pos, agv_area_sz, t)
                                AGVs(k).status = 'Go_Home';           
                            end
                            all_finished = false;
                        end
                    end
                    
                case {'Moving_Pick', 'Moving_Drop', 'Go_Home', 'Going_Charge', 'Yielding'}  
                    all_finished = false;
                    if AGVs(k).battery < 20 && ~strcmp(AGVs(k).status, 'Going_Charge') && ~strcmp(AGVs(k).status, 'Charging')
                        disp(['AGV-', num2str(k), ' 电量耗尽，保留队列现场，前往充电']);
                        AGVs(k).interrupted_status = AGVs(k).status; 
                        plan_to_charge(k,t);   
                        continue;              
                    end
                    
                    move_status = execute_move(k);  
                    if move_status == 1               
                        handle_arrival(k, task_list); 
                    elseif move_status < 0            
                        blocker_id = -move_status;     
                        resolve_conflict(k, blocker_id, task_list, t); 
                    end
                    
                case {'Loading', 'Unloading', 'Charging'}  
                    all_finished = false;
                    AGVs(k).wait_timer = AGVs(k).wait_timer - 1;  
                    
                    if strcmp(AGVs(k).status, 'Charging')        
                        AGVs(k).battery = min(100, AGVs(k).battery + 2.0); 
                        if AGVs(k).battery >= 100 && AGVs(k).wait_timer <= 0  
                            AGVs(k).status = 'Idle'; 
                        end
                    end
                    
                    if AGVs(k).wait_timer <= 0 && ~strcmp(AGVs(k).status, 'Charging') && ~strcmp(AGVs(k).status, 'Go_Home')
                        finish_waiting(k, task_list);   
                    end
            end
        end
        if all_finished, break; end   
        
        % --- B. 动画显示 ---
        for f = 1:frames_per_step   
            curr_bat_list = zeros(1, num_agvs);  
            for k = 1:num_agvs
                target_r = AGVs(k).pos(1); target_c = AGVs(k).pos(2); 
                curr_r = AGVs(k).vis_pos(1); curr_c = AGVs(k).vis_pos(2); 
                
                AGVs(k).vis_pos(1) = curr_r + (target_r - curr_r) * 0.3;
                AGVs(k).vis_pos(2) = curr_c + (target_c - curr_c) * 0.3;
                
                update_agv_plot(AGVs(k));   
                curr_bat_list(k) = AGVs(k).battery;      
                
                if ~isempty(AGVs(k).path) && AGVs(k).path_idx <= size(AGVs(k).path, 1)
                    rem_path = AGVs(k).path(AGVs(k).path_idx:end, :); 
                    set(AGVs(k).path_line, 'XData', rem_path(:,2) - 0.5, 'YData', rem_path(:,1) - 0.5); 
                else
                    set(AGVs(k).path_line, 'XData', NaN, 'YData', NaN); 
                end
            end
            update_battery_monitor(f_batt, b_handle, t_handles, curr_bat_list); 
            drawnow limitrate;                           
            pause(0.01);                                  
        end
    end
    export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories);
    disp('>> 仿真结束。');                              
    
    disp('========================================');
    disp('         AGV 运行总转弯次数统计      ');
    disp('========================================');
    for k = 1:num_agvs
        agv_type_str = '未知';
        if AGVs(k).type == 1, agv_type_str = '托举式'; end
        if AGVs(k).type == 2, agv_type_str = '叉车式'; end
        fprintf('  AGV-%02d (%s)  |  共转弯 %d 次\n', k, agv_type_str, AGVs(k).total_turns);
    end
    disp('========================================');
    
    function resolve_conflict(id_self, id_blocker, tasks_info, current_t)            
        pos_self = AGVs(id_self).pos;          
        target_self = AGVs(id_self).path(AGVs(id_self).path_idx, 1:2); 
        dir_self = target_self - pos_self;     % 提取方向矢量 d1
        pos_blocker = AGVs(id_blocker).pos;            
        moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home'};
        is_blocker_in_moving_state = ismember(AGVs(id_blocker).status, moving_states);
        has_path = ~isempty(AGVs(id_blocker).path) && AGVs(id_blocker).path_idx <= size(AGVs(id_blocker).path, 1);        
        if is_blocker_in_moving_state && has_path
            true_target_blocker = AGVs(id_blocker).path(AGVs(id_blocker).path_idx, 1:2); 
            dir_blocker = true_target_blocker - pos_blocker; 
            
            if AGVs(id_blocker).move_timer > 0
                v_blocker = 0.001; 
            else
                v_blocker = 1.0 / AGVs(id_blocker).step_dur; 
            end
            target_blocker = true_target_blocker;
        else
            true_target_blocker = pos_blocker;
            target_blocker = pos_blocker;      
            dir_blocker = [0, 0];
            v_blocker = 0;                     
        end
        dot_product = dir_self(1)*dir_blocker(1) + dir_self(2)*dir_blocker(2);
        c_type = 0; conflict_name = '未知冲突';
        
        % 定义状态标志位
        is_swapping = isequal(target_self, pos_blocker) && isequal(true_target_blocker, pos_self);
        is_same_target = isequal(target_self, target_blocker); 
        
        if is_swapping
            c_type = 1; conflict_name = '相向冲突(交换)';        
            
        elseif isequal(target_self, pos_blocker)
            if v_blocker == 0
                c_type = 3; conflict_name = '占位冲突'; 
            elseif dot_product > 0
                c_type = 4; conflict_name = '追尾冲突';
            else
                c_type = 3; conflict_name = '占位冲突(动态让出)';
            end
            
        elseif is_same_target
            if dot_product < 0
                c_type = 1; conflict_name = '相向冲突(相遇)';
            else
                c_type = 2; conflict_name = '节点冲突';
            end
        end
        
        conflict_pair = sort([id_self, id_blocker]);
        conflict_key = sprintf('%d_%d_%d', current_t, conflict_pair(1), conflict_pair(2));
        should_handle_conflict = ~isKey(reported_conflict_keys, conflict_key);
        if ~should_handle_conflict
            return;
        end
        reported_conflict_keys(conflict_key) = true;
        disp(['[Conflict] T=', num2str(current_t), ' ', conflict_name, ' (AGV-', num2str(id_self), ' -> AGV-', num2str(id_blocker), ')']);

        % Report and resolve each conflict only once for the same AGV pair at the same step.
        if ~send_conflict_webhook(current_t, id_self, pos_self, id_blocker, pos_blocker, conflict_name)
            fprintf('[Webhook] Conflict event send failed and was written to local log: T=%d, AGV-%d vs AGV-%d\n', current_t, id_self, id_blocker);
        end

        P_self = calculate_ahp_priority(AGVs(id_self), tasks_info, current_t);
        P_blocker = calculate_ahp_priority(AGVs(id_blocker), tasks_info, current_t);
        should_self_yield = (P_self < P_blocker) || (P_self == P_blocker && id_self > id_blocker);
        if should_self_yield
            loser_id = id_self;
            winner_id = id_blocker;
        else
            loser_id = id_blocker;
            winner_id = id_self;
        end
        fprintf('Conflict resolve: AGV-%d priority = %.2f, AGV-%d priority = %.2f | loser = AGV-%d, winner = AGV-%d\n', ...
            id_self, P_self, id_blocker, P_blocker, loser_id, winner_id);

        % Apply the mitigation directly to the lower-priority AGV, even if the higher-priority AGV detected the conflict first.
        if c_type == 1 
            % Head-on conflict: yield by retreating to a temporary safe node first.
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' retreats to a temporary yield node.']);
            success = plan_yield_path(loser_id, winner_id, current_t);
            if ~success && ~isempty(AGVs(loser_id).target_node)
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t);
            end
            if ~success
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 6);
            end
        elseif c_type == 2
            % Node conflict: lower-priority AGV waits before retrying.
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' waits before retrying.']);
            AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 6);
        elseif c_type == 3
            % Occupancy conflict: lower-priority AGV replans or backs off briefly.
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' attempts a detour around the occupied node.']);
            if ~isempty(AGVs(loser_id).target_node) 
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t); 
                if ~success
                    AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 6);
                end
            else
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 6);
            end 
        elseif c_type == 4
            % Rear-end conflict: lower-priority AGV replans or slows down.
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' replans or slows down.']);
            if ~isempty(AGVs(loser_id).target_node) 
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t); 
                if ~success
                    AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 6);
                end
            else
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 6);
            end
        end

    end

    function plan_to_charge(id, current_t)
        if isfield(props(AGVs(id).type), 'charge_stations') && ~isempty(props(AGVs(id).type).charge_stations)
            candidate_stations = props(AGVs(id).type).charge_stations;
        else
            candidate_stations = props(AGVs(id).type).charge;
        end

        if AGVs(id).type == 2
            charge_area_sz = [3, 3];
        else
            charge_area_sz = [2, 2];
        end

        best_cost = inf;
        best_station = [];
        best_station_target = [];
        best_station_path = [];

        for s = 1:size(candidate_stations, 1)
            station_pos = candidate_stations(s, :);
            is_occupied = false;
            for other = 1:num_agvs
                if other == id, continue; end
                if isequal(AGVs(other).pos, station_pos) || isequal(AGVs(other).target_node, station_pos)
                    if ismember(AGVs(other).status, {'Charging', 'Going_Charge'})
                        is_occupied = true;
                        break;
                    end
                end
            end

            if ~is_occupied
                [candidate_path, candidate_target, candidate_cost] = find_best_target_path(id, station_pos, charge_area_sz, 'charge');
                if ~isempty(candidate_path) && candidate_cost < best_cost
                    best_cost = candidate_cost;
                    best_station = station_pos;
                    best_station_target = candidate_target;
                    best_station_path = candidate_path;
                end
            end
        end

        if ~isempty(best_station)
            assign_planned_path(id, best_station_path, best_station_target, current_t);
            AGVs(id).status = 'Going_Charge';
        else
            AGVs(id).move_timer = 3;
        end
    end

    function [best_path, best_target, best_cost] = find_best_target_path(id, target_anchor, area_size, planning_mode)
        if nargin < 3 || isempty(area_size), area_size = [2, 2]; end
        if nargin < 4 || isempty(planning_mode), planning_mode = 'task'; end

        virtual_target_id = 0;
        if strcmp(planning_mode, 'charge')
            if AGVs(id).type == 1, virtual_target_id = 17; end
            if AGVs(id).type == 2, virtual_target_id = 18; end
        else
            if AGVs(id).type == 1, virtual_target_id = 1; end
            if AGVs(id).type == 2, virtual_target_id = 13; end
        end

        tempMap = create_binary_grid_map(mapW, mapH, virtual_target_id);
        area_h = area_size(1); area_w = area_size(2);
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr; c = target_anchor(2) + dc;
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    tempMap(r, c) = 0;
                end
            end
        end

        valid_targets = [];
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr; c = target_anchor(2) + dc;
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    occupied = false;
                    for other = 1:num_agvs
                        if other == id, continue; end
                        is_pos_occupied = (AGVs(other).pos(1) == r && AGVs(other).pos(2) == c);
                        is_target_occupied = ~isempty(AGVs(other).target_node) && ...
                                             (AGVs(other).target_node(1) == r && AGVs(other).target_node(2) == c);
                        if is_pos_occupied || is_target_occupied
                            occupied = true;
                            break;
                        end
                    end
                    if ~occupied
                        valid_targets = [valid_targets; r, c]; %#ok<AGROW>
                    end
                end
            end
        end

        best_path = [];
        best_target = [];
        best_cost = inf;
        if isempty(valid_targets)
            return;
        end

        current_weight = 0;
        if isfield(AGVs(id), 'payload_weight') && AGVs(id).load == 1
            current_weight = AGVs(id).payload_weight;
        end

        curr_pos = AGVs(id).pos;
        for idx = 1:size(valid_targets, 1)
            candidate_target = valid_targets(idx, :);
            evalMap = tempMap;
            evalMap(curr_pos(1), curr_pos(2)) = 0;

            for other = 1:num_agvs
                if other ~= id
                    pos_r = AGVs(other).pos(1);
                    pos_c = AGVs(other).pos(2);
                    if ~(pos_r == candidate_target(1) && pos_c == candidate_target(2))
                        evalMap(pos_r, pos_c) = 1;
                    end
                end
            end

            [candidate_path, candidate_cost, ~, ~, ~, ~] = astar_planner_turn3(evalMap, curr_pos, candidate_target, current_weight, [], AGVs(id).type);
            if ~isempty(candidate_path) && candidate_cost < best_cost
                best_cost = candidate_cost;
                best_target = candidate_target;
                best_path = candidate_path;
            end
        end
    end

    function assign_planned_path(id, path, actual_target, current_t)
        path_length = size(path, 1);
        time_stamps = zeros(path_length, 1);
        step_time = AGVs(id).step_dur;
        for p_idx = 1:path_length
            time_stamps(p_idx) = current_t + (p_idx - 1) * step_time;
        end

        AGVs(id).path = [path, time_stamps];
        AGVs(id).path_idx = 2;
        AGVs(id).target_node = actual_target;
    end

    function row_idx = get_task_row(task_id)
        row_idx = 0;
        if isempty(task_id) || task_id < 1 || task_id > numel(task_row_map)
            return;
        end
        row_idx = task_row_map(task_id);
    end

    function success = plan_path(id, target_anchor, area_size, current_t, planning_mode)
        if nargin < 3 || isempty(area_size), area_size = [2, 2]; end
        if nargin < 5 || isempty(planning_mode), planning_mode = 'task'; end

        [path, actual_target, ~] = find_best_target_path(id, target_anchor, area_size, planning_mode);
        if ~isempty(path)
            assign_planned_path(id, path, actual_target, current_t);
            success = true;
        else
            success = false;
        end
    end

    function success = plan_yield_path(id, blocker_id, current_t)
        success = false;
        curr_pos = AGVs(id).pos;
        blocker_pos = AGVs(blocker_id).pos;
        current_gap = abs(curr_pos(1) - blocker_pos(1)) + abs(curr_pos(2) - blocker_pos(2));
        candidate_nodes = [];

        if ~isempty(AGVs(id).path)
            backtrack_indices = [AGVs(id).path_idx - 2, AGVs(id).path_idx - 3];
            for idx = backtrack_indices
                if idx >= 1 && idx <= size(AGVs(id).path, 1)
                    candidate_nodes = [candidate_nodes; AGVs(id).path(idx, 1:2)]; %#ok<AGROW>
                end
            end
        end

        directions = [-1, 0; 1, 0; 0, -1; 0, 1];
        for d = 1:size(directions, 1)
            candidate = curr_pos + directions(d, :);
            if candidate(1) < 1 || candidate(1) > mapH || candidate(2) < 1 || candidate(2) > mapW
                continue;
            end
            candidate_nodes = [candidate_nodes; candidate]; %#ok<AGROW>
        end

        if isempty(candidate_nodes)
            return;
        end

        [~, unique_idx] = unique(candidate_nodes, 'rows', 'stable');
        candidate_nodes = candidate_nodes(unique_idx, :);
        candidate_gaps = abs(candidate_nodes(:, 1) - blocker_pos(1)) + abs(candidate_nodes(:, 2) - blocker_pos(2));
        candidate_nodes = [candidate_nodes, candidate_gaps];
        candidate_nodes = sortrows(candidate_nodes, -3);

        original_status = AGVs(id).status;
        for c_idx = 1:size(candidate_nodes, 1)
            candidate = candidate_nodes(c_idx, 1:2);
            if isequal(candidate, curr_pos) || isequal(candidate, blocker_pos)
                continue;
            end
            if candidate_nodes(c_idx, 3) < current_gap
                continue;
            end
            if plan_path(id, candidate, [1, 1], current_t)
                AGVs(id).yield_resume_status = original_status;
                AGVs(id).status = 'Yielding';
                success = true;
                return;
            end
        end
    end

    function status = execute_move(id)
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            status = 1; return; 
        end        
        curr_pos = AGVs(id).pos;
        next_node_3d = AGVs(id).path(AGVs(id).path_idx, :); 
        nr = next_node_3d(1); nc = next_node_3d(2); 
        target_t = next_node_3d(3);
        for other = 1:num_agvs
            if other == id, continue; end
            
            other_curr = AGVs(other).pos;
            
            moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home', 'Yielding'};
            is_other_moving = ~isempty(AGVs(other).path) && ...
                              AGVs(other).path_idx <= size(AGVs(other).path, 1) && ...
                              AGVs(other).move_timer <= 0 && ...
                              ismember(AGVs(other).status, moving_states);
                              
            if is_other_moving
                other_next_3d = AGVs(other).path(AGVs(other).path_idx, :);
                other_next_r = other_next_3d(1);
                other_next_c = other_next_3d(2);
                other_next_t = other_next_3d(3);
            else
                other_next_r = other_curr(1);
                other_next_c = other_curr(2);
                other_next_t = target_t; 
            end
            
            if nr == other_next_r && nc == other_next_c
                status = -other; return;
            end
            
            if nr == other_curr(1) && nc == other_curr(2) && ...
               other_next_r == curr_pos(1) && other_next_c == curr_pos(2)
                status = -other; return;
            end
            
            if nr == other_curr(1) && nc == other_curr(2) && target_t <= other_next_t
                status = -other; return;
            end
        end
        AGVs(id).pos = [nr, nc];                       
        curr_dir = [nr - curr_pos(1), nc - curr_pos(2)]; 
        if ~isequal(AGVs(id).last_dir, [0, 0]) && ~isequal(AGVs(id).last_dir, curr_dir)
            AGVs(id).total_turns = AGVs(id).total_turns + 1; 
        end
        AGVs(id).last_dir = curr_dir; 
        tid = AGVs(id).active_task_id;
        if tid > 0, task_trajectories{tid} = [task_trajectories{tid}; AGVs(id).pos]; end
        if ~isempty(AGVs(id).tasks)
            for i = 1:length(AGVs(id).tasks)
                q_tid = AGVs(id).tasks(i);
                if q_tid ~= tid && task_times(q_tid, 1) > 0
                    task_trajectories{q_tid} = [task_trajectories{q_tid}; AGVs(id).pos];
                end
            end
        end
        
        AGVs(id).total_dist = AGVs(id).total_dist + 1;
        AGVs(id).path_idx = AGVs(id).path_idx + 1;      
        AGVs(id).move_timer = AGVs(id).step_dur;         
        
        e_b = agv_params(id).e_base; e_l = agv_params(id).e_load_factor;
        cost = (e_b + e_l * AGVs(id).payload_weight / 100.0); 
        AGVs(id).battery = max(0, AGVs(id).battery - cost);
        
        if AGVs(id).path_idx > size(AGVs(id).path, 1)
            AGVs(id).last_dir = [0, 0]; status = 1; 
        else
            status = 0; 
        end
    end
    
    function handle_arrival(id, ~)
        st = AGVs(id).status;
        if strcmp(st, 'Moving_Pick')
            AGVs(id).status = 'Loading'; AGVs(id).wait_timer = 6; 
        elseif strcmp(st, 'Moving_Drop')
            AGVs(id).status = 'Unloading'; AGVs(id).wait_timer = 6; 
        elseif strcmp(st, 'Going_Charge')
            AGVs(id).status = 'Charging'; AGVs(id).wait_timer = 30; 
        elseif strcmp(st, 'Go_Home')
            AGVs(id).status = 'Idle'; 
        elseif strcmp(st, 'Yielding')
            resume_after_yield(id, t);
        end
    end

    function resume_after_yield(id, current_t)
        resume_status = AGVs(id).yield_resume_status;
        if isempty(resume_status)
            AGVs(id).status = 'Idle';
            return;
        end

        if strcmp(resume_status, 'Moving_Pick')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                AGVs(id).status = 'Idle';
                AGVs(id).yield_resume_status = '';
                return;
            end
            target_id = task_list(row_idx, 2);
            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
            if plan_path(id, pick_anchor, pick_size, current_t)
                AGVs(id).status = 'Moving_Pick';
                AGVs(id).yield_resume_status = '';
            else
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
        elseif strcmp(resume_status, 'Moving_Drop')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                AGVs(id).status = 'Idle';
                AGVs(id).yield_resume_status = '';
                return;
            end
            target_id = task_list(row_idx, 2);
            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
            if plan_path(id, drop_anchor, drop_size, current_t)
                AGVs(id).status = 'Moving_Drop';
                AGVs(id).yield_resume_status = '';
            else
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
        elseif strcmp(resume_status, 'Go_Home')
            if AGVs(id).type == 2
                agv_area_sz = [3, 3];
            else
                agv_area_sz = [1, 1];
            end
            if plan_path(id, AGVs(id).home_pos, agv_area_sz, current_t)
                AGVs(id).status = 'Go_Home';
                AGVs(id).yield_resume_status = '';
            else
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
        elseif strcmp(resume_status, 'Going_Charge')
            AGVs(id).yield_resume_status = '';
            plan_to_charge(id, current_t);
            if ~strcmp(AGVs(id).status, 'Going_Charge')
                AGVs(id).yield_resume_status = 'Going_Charge';
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
        else
            AGVs(id).status = resume_status;
            AGVs(id).yield_resume_status = '';
        end
    end
    
    function finish_waiting(id, tasks_info)
        st = AGVs(id).status;
        
        if strcmp(st, 'Loading')
            tid = AGVs(id).active_task_id;                 
            row_idx = get_task_row(tid);
            if row_idx == 0
                AGVs(id).status = 'Idle';
                AGVs(id).active_task_id = 0;
                return;
            end
            task_weight = tasks_info(row_idx, 3);
            
            % 1. 【核心：仅记录起点】记录开始时间和里程，不进行结算
            if task_times(tid, 1) == 0, task_times(tid, 1) = t; end
            task_start_dist(tid) = AGVs(id).total_dist;
            task_executor(tid) = id;
            
            % 2. 装载货物
            AGVs(id).payload_weight = AGVs(id).payload_weight + task_weight; 
            AGVs(id).load = 1;                     
            
            fprintf('[AGV-%02d] 成功装载订单 #%d | 重量: %d | 车上总重: %d\n', ...
                id, tid, task_weight, AGVs(id).payload_weight);
                
            % 3. 队列流转逻辑
            if ~isempty(AGVs(id).pick_queue)
                next_tid = AGVs(id).pick_queue(1);
                AGVs(id).pick_queue(1) = [];
                AGVs(id).active_task_id = next_tid;
                next_row = get_task_row(next_tid);
                if next_row == 0
                    AGVs(id).status = 'Idle';
                    AGVs(id).active_task_id = 0;
                    AGVs(id).pick_queue = [];
                    AGVs(id).drop_queue = [];
                    return;
                end
                next_target_id = tasks_info(next_row, 2);
                [pick_anchor, ~, pick_size, ~] = get_task_coordinates(next_target_id); 
                if plan_path(id, pick_anchor, pick_size, t) 
                    AGVs(id).status = 'Moving_Pick';      
                else 
                    AGVs(id).wait_timer = 2;               
                    AGVs(id).pick_queue = [next_tid, AGVs(id).pick_queue]; 
                end
            else
                % 取完货了，出发去送货
                first_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = []; 
                AGVs(id).active_task_id = first_drop_tid;
                drop_row = get_task_row(first_drop_tid);
                if drop_row == 0
                    AGVs(id).status = 'Idle';
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    return;
                end
                drop_target_id = tasks_info(drop_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(drop_target_id); 
                if plan_path(id, drop_anchor, drop_size, t) 
                    AGVs(id).status = 'Moving_Drop';      
                else 
                    AGVs(id).wait_timer = 2;               
                    AGVs(id).drop_queue = [first_drop_tid, AGVs(id).drop_queue]; 
                end
            end
            
        elseif strcmp(st, 'Unloading')
            tid = AGVs(id).active_task_id;                 
            row_idx = get_task_row(tid);
            if row_idx == 0
                AGVs(id).status = 'Idle';
                AGVs(id).active_task_id = 0;
                return;
            end
            task_weight = tasks_info(row_idx, 3);
            
            % ★【核心：结算终点指标】只有在卸货完成时才记录结束时间和总路程
            task_times(tid, 2) = t; 
            time_spent_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
            task_dist_record(tid) = AGVs(id).total_dist - task_start_dist(tid);
            
            fprintf('✅ [AGV-%02d] 任务完成！订单 #%d | 耗时: %.1f秒 | 运输里程: %d格\n', ...
                    id, tid, time_spent_sec, task_dist_record(tid));
            
            % 扣除载重并从该车任务链中移除
            AGVs(id).payload_weight = max(0, AGVs(id).payload_weight - task_weight); 
            AGVs(id).tasks(AGVs(id).tasks == tid) = [];                
                
            if ~isempty(AGVs(id).drop_queue)
                % 继续送下一件
                next_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = []; 
                AGVs(id).active_task_id = next_drop_tid;
                next_row = get_task_row(next_drop_tid);
                if next_row == 0
                    AGVs(id).status = 'Idle';
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    return;
                end
                next_target_id = tasks_info(next_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(next_target_id); 
                if plan_path(id, drop_anchor, drop_size,t)
                    AGVs(id).status = 'Moving_Drop';      
                else 
                    AGVs(id).wait_timer = 2;               
                    AGVs(id).drop_queue = [next_drop_tid, AGVs(id).drop_queue]; 
                end
            else
                % 全部送完，回归空闲
                fprintf('   -> AGV-%02d 批次配送全部收工。\n', id);
                AGVs(id).status = 'Idle';                   
                AGVs(id).load = 0;                           
                AGVs(id).active_task_id = 0;
            end
        end
    end  

    function export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories)
        disp('>> [数据模块] 正在生成仿真报告...');
        save_dir = fileparts(mfilename('fullpath')); % 获取当前脚本所在绝对路径
        
        % 1. 导出任务指标 (task_metrics.csv)
        try
            csv_file_path = fullfile(save_dir, 'task_metrics.csv');
            fid = fopen(csv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid, 'task_id,agv_id,time_sec,distance\n');
            for i = 1:size(task_list, 1)
                tid = task_list(i, 1);
                if task_times(tid, 2) > 0 % 只记录已完成的任务
                    t_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
                    dist = task_dist_record(tid);
                    agv_str = sprintf('AGV-%02d', task_executor(tid));
                    fprintf(fid, '%d,%s,%.1f,%d\n', tid, agv_str, t_sec, dist);
                end
            end
            fclose(fid);
            disp('  -> 已生成 task_metrics.csv');
        catch ME
            fprintf('  -> [错误] task_metrics.csv 生成失败: %s\n', ME.message);
        end
        
        % 2. 导出轨迹数据 (task_paths.json)
        try
            path_struct = struct();
            for i = 1:size(task_list, 1)
                tid = task_list(i, 1);
                if ~isempty(task_trajectories{tid})
                    fname = sprintf('task_%d', tid);
                    path_struct.(fname) = task_trajectories{tid};
                end
            end
            
            json_str = jsonencode(path_struct);
            json_file_path = fullfile(save_dir, 'task_paths.json');
            fid_json = fopen(json_file_path, 'w');
            if fid_json ~= -1
                fprintf(fid_json, '%s', json_str);
                fclose(fid_json);
                disp('  -> 已生成 task_paths.json');
            else
                disp('  -> [错误] 无法创建 task_paths.json 文件');
            end
        catch ME
            fprintf('  -> [错误] task_paths.json 生成失败: %s\n', ME.message);
        end
        
        % 3. 导出设备状态 (agv_metrics.csv)
        try
            agv_file_path = fullfile(save_dir, 'agv_metrics.csv');
            fid_agv = fopen(agv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid_agv, 'agv_id,agv_type,battery,total_distance,total_turns\n');
            for k = 1:num_agvs
                fprintf(fid_agv, '%d,%d,%.2f,%d,%d\n', ...
                    k, AGVs(k).type, AGVs(k).battery, AGVs(k).total_dist, AGVs(k).total_turns);
            end
            fclose(fid_agv);
            disp('  -> 已生成 agv_metrics.csv');
        catch ME
            fprintf('  -> [错误] agv_metrics.csv 生成失败: %s\n', ME.message);
        end
    end
    
    function run_sliding_window_radar(current_t, tasks_info)
        window_size = 6; % 预测未来 6 个仿真步 (即 1 秒)
        
        % 1. 提取所有车辆在未来 6 步的预测轨迹 (Nx3 矩阵: [r, c, future_t])
        predicted_trajs = cell(1, num_agvs);
        for k = 1:num_agvs
            predicted_trajs{k} = get_future_trajectory(k, current_t, window_size);
        end
        
        % 2. 两两遍历，寻找时空交叉点
        for i = 1:num_agvs
            for j = i+1:num_agvs
                traj_A = predicted_trajs{i};
                traj_B = predicted_trajs{j};
                
                % 逐帧扫描未来时间窗
                for dt = 1:window_size
                    future_t = current_t + dt;
                    pos_A = traj_A(dt, 1:2);
                    pos_B = traj_B(dt, 1:2);
                    
                    is_conflict = false;
                    % 判定 1: 节点冲突/追尾 (同一时刻站在同一个格子上)
                    if isequal(pos_A, pos_B)
                        is_conflict = true;
                    end
                    
                    % 判定 2: 换位冲突 (边缘穿插)
                    if dt > 1
                        prev_A = traj_A(dt-1, 1:2);
                        prev_B = traj_B(dt-1, 1:2);
                        if isequal(pos_A, prev_B) && isequal(pos_B, prev_A)
                            is_conflict = true;
                        end
                    end
                    
                    % 如果发现冲突，立即执行时空博弈与轨迹拼接
                    if is_conflict
                        resolve_future_conflict(i, j, future_t, dt, tasks_info);
                        % 解决完这一对后，立刻跳出当前时间窗的扫描，避免重复处理
                        break; 
                    end
                end
            end
        end
    end
    
    function traj = get_future_trajectory(id, current_t, w_size)
        traj = zeros(w_size, 3);
        temp_pos = AGVs(id).pos;
        temp_path_idx = AGVs(id).path_idx;
        temp_timer = AGVs(id).move_timer;
        
        moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home'};
        is_moving = ismember(AGVs(id).status, moving_states) && ~isempty(AGVs(id).path);
        
        for dt = 1:w_size
            f_t = current_t + dt;
            if ~is_moving || temp_path_idx > size(AGVs(id).path, 1)
                % 如果是静止状态，未来坐标永远等于当前坐标
                traj(dt, :) = [temp_pos(1), temp_pos(2), f_t];
            else
                if temp_timer > 0
                    % 还在路上跑，尚未跨入下一个格子
                    temp_timer = temp_timer - 1;
                    traj(dt, :) = [temp_pos(1), temp_pos(2), f_t];
                else
                    % 刚好跨入下一个格子，更新临时坐标
                    next_node = AGVs(id).path(temp_path_idx, 1:2);
                    temp_pos = next_node;
                    traj(dt, :) = [temp_pos(1), temp_pos(2), f_t];
                    
                    temp_path_idx = temp_path_idx + 1;
                    temp_timer = AGVs(id).step_dur - 1;
                end
            end
        end
    end

    function resolve_future_conflict(id_A, id_B, conflict_t, dt, tasks_info)
        
        % 推算出当前的真实时间
        current_t = conflict_t - dt;
        
        % 1. 穿越至未来，计算双方在冲突时刻的真实预期优先级
        p_A = calculate_predictive_ahp_priority(AGVs(id_A), tasks_info, current_t, conflict_t, agv_params(id_A));
        p_B = calculate_predictive_ahp_priority(AGVs(id_B), tasks_info, current_t, conflict_t, agv_params(id_B));
        
        % 裁定谁是弱者 (loser 需要改变未来)
        if p_A < p_B || (p_A == p_B && id_A > id_B)
            loser = id_A; winner = id_B;
        else
            loser = id_B; winner = id_A;
        end
        
        % 2. 如果弱者本身处于静止状态，无法主动拼接轨迹，交由底层兜底拦截
        if isempty(AGVs(loser).path) || AGVs(loser).path_idx > size(AGVs(loser).path, 1)
            return; 
        end
        
        % 3. 寻找“安全锚点”(Safe Anchor)
        safe_t = conflict_t - 1;
        safe_path_row = find(AGVs(loser).path(:, 3) == safe_t, 1, 'last');
        if isempty(safe_path_row)
            safe_path_row = AGVs(loser).path_idx; 
        end
        safe_anchor = AGVs(loser).path(safe_path_row, 1:2);
        
        original_path_loser = AGVs(loser).path; 
        original_idx_loser  = AGVs(loser).path_idx; 
        original_pos_loser  = AGVs(loser).pos;
        
        original_pos_winner = AGVs(winner).pos;
        
        % 截取安全前缀
        safe_prefix_path = original_path_loser(1:safe_path_row, :);
        
        % 预测高优车辆在冲突时刻的坐标 (这就是导致碰撞的罪魁祸首)
        winner_future_traj = get_future_trajectory(winner, conflict_t - 1, 1);
        future_obstacle_pos = winner_future_traj(1, 1:2);
        
        AGVs(loser).pos = safe_anchor;
        AGVs(winner).pos = future_obstacle_pos; 

        success = plan_path(loser, AGVs(loser).target_node, [1, 1], safe_t);
        
        AGVs(loser).pos = original_pos_loser;
        AGVs(winner).pos = original_pos_winner;
        
        % 6. 命运裁决：无缝拼接 (Trajectory Stitching)
        if success
            % A* 成功避开了未来的 winner，找到了新路
            new_future_path = AGVs(loser).path(2:end, :); % 剔除 A* 起点本身
            AGVs(loser).path = [safe_prefix_path; new_future_path];
            disp(['[预言家] 拼接成功，AGV-', num2str(loser), ' 将在 T=', num2str(safe_t), ' 提前变道避让 AGV-', num2str(winner)]);
        else
            % A* 发现单行道死胡同绕不开，执行【虚拟等待】
            wait_nodes = zeros(3, 3);
            for w_step = 1:3
                wait_nodes(w_step, :) = [safe_anchor(1), safe_anchor(2), safe_t + w_step * AGVs(loser).step_dur];
            end
            
            % 提取原路径的剩余部分，整体向后推迟 3 个步长
            remaining_path = original_path_loser(safe_path_row+1:end, :);
            if ~isempty(remaining_path)
                time_delay = 3 * AGVs(loser).step_dur;
                remaining_path(:, 3) = remaining_path(:, 3) + time_delay;
                AGVs(loser).path = [safe_prefix_path; wait_nodes; remaining_path];
                disp(['[预言家] 绕路失败，AGV-', num2str(loser), ' 将在安全点原地等待。']);
            end
        end
        
        AGVs(loser).path_idx = original_idx_loser; 
    end

end