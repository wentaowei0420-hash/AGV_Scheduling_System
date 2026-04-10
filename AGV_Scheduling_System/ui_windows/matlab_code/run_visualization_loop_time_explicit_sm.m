function run_visualization_loop_time_explicit_sm(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    global mapW mapH;
    global costmap_type1 costmap_type2;

    generate_beautiful_factory_map();
    init_global_costmaps();

    f_map = gcf;
    ax = findobj(f_map, 'Type', 'Axes');
    hold(ax, 'on');
    set(f_map, 'Name', 'Real-time Scheduling Simulation (Explicit State Machine)', ...
        'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
        'Position', [50, 200, 1000, 700]);
    [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs);

    [AGVs, props, ~] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax);
    state_defs = build_state_definitions();

    disp('>> [System] Explicit state-machine simulation started.');

    for k = 1:num_agvs
        AGVs(k).total_turns = 0;
        AGVs(k).last_dir = [0, 0];
        AGVs(k).pick_queue = [];
        AGVs(k).drop_queue = [];
        AGVs(k).active_task_id = 0;
        AGVs(k).interrupted_status = '';
        AGVs(k).yield_resume_status = '';
    end

    sim_running = true;
    MAX_STEPS = 500000;
    t = 0;
    frames_per_step = 2;
    reservation_horizon_steps = 8;
    max_departure_wait_steps = 4;

    max_task_id = max(task_list(:, 1));
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
    task_trajectories = cell(max_task_id, 1);
    reported_conflict_keys = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    for k = 1:num_agvs
        AGVs(k).total_dist = 0;
    end

    while sim_running && t < MAX_STEPS
        t = t + 1;
        all_finished = true;
        reported_conflict_keys = containers.Map('KeyType', 'char', 'ValueType', 'logical');

        for k = 1:num_agvs
            if AGVs(k).move_timer > 0
                AGVs(k).move_timer = AGVs(k).move_timer - 1;
                all_finished = false;
                continue;
            end

            if ~isfield(state_defs, AGVs(k).status)
                error('Unknown AGV state: %s', AGVs(k).status);
            end

            state_info = state_defs.(AGVs(k).status);
            [still_active, stop_sim] = state_info.handler(k, t);
            all_finished = all_finished && ~still_active;
            if stop_sim
                sim_running = false;
                break;
            end
        end

        if all_finished
            break;
        end

        for f = 1:frames_per_step
            curr_bat_list = zeros(1, num_agvs);
            for k = 1:num_agvs
                target_r = AGVs(k).pos(1);
                target_c = AGVs(k).pos(2);
                curr_r = AGVs(k).vis_pos(1);
                curr_c = AGVs(k).vis_pos(2);

                AGVs(k).vis_pos(1) = curr_r + (target_r - curr_r) * 0.3;
                AGVs(k).vis_pos(2) = curr_c + (target_c - curr_c) * 0.3;

                update_agv_plot(AGVs(k));
                curr_bat_list(k) = AGVs(k).battery;

                if ~isempty(AGVs(k).path) && AGVs(k).path_idx <= size(AGVs(k).path, 1)
                    rem_path = AGVs(k).path(AGVs(k).path_idx:end, :);
                    set(AGVs(k).path_line, 'XData', rem_path(:, 2) - 0.5, 'YData', rem_path(:, 1) - 0.5);
                else
                    set(AGVs(k).path_line, 'XData', NaN, 'YData', NaN);
                end
            end
            update_battery_monitor(f_batt, b_handle, t_handles, curr_bat_list);
            drawnow limitrate;
            pause(0.02);
        end
    end

    export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories);
    disp('>> Simulation finished.');

    function defs = build_state_definitions()
        defs = struct();
        defs.Idle = struct('category', 'idle', 'handler', @handle_idle_state);
        defs.Loading = struct('category', 'waiting', 'handler', @handle_waiting_state);
        defs.Unloading = struct('category', 'waiting', 'handler', @handle_waiting_state);
        defs.Charging = struct('category', 'waiting', 'handler', @handle_waiting_state);

        defs.Moving_Pick = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Moving_Drop = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Go_Home = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Going_Home = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Going_Charge = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Yielding = struct('category', 'moving', 'handler', @handle_moving_state);
    end

    function transition_to(id, new_state, wait_timer, move_timer)
        AGVs(id).status = new_state;
        if nargin >= 3 && ~isempty(wait_timer)
            AGVs(id).wait_timer = wait_timer;
        end
        if nargin >= 4 && ~isempty(move_timer)
            AGVs(id).move_timer = move_timer;
        end
    end

    function [still_active, stop_sim] = handle_idle_state(id, current_t)
        stop_sim = false;
        still_active = false;

        if AGVs(id).battery < 20
            plan_to_charge(id, current_t);
            still_active = true;
            return;
        end

        if AGVs(id).active_task_id > 0
            try_resume_interrupted_task(id, current_t);
            still_active = true;
            return;
        end

        if ~isempty(AGVs(id).tasks)
            try_dispatch_new_batch(id, current_t);
            still_active = true;
            return;
        end

        if try_idle_post_actions(id, current_t)
            still_active = true;
        end
    end

    function [still_active, stop_sim] = handle_moving_state(id, current_t)
        stop_sim = false;
        still_active = true;

        if AGVs(id).battery < 20 && ~strcmp(AGVs(id).status, 'Going_Charge') && ~strcmp(AGVs(id).status, 'Charging')
            AGVs(id).interrupted_status = AGVs(id).status;
            plan_to_charge(id, current_t);
            return;
        end

        move_status = execute_move(id, current_t);
        if move_status == 1
            handle_arrival(id, current_t);
        elseif move_status < 0
            resolve_conflict(id, -move_status, task_list, current_t);
        end
    end

    function [still_active, stop_sim] = handle_waiting_state(id, current_t)
        stop_sim = false;
        still_active = true;

        AGVs(id).wait_timer = AGVs(id).wait_timer - 1;

        if strcmp(AGVs(id).status, 'Charging')
            AGVs(id).battery = min(100, AGVs(id).battery + 2.0);
            if AGVs(id).battery >= 100 && AGVs(id).wait_timer <= 0
                transition_to(id, 'Idle', 0, []);
            end
            return;
        end

        if AGVs(id).wait_timer <= 0
            finish_waiting(id, task_list, current_t);
        end
    end

    function try_resume_interrupted_task(id, current_t)
        tid = AGVs(id).active_task_id;
        row_idx = get_task_row(tid);
        if row_idx == 0
            AGVs(id).active_task_id = 0;
            return;
        end

        target_id = task_list(row_idx, 2);
        if strcmp(AGVs(id).interrupted_status, 'Moving_Drop')
            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
            if plan_path(id, drop_anchor, drop_size, current_t)
                transition_to(id, 'Moving_Drop', 0, []);
                AGVs(id).interrupted_status = '';
            end
        elseif strcmp(AGVs(id).interrupted_status, 'Moving_Pick')
            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
            if plan_path(id, pick_anchor, pick_size, current_t)
                transition_to(id, 'Moving_Pick', 0, []);
                AGVs(id).interrupted_status = '';
            end
        else
            AGVs(id).active_task_id = 0;
        end
    end

    function try_dispatch_new_batch(id, current_t)
        max_load_capacity = 80;
        batch_tasks = [];
        current_batch_weight = 0;

        for i = 1:length(AGVs(id).tasks)
            tid = AGVs(id).tasks(i);
            row_idx = get_task_row(tid);
            if row_idx == 0
                continue;
            end
            w = task_list(row_idx, 3);
            if AGVs(id).type == 2 && i > 1
                break;
            end
            if i == 1 || (current_batch_weight + w <= max_load_capacity)
                batch_tasks = [batch_tasks, tid]; %#ok<AGROW>
                current_batch_weight = current_batch_weight + w;
            else
                break;
            end
        end

        if isempty(batch_tasks)
            return;
        end

        AGVs(id).pick_queue = batch_tasks;
        AGVs(id).drop_queue = batch_tasks;

        first_tid = AGVs(id).pick_queue(1);
        AGVs(id).pick_queue(1) = [];
        AGVs(id).active_task_id = first_tid;

        row_idx = get_task_row(first_tid);
        if row_idx == 0
            AGVs(id).pick_queue = [];
            AGVs(id).drop_queue = [];
            AGVs(id).active_task_id = 0;
            return;
        end

        target_id = task_list(row_idx, 2);
        [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
        if plan_path(id, pick_anchor, pick_size, current_t)
            transition_to(id, 'Moving_Pick', 0, []);
        else
            AGVs(id).pick_queue = [];
            AGVs(id).drop_queue = [];
            AGVs(id).active_task_id = 0;
        end
    end

    function active = try_idle_post_actions(id, current_t)
        active = false;
        if AGVs(id).type == 2
            agv_area_sz = [3, 3];
        else
            agv_area_sz = [1, 1];
        end

        home_pos = AGVs(id).home_pos;
        if AGVs(id).battery < 95
            if is_at_charge_station(id, agv_area_sz)
                transition_to(id, 'Charging', 5, []);
            else
                plan_to_charge(id, current_t);
            end
            active = true;
        elseif ~check_in_area(AGVs(id).pos, home_pos, agv_area_sz)
            if plan_path(id, home_pos, agv_area_sz, current_t)
                transition_to(id, 'Go_Home', 0, []);
            end
            active = true;
        end
    end

    function flag = is_at_charge_station(id, agv_area_sz)
        flag = false;
        if isfield(props(AGVs(id).type), 'charge_stations') && ~isempty(props(AGVs(id).type).charge_stations)
            candidate_stations = props(AGVs(id).type).charge_stations;
        else
            candidate_stations = props(AGVs(id).type).charge;
        end
        for s = 1:size(candidate_stations, 1)
            if check_in_area(AGVs(id).pos, candidate_stations(s, :), agv_area_sz)
                flag = true;
                return;
            end
        end
    end
    function resolve_conflict(id_self, id_blocker, tasks_info, current_t)
        pos_self = AGVs(id_self).pos;
        target_self = AGVs(id_self).path(AGVs(id_self).path_idx, 1:2);
        dir_self = target_self - pos_self;

        pos_blocker = AGVs(id_blocker).pos;
        moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home', 'Yielding'};
        is_blocker_moving = ismember(AGVs(id_blocker).status, moving_states);
        has_path = ~isempty(AGVs(id_blocker).path) && AGVs(id_blocker).path_idx <= size(AGVs(id_blocker).path, 1);

        if is_blocker_moving && has_path
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

        dot_product = dir_self(1) * dir_blocker(1) + dir_self(2) * dir_blocker(2);
        if AGVs(id_self).move_timer > 0
            v_self = 0.001;
        else
            v_self = 1.0 / AGVs(id_self).step_dur;
        end

        c_type = 0;
        conflict_name = 'Unknown';
        is_swapping = isequal(target_self, pos_blocker) && isequal(true_target_blocker, pos_self);
        is_same_target = isequal(target_self, target_blocker);

        if is_swapping
            c_type = 1; conflict_name = 'Head-on swap';
        elseif isequal(target_self, pos_blocker)
            if v_blocker == 0
                c_type = 3; conflict_name = 'Occupied node';
            elseif dot_product > 0 && v_self > v_blocker
                c_type = 4; conflict_name = 'Rear-end';
            else
                c_type = 1; conflict_name = 'Head-on swap';
            end
        elseif is_same_target
            if dot_product < 0
                c_type = 1; conflict_name = 'Head-on meet';
            else
                c_type = 2; conflict_name = 'Node contention';
            end
        end

        conflict_pair = sort([id_self, id_blocker]);
        conflict_key = sprintf('%d_%d_%d', current_t, conflict_pair(1), conflict_pair(2));
        if isKey(reported_conflict_keys, conflict_key)
            return;
        end
        reported_conflict_keys(conflict_key) = true;

        disp(['[Conflict] T=', num2str(current_t), ' ', conflict_name, ' AGV-', num2str(id_self), ' vs AGV-', num2str(id_blocker)]);
        send_conflict_webhook(current_t, id_self, pos_self, id_blocker, pos_blocker, conflict_name);

        P_self = calculate_ahp_priority(AGVs(id_self), tasks_info, current_t);
        P_blocker = calculate_ahp_priority(AGVs(id_blocker), tasks_info, current_t);

        should_self_yield = (P_self < P_blocker) || (P_self == P_blocker && id_self > id_blocker);
        if should_self_yield
            loser_id = id_self;
        else
            loser_id = id_blocker;
        end

        if c_type == 1
            success = plan_yield_path(loser_id, id_self + id_blocker - loser_id, current_t);
            if ~success && ~isempty(AGVs(loser_id).target_node)
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t);
            end
            if ~success
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
            end
        elseif c_type == 2
            AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
        else
            if ~isempty(AGVs(loser_id).target_node)
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t);
                if ~success
                    AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
                end
            else
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
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
            charge_area_sz = [1, 1];
        end

        best_cost = inf;
        best_station = [];
        best_station_target = [];
        best_station_path = [];
        best_station_wait_steps = 0;

        for s = 1:size(candidate_stations, 1)
            station_pos = candidate_stations(s, :);
            is_occupied = false;
            for other = 1:num_agvs
                if other == id
                    continue;
                end
                if (isequal(AGVs(other).pos, station_pos) || isequal(AGVs(other).target_node, station_pos)) && ...
                        ismember(AGVs(other).status, {'Charging', 'Going_Charge'})
                    is_occupied = true;
                    break;
                end
            end
            if ~is_occupied
                [candidate_path, candidate_target, candidate_cost, candidate_wait_steps] = find_best_target_path(id, station_pos, charge_area_sz, 'charge', current_t);
                if ~isempty(candidate_path) && candidate_cost < best_cost
                    best_cost = candidate_cost;
                    best_station = station_pos;
                    best_station_target = candidate_target;
                    best_station_path = candidate_path;
                    best_station_wait_steps = candidate_wait_steps;
                end
            end
        end

        if ~isempty(best_station)
            assign_planned_path(id, best_station_path, best_station_target, current_t, best_station_wait_steps);
            transition_to(id, 'Going_Charge', 0, []);
        else
            AGVs(id).move_timer = 5;
        end
    end

    function [best_path, best_target, best_cost, best_wait_steps] = find_best_target_path(id, target_anchor, area_size, planning_mode, current_t)
        if nargin < 3 || isempty(area_size)
            area_size = [2, 2];
        end
        if nargin < 4 || isempty(planning_mode)
            planning_mode = 'task';
        end
        if nargin < 5 || isempty(current_t)
            current_t = t;
        end

        virtual_target_id = 0;
        if strcmp(planning_mode, 'charge')
            if AGVs(id).type == 1
                virtual_target_id = 17;
            else
                virtual_target_id = 18;
            end
        else
            if AGVs(id).type == 1
                virtual_target_id = 1;
            else
                virtual_target_id = 13;
            end
        end

        tempMap = create_binary_grid_map(mapW, mapH, virtual_target_id);
        area_h = area_size(1);
        area_w = area_size(2);

        for dr = 0:(area_h - 1)
            for dc = 0:(area_w - 1)
                r = target_anchor(1) + dr;
                c = target_anchor(2) + dc;
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    tempMap(r, c) = 0;
                end
            end
        end

        valid_targets = [];
        for dr = 0:(area_h - 1)
            for dc = 0:(area_w - 1)
                r = target_anchor(1) + dr;
                c = target_anchor(2) + dc;
                if r < 1 || r > mapH || c < 1 || c > mapW
                    continue;
                end
                occupied = false;
                for other = 1:num_agvs
                    if other == id
                        continue;
                    end
                    is_pos_occupied = AGVs(other).pos(1) == r && AGVs(other).pos(2) == c;
                    is_target_occupied = ~isempty(AGVs(other).target_node) && AGVs(other).target_node(1) == r && AGVs(other).target_node(2) == c;
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

        best_path = [];
        best_target = [];
        best_cost = inf;
        best_wait_steps = 0;
        best_conflict_count = inf;
        if isempty(valid_targets)
            return;
        end
        reservations = build_sliding_window_reservations(current_t, id);

        current_weight = 0;
        if isfield(AGVs(id), 'payload_weight') && AGVs(id).load == 1
            current_weight = AGVs(id).payload_weight;
        end

        if AGVs(id).type == 2
            current_costmap = costmap_type2;
        else
            current_costmap = costmap_type1;
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
            [candidate_path, candidate_cost] = astar_planner_turn3(evalMap, curr_pos, candidate_target, current_weight, current_costmap, AGVs(id).type);
            if isempty(candidate_path)
                continue;
            end

            [is_feasible, conflict_count, wait_steps] = evaluate_candidate_path_window(id, candidate_path, current_t, reservations);
            if is_feasible
                if (conflict_count < best_conflict_count) || ...
                   (conflict_count == best_conflict_count && candidate_cost < best_cost - 1e-9) || ...
                   (conflict_count == best_conflict_count && abs(candidate_cost - best_cost) <= 1e-9 && wait_steps < best_wait_steps)
                    best_conflict_count = conflict_count;
                    best_cost = candidate_cost;
                    best_target = candidate_target;
                    best_path = candidate_path;
                    best_wait_steps = wait_steps;
                end
            elseif isempty(best_path) && conflict_count < best_conflict_count
                best_conflict_count = conflict_count;
                best_cost = candidate_cost;
                best_target = candidate_target;
                best_path = candidate_path;
                best_wait_steps = wait_steps;
            end
        end
    end

    function assign_planned_path(id, path, actual_target, current_t, initial_wait_steps)
        if nargin < 5 || isempty(initial_wait_steps)
            initial_wait_steps = 0;
        end
        path_length = size(path, 1);
        time_stamps = zeros(path_length, 1);
        step_time = AGVs(id).step_dur;
        for p_idx = 1:path_length
            time_stamps(p_idx) = current_t + initial_wait_steps + (p_idx - 1) * step_time;
        end
        AGVs(id).path = [path, time_stamps];
        AGVs(id).path_idx = 2;
        AGVs(id).target_node = actual_target;
        if initial_wait_steps > 0
            AGVs(id).move_timer = max(AGVs(id).move_timer, initial_wait_steps);
        end
    end

    function row_idx = get_task_row(task_id)
        row_idx = 0;
        if isempty(task_id) || task_id < 1 || task_id > numel(task_row_map)
            return;
        end
        row_idx = task_row_map(task_id);
    end

    function success = plan_path(id, target_anchor, area_size, current_t, planning_mode)
        if nargin < 3 || isempty(area_size)
            area_size = [2, 2];
        end
        if nargin < 5 || isempty(planning_mode)
            planning_mode = 'task';
        end
        [path, actual_target, ~, wait_steps] = find_best_target_path(id, target_anchor, area_size, planning_mode, current_t);
        if ~isempty(path)
            assign_planned_path(id, path, actual_target, current_t, wait_steps);
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
                transition_to(id, 'Yielding', 0, []);
                success = true;
                return;
            end
        end
    end
    function status = execute_move(id, current_t)
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            status = 1;
            return;
        end

        blocker_id = detect_future_window_conflict(id, current_t);
        if blocker_id > 0
            status = -blocker_id;
            return;
        end

        curr_pos = AGVs(id).pos;
        next_node_3d = AGVs(id).path(AGVs(id).path_idx, :);
        nr = next_node_3d(1);
        nc = next_node_3d(2);
        target_t = next_node_3d(3);

        for other = 1:num_agvs
            if other == id
                continue;
            end
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
                status = -other;
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2) && ...
                    other_next_r == curr_pos(1) && other_next_c == curr_pos(2)
                status = -other;
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2) && target_t <= other_next_t
                status = -other;
                return;
            end
        end

        AGVs(id).pos = [nr, nc];
        curr_dir = [nr - curr_pos(1), nc - curr_pos(2)];
        if ~isequal(AGVs(id).last_dir, [0, 0]) && ~isequal(AGVs(id).last_dir, curr_dir)
            AGVs(id).total_turns = AGVs(id).total_turns + 1;
        end
        AGVs(id).last_dir = curr_dir;

        tid = AGVs(id).active_task_id;
        if tid > 0
            task_trajectories{tid} = [task_trajectories{tid}; AGVs(id).pos];
        end
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

        e_b = agv_params(id).e_base;
        e_l = agv_params(id).e_load_factor;
        cost = e_b + e_l * AGVs(id).payload_weight / 100.0;
        AGVs(id).battery = max(0, AGVs(id).battery - cost);

        if AGVs(id).path_idx > size(AGVs(id).path, 1)
            AGVs(id).last_dir = [0, 0];
            status = 1;
        else
            status = 0;
        end
    end

    function reservations = build_sliding_window_reservations(current_t, exclude_id)
        reservations.node = containers.Map('KeyType', 'char', 'ValueType', 'double');
        reservations.edge = containers.Map('KeyType', 'char', 'ValueType', 'double');
        horizon_t = get_window_horizon_time(current_t);

        for other = 1:num_agvs
            if nargin >= 2 && other == exclude_id
                continue;
            end

            curr_pos = AGVs(other).pos;
            hold_until = min(horizon_t, current_t + max(AGVs(other).move_timer, 0));
            for tau = current_t:hold_until
                reserve_node(reservations.node, curr_pos, tau, other);
            end

            if isempty(AGVs(other).path) || AGVs(other).path_idx > size(AGVs(other).path, 1)
                continue;
            end

            prev_pos = curr_pos;
            prev_t = current_t;
            for idx = AGVs(other).path_idx:size(AGVs(other).path, 1)
                node_pos = AGVs(other).path(idx, 1:2);
                node_t = AGVs(other).path(idx, 3);
                if node_t > horizon_t
                    break;
                end
                reserve_node(reservations.node, node_pos, node_t, other);
                reserve_edge(reservations.edge, prev_pos, node_pos, node_t, other);
                prev_pos = node_pos;
                prev_t = node_t; %#ok<NASGU>
            end
        end
    end

    function [is_feasible, conflict_count, best_wait_steps] = evaluate_candidate_path_window(id, candidate_path, current_t, reservations)
        step_time = AGVs(id).step_dur;
        horizon_t = get_window_horizon_time(current_t);
        best_wait_steps = 0;
        best_conflict = inf;
        is_feasible = false;

        for wait_steps = 0:max_departure_wait_steps
            conflict_count = 0;
            timed_path = [candidate_path, zeros(size(candidate_path, 1), 1)];
            for p_idx = 1:size(candidate_path, 1)
                timed_path(p_idx, 3) = current_t + wait_steps + (p_idx - 1) * step_time;
            end

            hold_until = min(horizon_t, current_t + wait_steps);
            for tau = current_t:hold_until
                if is_reserved_node(reservations.node, candidate_path(1, :), tau, id)
                    conflict_count = conflict_count + 1;
                end
            end

            for p_idx = 2:size(timed_path, 1)
                node_pos = timed_path(p_idx, 1:2);
                node_t = timed_path(p_idx, 3);
                if node_t > horizon_t
                    break;
                end
                if is_reserved_node(reservations.node, node_pos, node_t, id)
                    conflict_count = conflict_count + 1;
                end
                prev_pos = timed_path(p_idx - 1, 1:2);
                if is_reserved_edge(reservations.edge, prev_pos, node_pos, node_t, id)
                    conflict_count = conflict_count + 1;
                end
            end

            if conflict_count == 0
                is_feasible = true;
                best_wait_steps = wait_steps;
                return;
            end

            if conflict_count < best_conflict
                best_conflict = conflict_count;
                best_wait_steps = wait_steps;
            end
        end

        conflict_count = best_conflict;
    end

    function blocker_id = detect_future_window_conflict(id, current_t)
        blocker_id = 0;
        reservations = build_sliding_window_reservations(current_t, id);
        horizon_t = get_window_horizon_time(current_t);

        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            return;
        end

        curr_pos = AGVs(id).pos;
        hold_until = min(horizon_t, current_t + max(AGVs(id).move_timer, 0));
        for tau = current_t:hold_until
            owner = lookup_reserved_node(reservations.node, curr_pos, tau);
            if owner > 0 && owner ~= id
                blocker_id = owner;
                return;
            end
        end

        prev_pos = curr_pos;
        for idx = AGVs(id).path_idx:size(AGVs(id).path, 1)
            node_pos = AGVs(id).path(idx, 1:2);
            node_t = AGVs(id).path(idx, 3);
            if node_t > horizon_t
                break;
            end
            owner = lookup_reserved_node(reservations.node, node_pos, node_t);
            if owner > 0 && owner ~= id
                blocker_id = owner;
                return;
            end
            owner = lookup_reserved_edge(reservations.edge, prev_pos, node_pos, node_t);
            if owner > 0 && owner ~= id
                blocker_id = owner;
                return;
            end
            prev_pos = node_pos;
        end
    end

    function horizon_t = get_window_horizon_time(current_t)
        max_step = 1;
        for agv_idx = 1:num_agvs
            max_step = max(max_step, AGVs(agv_idx).step_dur);
        end
        horizon_t = current_t + reservation_horizon_steps * max_step;
    end

    function reserve_node(node_map, pos, t, owner_id)
        key = sprintf('%d_%d_%d', round(pos(1)), round(pos(2)), round(t));
        if ~isKey(node_map, key)
            node_map(key) = owner_id;
        end
    end

    function reserve_edge(edge_map, from_pos, to_pos, t, owner_id)
        key = sprintf('%d_%d_%d_%d_%d', round(from_pos(1)), round(from_pos(2)), round(to_pos(1)), round(to_pos(2)), round(t));
        reverse_key = sprintf('%d_%d_%d_%d_%d', round(to_pos(1)), round(to_pos(2)), round(from_pos(1)), round(from_pos(2)), round(t));
        if ~isKey(edge_map, key)
            edge_map(key) = owner_id;
        end
        if ~isKey(edge_map, reverse_key)
            edge_map(reverse_key) = owner_id;
        end
    end

    function tf = is_reserved_node(node_map, pos, t, owner_id)
        owner = lookup_reserved_node(node_map, pos, t);
        tf = owner > 0 && owner ~= owner_id;
    end

    function tf = is_reserved_edge(edge_map, from_pos, to_pos, t, owner_id)
        owner = lookup_reserved_edge(edge_map, from_pos, to_pos, t);
        tf = owner > 0 && owner ~= owner_id;
    end

    function owner = lookup_reserved_node(node_map, pos, t)
        key = sprintf('%d_%d_%d', round(pos(1)), round(pos(2)), round(t));
        if isKey(node_map, key)
            owner = node_map(key);
        else
            owner = 0;
        end
    end

    function owner = lookup_reserved_edge(edge_map, from_pos, to_pos, t)
        key = sprintf('%d_%d_%d_%d_%d', round(from_pos(1)), round(from_pos(2)), round(to_pos(1)), round(to_pos(2)), round(t));
        if isKey(edge_map, key)
            owner = edge_map(key);
        else
            owner = 0;
        end
    end

    function handle_arrival(id, current_t)
        st = AGVs(id).status;
        if strcmp(st, 'Moving_Pick')
            transition_to(id, 'Loading', 6, []);
        elseif strcmp(st, 'Moving_Drop')
            transition_to(id, 'Unloading', 6, []);
        elseif strcmp(st, 'Going_Charge')
            transition_to(id, 'Charging', 30, []);
        elseif strcmp(st, 'Go_Home') || strcmp(st, 'Going_Home')
            transition_to(id, 'Idle', 0, []);
        elseif strcmp(st, 'Yielding')
            resume_after_yield(id, current_t);
        end
    end

    function resume_after_yield(id, current_t)
        resume_status = AGVs(id).yield_resume_status;
        if isempty(resume_status)
            transition_to(id, 'Idle', 0, []);
            return;
        end

        if strcmp(resume_status, 'Moving_Pick')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle', 0, []);
                AGVs(id).yield_resume_status = '';
                return;
            end
            target_id = task_list(row_idx, 2);
            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
            if plan_path(id, pick_anchor, pick_size, current_t)
                transition_to(id, 'Moving_Pick', 0, []);
                AGVs(id).yield_resume_status = '';
            else
                transition_to(id, 'Yielding', 0, max(AGVs(id).step_dur, 2));
            end
        elseif strcmp(resume_status, 'Moving_Drop')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle', 0, []);
                AGVs(id).yield_resume_status = '';
                return;
            end
            target_id = task_list(row_idx, 2);
            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
            if plan_path(id, drop_anchor, drop_size, current_t)
                transition_to(id, 'Moving_Drop', 0, []);
                AGVs(id).yield_resume_status = '';
            else
                transition_to(id, 'Yielding', 0, max(AGVs(id).step_dur, 2));
            end
        elseif strcmp(resume_status, 'Go_Home') || strcmp(resume_status, 'Going_Home')
            if AGVs(id).type == 2
                agv_area_sz = [3, 3];
            else
                agv_area_sz = [1, 1];
            end
            if plan_path(id, AGVs(id).home_pos, agv_area_sz, current_t)
                transition_to(id, 'Go_Home', 0, []);
                AGVs(id).yield_resume_status = '';
            else
                transition_to(id, 'Yielding', 0, max(AGVs(id).step_dur, 2));
            end
        elseif strcmp(resume_status, 'Going_Charge')
            AGVs(id).yield_resume_status = '';
            plan_to_charge(id, current_t);
            if ~strcmp(AGVs(id).status, 'Going_Charge')
                AGVs(id).yield_resume_status = 'Going_Charge';
                transition_to(id, 'Yielding', 0, max(AGVs(id).step_dur, 2));
            end
        else
            transition_to(id, resume_status, 0, []);
            AGVs(id).yield_resume_status = '';
        end
    end

    function finish_waiting(id, tasks_info, current_t)
        st = AGVs(id).status;

        if strcmp(st, 'Loading')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle', 0, []);
                AGVs(id).active_task_id = 0;
                return;
            end
            task_weight = tasks_info(row_idx, 3);

            if task_times(tid, 1) == 0
                task_times(tid, 1) = t;
            end
            task_start_dist(tid) = AGVs(id).total_dist;
            task_executor(tid) = id;
            AGVs(id).payload_weight = AGVs(id).payload_weight + task_weight;
            AGVs(id).load = 1;

            if ~isempty(AGVs(id).pick_queue)
                next_tid = AGVs(id).pick_queue(1);
                AGVs(id).pick_queue(1) = [];
                AGVs(id).active_task_id = next_tid;
                next_row = get_task_row(next_tid);
                if next_row == 0
                    transition_to(id, 'Idle', 0, []);
                    AGVs(id).active_task_id = 0;
                    AGVs(id).pick_queue = [];
                    AGVs(id).drop_queue = [];
                    return;
                end
                next_target_id = tasks_info(next_row, 2);
                [pick_anchor, ~, pick_size, ~] = get_task_coordinates(next_target_id);
                if plan_path(id, pick_anchor, pick_size, current_t)
                    transition_to(id, 'Moving_Pick', 0, []);
                else
                    AGVs(id).wait_timer = 2;
                    AGVs(id).pick_queue = [next_tid, AGVs(id).pick_queue];
                end
            else
                first_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = [];
                AGVs(id).active_task_id = first_drop_tid;
                drop_row = get_task_row(first_drop_tid);
                if drop_row == 0
                    transition_to(id, 'Idle', 0, []);
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    return;
                end
                drop_target_id = tasks_info(drop_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(drop_target_id);
                if plan_path(id, drop_anchor, drop_size, current_t)
                    transition_to(id, 'Moving_Drop', 0, []);
                else
                    AGVs(id).wait_timer = 2;
                    AGVs(id).drop_queue = [first_drop_tid, AGVs(id).drop_queue];
                end
            end

        elseif strcmp(st, 'Unloading')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle', 0, []);
                AGVs(id).active_task_id = 0;
                return;
            end
            task_weight = tasks_info(row_idx, 3);
            task_times(tid, 2) = t;
            task_dist_record(tid) = AGVs(id).total_dist - task_start_dist(tid);
            AGVs(id).payload_weight = max(0, AGVs(id).payload_weight - task_weight);
            AGVs(id).tasks(AGVs(id).tasks == tid) = [];

            if ~isempty(AGVs(id).drop_queue)
                next_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = [];
                AGVs(id).active_task_id = next_drop_tid;
                next_row = get_task_row(next_drop_tid);
                if next_row == 0
                    transition_to(id, 'Idle', 0, []);
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    return;
                end
                next_target_id = tasks_info(next_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(next_target_id);
                if plan_path(id, drop_anchor, drop_size, current_t)
                    transition_to(id, 'Moving_Drop', 0, []);
                else
                    AGVs(id).wait_timer = 2;
                    AGVs(id).drop_queue = [next_drop_tid, AGVs(id).drop_queue];
                end
            else
                transition_to(id, 'Idle', 0, []);
                AGVs(id).load = 0;
                AGVs(id).active_task_id = 0;
            end
        end
    end

    function export_simulation_results(num_agvs_local, AGVs_local, task_list_local, task_times_local, task_dist_record_local, task_executor_local, task_trajectories_local)
        disp('>> [Data] Exporting simulation report.');
        save_dir = fileparts(mfilename('fullpath'));

        try
            csv_file_path = fullfile(save_dir, 'task_metrics.csv');
            fid = fopen(csv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid, 'task_id,agv_id,time_sec,distance\n');
            for i = 1:size(task_list_local, 1)
                tid = task_list_local(i, 1);
                if task_times_local(tid, 2) > 0
                    t_sec = (task_times_local(tid, 2) - task_times_local(tid, 1)) / 6.0;
                    dist = task_dist_record_local(tid);
                    agv_str = sprintf('AGV-%02d', task_executor_local(tid));
                    fprintf(fid, '%d,%s,%.1f,%d\n', tid, agv_str, t_sec, dist);
                end
            end
            fclose(fid);
        catch ME
            fprintf('task_metrics.csv export failed: %s\n', ME.message);
        end

        try
            path_struct = struct();
            for i = 1:size(task_list_local, 1)
                tid = task_list_local(i, 1);
                if ~isempty(task_trajectories_local{tid})
                    fname = sprintf('task_%d', tid);
                    path_struct.(fname) = task_trajectories_local{tid};
                end
            end
            json_str = jsonencode(path_struct);
            json_file_path = fullfile(save_dir, 'task_paths.json');
            fid_json = fopen(json_file_path, 'w');
            if fid_json ~= -1
                fprintf(fid_json, '%s', json_str);
                fclose(fid_json);
            end
        catch ME
            fprintf('task_paths.json export failed: %s\n', ME.message);
        end

        try
            agv_file_path = fullfile(save_dir, 'agv_metrics.csv');
            fid_agv = fopen(agv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid_agv, 'agv_id,agv_type,battery,total_distance,total_turns\n');
            for k = 1:num_agvs_local
                fprintf(fid_agv, '%d,%d,%.2f,%d,%d\n', k, AGVs_local(k).type, AGVs_local(k).battery, AGVs_local(k).total_dist, AGVs_local(k).total_turns);
            end
            fclose(fid_agv);
        catch ME
            fprintf('agv_metrics.csv export failed: %s\n', ME.message);
        end
    end
end


