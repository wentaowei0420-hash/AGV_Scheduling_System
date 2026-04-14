function run_visualization_loop_event_sm(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    
    global mapW mapH;
    global costmap_type1 costmap_type2;

    generate_beautiful_factory_map();
    init_global_costmaps();

    f_map = gcf;
    ax = findobj(f_map, 'Type', 'Axes');
    hold(ax, 'on');
    set(f_map, 'Name', 'Event-driven Scheduling Simulation', ...
        'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', ...
        'Position', [50, 200, 1000, 700]);
    [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs);

    [AGVs, props, ~] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax);
    state_defs = build_state_definitions();

    disp('>> [System] Event-driven state-machine simulation started.');

    for k = 1:num_agvs
        AGVs(k).total_turns = 0;
        AGVs(k).last_dir = [0, 0];
        AGVs(k).pick_queue = [];
        AGVs(k).drop_queue = [];
        AGVs(k).active_task_id = 0;
        AGVs(k).interrupted_status = '';
        AGVs(k).yield_resume_status = '';
        AGVs(k).total_dist = 0;
        AGVs(k).next_event_t = 0;
        AGVs(k).wait_timer = 0;
        AGVs(k).move_timer = 0;
    end

    current_t = 0;
    MAX_EVENTS = 500000;
    event_count = 0;
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

    while event_count < MAX_EVENTS
        pending = [AGVs.next_event_t];
        finite_pending = pending(isfinite(pending));
        if isempty(finite_pending)
            break;
        end

        current_t = min(finite_pending);
        reported_conflict_keys = containers.Map('KeyType', 'char', 'ValueType', 'logical');

        while true
            due_ids = find([AGVs.next_event_t] == current_t);
            if isempty(due_ids)
                break;
            end

            for idx = 1:numel(due_ids)
                AGVs(due_ids(idx)).next_event_t = inf;
            end

            for idx = 1:numel(due_ids)
                id = due_ids(idx);
                event_count = event_count + 1;
                if ~isfield(state_defs, AGVs(id).status)
                    error('Unknown AGV state: %s', AGVs(id).status);
                end
                state_info = state_defs.(AGVs(id).status);
                state_info.handler(id, current_t);
            end
        end

        render_scene();
    end

    export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories);
    disp('>> Event-driven simulation finished.');

    function defs = build_state_definitions()
        defs = struct();
        defs.Idle = struct('category', 'idle', 'handler', @handle_idle_state);
        defs.Loading = struct('category', 'waiting', 'handler', @handle_waiting_state);
        defs.Unloading = struct('category', 'waiting', 'handler', @handle_waiting_state);
        defs.Charging = struct('category', 'waiting', 'handler', @handle_waiting_state);
        defs.Moving_Pick = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Moving_Drop = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Go_Home = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Going_Charge = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Yielding = struct('category', 'moving', 'handler', @handle_moving_state);
    end

    function transition_to(id, new_state)
        AGVs(id).status = new_state;
    end

    function schedule_now(id, event_t)
        AGVs(id).next_event_t = event_t;
    end

    function schedule_in(id, event_t, delta)
        AGVs(id).next_event_t = event_t + max(0, delta);
    end

    function deactivate(id)
        AGVs(id).next_event_t = inf;
    end

    function render_scene()
        curr_bat_list = zeros(1, num_agvs);
        for k = 1:num_agvs
            AGVs(k).vis_pos = AGVs(k).pos;
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

    function handle_idle_state(id, event_t)
        if AGVs(id).battery < 20
            plan_to_charge(id, event_t);
            return;
        end

        if AGVs(id).active_task_id > 0
            try_resume_interrupted_task(id, event_t);
            return;
        end

        if ~isempty(AGVs(id).tasks)
            try_dispatch_new_batch(id, event_t);
            return;
        end

        if try_idle_post_actions(id, event_t)
            return;
        end

        deactivate(id);
    end

    function handle_moving_state(id, event_t)
        if AGVs(id).battery < 20 && ~strcmp(AGVs(id).status, 'Going_Charge')
            AGVs(id).interrupted_status = AGVs(id).status;
            plan_to_charge(id, event_t);
            return;
        end

        move_status = execute_move_event(id, event_t);
        if move_status == 1
            handle_arrival(id, event_t);
        elseif move_status < 0
            resolve_conflict(id, -move_status, task_list, event_t);
            if AGVs(id).next_event_t == inf
                schedule_in(id, event_t, AGVs(id).step_dur);
            end
        else
            schedule_in(id, event_t, AGVs(id).step_dur);
        end
    end

    function handle_waiting_state(id, event_t)
        if strcmp(AGVs(id).status, 'Charging')
            AGVs(id).battery = min(100, AGVs(id).battery + 2.0 * max(1, AGVs(id).wait_timer));
            if AGVs(id).battery >= 100
                transition_to(id, 'Idle');
                schedule_now(id, event_t);
            else
                AGVs(id).wait_timer = max(1, ceil((100 - AGVs(id).battery) / 2.0));
                schedule_in(id, event_t, AGVs(id).wait_timer);
            end
            return;
        end

        finish_waiting(id, task_list, event_t);
    end

    function try_resume_interrupted_task(id, event_t)
        tid = AGVs(id).active_task_id;
        row_idx = get_task_row(tid);
        if row_idx == 0
            AGVs(id).active_task_id = 0;
            schedule_now(id, event_t);
            return;
        end

        target_id = task_list(row_idx, 2);
        if strcmp(AGVs(id).interrupted_status, 'Moving_Drop')
            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
            if plan_path(id, drop_anchor, drop_size)
                transition_to(id, 'Moving_Drop');
                AGVs(id).interrupted_status = '';
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        elseif strcmp(AGVs(id).interrupted_status, 'Moving_Pick')
            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
            if plan_path(id, pick_anchor, pick_size)
                transition_to(id, 'Moving_Pick');
                AGVs(id).interrupted_status = '';
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        else
            AGVs(id).active_task_id = 0;
            schedule_now(id, event_t);
        end
    end

    function try_dispatch_new_batch(id, event_t)
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
            deactivate(id);
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
            schedule_now(id, event_t);
            return;
        end

        target_id = task_list(row_idx, 2);
        [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
        if plan_path(id, pick_anchor, pick_size)
            transition_to(id, 'Moving_Pick');
            schedule_in(id, event_t, AGVs(id).step_dur);
        else
            AGVs(id).pick_queue = [];
            AGVs(id).drop_queue = [];
            AGVs(id).active_task_id = 0;
            schedule_in(id, event_t, 1);
        end
    end

    function active = try_idle_post_actions(id, event_t)
        active = true;
        if AGVs(id).type == 2
            agv_area_sz = [3, 3];
        else
            agv_area_sz = [1, 1];
        end

        home_pos = AGVs(id).home_pos;
        if AGVs(id).battery < 95
            if is_at_charge_station(id, agv_area_sz)
                transition_to(id, 'Charging');
                AGVs(id).wait_timer = max(1, ceil((100 - AGVs(id).battery) / 2.0));
                schedule_in(id, event_t, AGVs(id).wait_timer);
            else
                plan_to_charge(id, event_t);
            end
        elseif ~check_in_area(AGVs(id).pos, home_pos, agv_area_sz)
            if plan_path(id, home_pos, agv_area_sz)
                transition_to(id, 'Go_Home');
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        else
            active = false;
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
    function resolve_conflict(id_self, id_blocker, tasks_info, event_t)
        pos_self = AGVs(id_self).pos;
        target_self = AGVs(id_self).path(AGVs(id_self).path_idx, 1:2);
        pos_blocker = AGVs(id_blocker).pos;

        other_next = get_planned_next_cell(id_blocker);
        is_swapping = isequal(target_self, pos_blocker) && isequal(other_next, pos_self);
        is_same_target = isequal(target_self, other_next);

        conflict_name = 'Node contention';
        if is_swapping
            conflict_name = 'Head-on swap';
        elseif isequal(target_self, pos_blocker)
            if AGVs(id_blocker).next_event_t > event_t || ~is_moving_state(AGVs(id_blocker).status)
                conflict_name = 'Occupied node';
            else
                conflict_name = 'Rear-end';
            end
        elseif is_same_target
            conflict_name = 'Node contention';
        end

        conflict_pair = sort([id_self, id_blocker]);
        conflict_key = sprintf('%d_%d_%d', round(event_t), conflict_pair(1), conflict_pair(2));
        if isKey(reported_conflict_keys, conflict_key)
            return;
        end
        reported_conflict_keys(conflict_key) = true;

        send_conflict_webhook(round(event_t), id_self, pos_self, id_blocker, pos_blocker, conflict_name);

        P_self = calculate_ahp_priority(AGVs(id_self), tasks_info, event_t);
        P_blocker = calculate_ahp_priority(AGVs(id_blocker), tasks_info, event_t);
        should_self_yield = (P_self < P_blocker) || (P_self == P_blocker && id_self > id_blocker);
        if should_self_yield
            loser_id = id_self;
            winner_id = id_blocker;
        else
            loser_id = id_blocker;
            winner_id = id_self;
        end

        if plan_yield_path(loser_id, winner_id)
            AGVs(loser_id).yield_resume_status = AGVs(loser_id).status;
            transition_to(loser_id, 'Yielding');
            schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
        elseif ~isempty(AGVs(loser_id).target_node) && plan_path(loser_id, AGVs(loser_id).target_node, [1, 1])
            schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
        else
            schedule_in(loser_id, event_t, max(1, AGVs(loser_id).step_dur));
        end

        if AGVs(winner_id).next_event_t == inf && is_moving_state(AGVs(winner_id).status)
            schedule_in(winner_id, event_t, AGVs(winner_id).step_dur);
        end
    end

    function plan_to_charge(id, event_t)
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
        best_station_target = [];
        best_station_path = [];

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
                [candidate_path, candidate_target, candidate_cost] = find_best_target_path(id, station_pos, charge_area_sz, 'charge');
                if ~isempty(candidate_path) && candidate_cost < best_cost
                    best_cost = candidate_cost;
                    best_station_target = candidate_target;
                    best_station_path = candidate_path;
                end
            end
        end

        if ~isempty(best_station_path)
            assign_planned_path(id, best_station_path, best_station_target);
            transition_to(id, 'Going_Charge');
            schedule_in(id, event_t, AGVs(id).step_dur);
        else
            schedule_in(id, event_t, 5);
        end
    end

    function [best_path, best_target, best_cost] = find_best_target_path(id, target_anchor, area_size, planning_mode)
        if nargin < 3 || isempty(area_size)
            area_size = [2, 2];
        end
        if nargin < 4 || isempty(planning_mode)
            planning_mode = 'task';
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
        if isempty(valid_targets)
            return;
        end

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
            if ~isempty(candidate_path) && candidate_cost < best_cost
                best_cost = candidate_cost;
                best_target = candidate_target;
                best_path = candidate_path;
            end
        end
    end

    function assign_planned_path(id, path, actual_target)
        AGVs(id).path = path;
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

    function success = plan_path(id, target_anchor, area_size, planning_mode)
        if nargin < 3 || isempty(area_size)
            area_size = [2, 2];
        end
        if nargin < 4 || isempty(planning_mode)
            planning_mode = 'task';
        end
        [path, actual_target] = find_best_target_path(id, target_anchor, area_size, planning_mode);
        if ~isempty(path)
            assign_planned_path(id, path, actual_target);
            success = true;
        else
            success = false;
        end
    end

    function success = plan_yield_path(id, blocker_id)
        success = false;
        curr_pos = AGVs(id).pos;
        blocker_pos = AGVs(blocker_id).pos;
        current_gap = abs(curr_pos(1) - blocker_pos(1)) + abs(curr_pos(2) - blocker_pos(2));
        candidate_nodes = [];

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

        for c_idx = 1:size(candidate_nodes, 1)
            candidate = candidate_nodes(c_idx, 1:2);
            if isequal(candidate, curr_pos) || isequal(candidate, blocker_pos)
                continue;
            end
            if candidate_nodes(c_idx, 3) < current_gap
                continue;
            end
            if plan_path(id, candidate, [1, 1])
                success = true;
                return;
            end
        end
    end
    function status = execute_move_event(id, event_t)
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            status = 1;
            return;
        end

        curr_pos = AGVs(id).pos;
        next_node = AGVs(id).path(AGVs(id).path_idx, 1:2);
        nr = next_node(1);
        nc = next_node(2);

        for other = 1:num_agvs
            if other == id
                continue;
            end
            other_curr = AGVs(other).pos;
            if AGVs(other).next_event_t == event_t && is_moving_state(AGVs(other).status) && ...
                    ~isempty(AGVs(other).path) && AGVs(other).path_idx <= size(AGVs(other).path, 1)
                other_next = AGVs(other).path(AGVs(other).path_idx, 1:2);
            else
                other_next = other_curr;
            end

            if nr == other_next(1) && nc == other_next(2)
                status = -other;
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2) && ...
                    other_next(1) == curr_pos(1) && other_next(2) == curr_pos(2)
                status = -other;
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2) && AGVs(other).next_event_t > event_t
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

    function handle_arrival(id, event_t)
        st = AGVs(id).status;
        if strcmp(st, 'Moving_Pick')
            transition_to(id, 'Loading');
            AGVs(id).wait_timer = 6;
            schedule_in(id, event_t, AGVs(id).wait_timer);
        elseif strcmp(st, 'Moving_Drop')
            transition_to(id, 'Unloading');
            AGVs(id).wait_timer = 6;
            schedule_in(id, event_t, AGVs(id).wait_timer);
        elseif strcmp(st, 'Going_Charge')
            transition_to(id, 'Charging');
            AGVs(id).wait_timer = max(1, ceil((100 - AGVs(id).battery) / 2.0));
            schedule_in(id, event_t, AGVs(id).wait_timer);
        elseif strcmp(st, 'Go_Home')
            transition_to(id, 'Idle');
            schedule_now(id, event_t);
        elseif strcmp(st, 'Yielding')
            resume_after_yield(id, event_t);
        else
            schedule_now(id, event_t);
        end
    end

    function resume_after_yield(id, event_t)
        resume_status = AGVs(id).yield_resume_status;
        if isempty(resume_status)
            transition_to(id, 'Idle');
            schedule_now(id, event_t);
            return;
        end

        if strcmp(resume_status, 'Moving_Pick')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle');
                AGVs(id).yield_resume_status = '';
                schedule_now(id, event_t);
                return;
            end
            target_id = task_list(row_idx, 2);
            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
            if plan_path(id, pick_anchor, pick_size)
                transition_to(id, 'Moving_Pick');
                AGVs(id).yield_resume_status = '';
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        elseif strcmp(resume_status, 'Moving_Drop')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle');
                AGVs(id).yield_resume_status = '';
                schedule_now(id, event_t);
                return;
            end
            target_id = task_list(row_idx, 2);
            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
            if plan_path(id, drop_anchor, drop_size)
                transition_to(id, 'Moving_Drop');
                AGVs(id).yield_resume_status = '';
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        elseif strcmp(resume_status, 'Go_Home')
            if AGVs(id).type == 2
                area_sz = [3, 3];
            else
                area_sz = [1, 1];
            end
            if plan_path(id, AGVs(id).home_pos, area_sz)
                transition_to(id, 'Go_Home');
                AGVs(id).yield_resume_status = '';
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        elseif strcmp(resume_status, 'Going_Charge')
            AGVs(id).yield_resume_status = '';
            plan_to_charge(id, event_t);
        else
            transition_to(id, resume_status);
            AGVs(id).yield_resume_status = '';
            schedule_now(id, event_t);
        end
    end

    function finish_waiting(id, tasks_info, event_t)
        st = AGVs(id).status;
        if strcmp(st, 'Loading')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle');
                AGVs(id).active_task_id = 0;
                schedule_now(id, event_t);
                return;
            end
            task_weight = tasks_info(row_idx, 3);
            if task_times(tid, 1) == 0
                task_times(tid, 1) = event_t;
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
                    transition_to(id, 'Idle');
                    AGVs(id).active_task_id = 0;
                    AGVs(id).pick_queue = [];
                    AGVs(id).drop_queue = [];
                    schedule_now(id, event_t);
                    return;
                end
                next_target_id = tasks_info(next_row, 2);
                [pick_anchor, ~, pick_size, ~] = get_task_coordinates(next_target_id);
                if plan_path(id, pick_anchor, pick_size)
                    transition_to(id, 'Moving_Pick');
                    schedule_in(id, event_t, AGVs(id).step_dur);
                else
                    AGVs(id).pick_queue = [next_tid, AGVs(id).pick_queue];
                    schedule_in(id, event_t, 1);
                end
            else
                first_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = [];
                AGVs(id).active_task_id = first_drop_tid;
                drop_row = get_task_row(first_drop_tid);
                if drop_row == 0
                    transition_to(id, 'Idle');
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    schedule_now(id, event_t);
                    return;
                end
                drop_target_id = tasks_info(drop_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(drop_target_id);
                if plan_path(id, drop_anchor, drop_size)
                    transition_to(id, 'Moving_Drop');
                    schedule_in(id, event_t, AGVs(id).step_dur);
                else
                    AGVs(id).drop_queue = [first_drop_tid, AGVs(id).drop_queue];
                    schedule_in(id, event_t, 1);
                end
            end
        elseif strcmp(st, 'Unloading')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                transition_to(id, 'Idle');
                AGVs(id).active_task_id = 0;
                schedule_now(id, event_t);
                return;
            end
            task_weight = tasks_info(row_idx, 3);
            task_times(tid, 2) = event_t;
            task_dist_record(tid) = AGVs(id).total_dist - task_start_dist(tid);
            AGVs(id).payload_weight = max(0, AGVs(id).payload_weight - task_weight);
            AGVs(id).tasks(AGVs(id).tasks == tid) = [];

            if ~isempty(AGVs(id).drop_queue)
                next_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = [];
                AGVs(id).active_task_id = next_drop_tid;
                next_row = get_task_row(next_drop_tid);
                if next_row == 0
                    transition_to(id, 'Idle');
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    schedule_now(id, event_t);
                    return;
                end
                next_target_id = tasks_info(next_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(next_target_id);
                if plan_path(id, drop_anchor, drop_size)
                    transition_to(id, 'Moving_Drop');
                    schedule_in(id, event_t, AGVs(id).step_dur);
                else
                    AGVs(id).drop_queue = [next_drop_tid, AGVs(id).drop_queue];
                    schedule_in(id, event_t, 1);
                end
            else
                transition_to(id, 'Idle');
                AGVs(id).load = 0;
                AGVs(id).active_task_id = 0;
                schedule_now(id, event_t);
            end
        else
            transition_to(id, 'Idle');
            schedule_now(id, event_t);
        end
    end

    function tf = is_moving_state(state_name)
        tf = ismember(state_name, {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home', 'Yielding'});
    end

    function next_cell = get_planned_next_cell(id)
        if ~isempty(AGVs(id).path) && AGVs(id).path_idx <= size(AGVs(id).path, 1)
            next_cell = AGVs(id).path(AGVs(id).path_idx, 1:2);
        else
            next_cell = AGVs(id).pos;
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


