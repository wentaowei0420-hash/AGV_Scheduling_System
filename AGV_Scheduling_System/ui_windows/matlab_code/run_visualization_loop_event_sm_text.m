function run_visualization_loop_event_sm_text(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
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

    reservation_horizon_steps = 6;
    max_departure_wait_steps = 4;
    reservation_cache = struct();
    reservation_cache.node = containers.Map('KeyType', 'char', 'ValueType', 'double');
    reservation_cache.edge = containers.Map('KeyType', 'char', 'ValueType', 'double');
    reservation_cache.built_at = -inf;
    reservation_dirty = true;
    last_window_conflict = struct('self_id', 0, 'blocker_id', 0, 'type', 'none', 'first_t', -inf, 'node', []);
    last_runtime_conflict = struct('self_id', 0, 'blocker_id', 0, 'reason', 'none', 'event_t', -inf, 'node', []);
    debug_conflict_log = true;
    wait_clearance_timeout = max(10, reservation_horizon_steps * 3);
    wait_clearance_retry_limit = 4;
    safe_harbor_nodes = build_safe_harbor_nodes();
    stall_detect_threshold = max(8, reservation_horizon_steps * 2);
    imminent_window_buffer_steps = 2;
    repeat_wait_replan_threshold = 2;
    repeat_wait_memory_horizon = max(wait_clearance_timeout, reservation_horizon_steps * 2);
    last_progress_t = 0;

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
        AGVs(k).reservation_hold_node = [];
        AGVs(k).reservation_hold_until = -inf;
        AGVs(k).resume_after_wait = false;
        AGVs(k).wait_resume_status = '';
        AGVs(k).wait_resume_target = [];
        AGVs(k).wait_resume_area = [1, 1];
        AGVs(k).wait_resume_mode = 'task';
        AGVs(k).wait_blocker_id = 0;
        AGVs(k).wait_start_t = -inf;
        AGVs(k).clearance_retry_count = 0;
        AGVs(k).rear_end_retry_count = 0;
        AGVs(k).last_wait_signature = '';
        AGVs(k).last_wait_assign_t = -inf;
        AGVs(k).repeat_wait_count = 0;
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
            conflict_log('EVENT_QUEUE_EMPTY stop_reason=no_finite_events');
            dump_event_queue_state('queue_empty');
            break;
        end

        current_t = min(finite_pending);
        reported_conflict_keys = containers.Map('KeyType', 'char', 'ValueType', 'logical');

        while true
            due_ids = find([AGVs.next_event_t] == current_t);
            if isempty(due_ids)
                break;
            end

            conflict_records = collect_due_conflicts_batch(due_ids, current_t, task_list);
            blocked_ids = zeros(0, 1);
            for rec_idx = 1:numel(conflict_records)
                rec = conflict_records(rec_idx);
                resolve_conflict_precomputed(rec, current_t);
                blocked_ids(end + 1, 1) = rec.loser_id; %#ok<AGROW>
            end

            for idx = 1:numel(due_ids)
                id = due_ids(idx);
                if any(blocked_ids == id) || AGVs(id).next_event_t ~= current_t
                    continue;
                end
                AGVs(id).next_event_t = inf;
                event_count = event_count + 1;
                if ~isfield(state_defs, AGVs(id).status)
                    error('Unknown AGV state: %s', AGVs(id).status);
                end
                state_info = state_defs.(AGVs(id).status);
                state_info.handler(id, current_t);
            end
        end

        if current_t - last_progress_t >= stall_detect_threshold
            conflict_log('STALL_OBSERVED current_t=%g last_progress_t=%g threshold=%g (Tarjan disabled)', ...
                current_t, last_progress_t, stall_detect_threshold);
            dump_event_queue_state('stall_detected');
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
        defs.Waiting_Clearance = struct('category', 'waiting', 'handler', @handle_waiting_state);
        defs.Moving_Pick = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Moving_Drop = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Go_Home = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Going_Charge = struct('category', 'moving', 'handler', @handle_moving_state);
        defs.Yielding = struct('category', 'moving', 'handler', @handle_moving_state);
    end

    function transition_to(id, new_state)
        AGVs(id).status = new_state;
        reservation_dirty = true;
    end

    function schedule_now(id, event_t)
        AGVs(id).next_event_t = event_t;
        reservation_dirty = true;
    end

    function schedule_in(id, event_t, delta)
        AGVs(id).next_event_t = event_t + max(0, delta);
        reservation_dirty = true;
    end

    function conflict_log(fmt, varargin)
        if ~debug_conflict_log
            return;
        end
        fprintf('[Conflict][t=%g] %s\n', current_t_fallback(), sprintf(fmt, varargin{:}));
    end

    function dump_event_queue_state(tag)
        conflict_log('STATE_SNAPSHOT tag=%s', tag);
        for sid = 1:num_agvs
            conflict_log('  AGV%d state=%s pos=%s next_t=%g target=%s path_idx=%d/%d wait_blocker=AGV%d hold_until=%g resume=%s', ...
                sid, AGVs(sid).status, node_str(AGVs(sid).pos), AGVs(sid).next_event_t, ...
                node_str(AGVs(sid).target_node), AGVs(sid).path_idx, size(AGVs(sid).path, 1), ...
                AGVs(sid).wait_blocker_id, AGVs(sid).reservation_hold_until, AGVs(sid).wait_resume_status);
        end
    end

    function txt = node_str(node)
        if isempty(node)
            txt = '[]';
        else
            txt = sprintf('[%d,%d]', round(node(1)), round(node(2)));
        end
    end

    function deactivate(id)
        AGVs(id).next_event_t = inf;
        reservation_dirty = true;
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
            % Treat charging progress as legitimate simulation progress so
            % the watchdog does not flag long charge intervals as stalls.
            last_progress_t = event_t;
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

        if strcmp(AGVs(id).status, 'Waiting_Clearance')
            AGVs(id).reservation_hold_until = event_t;
            AGVs(id).reservation_hold_node = AGVs(id).pos;
            reservation_dirty = true;
            if event_t - AGVs(id).wait_start_t > wait_clearance_timeout
                AGVs(id).clearance_retry_count = wait_clearance_retry_limit;
            end
            if ~isempty(AGVs(id).wait_resume_target) && ...
                    plan_path(id, AGVs(id).wait_resume_target, AGVs(id).wait_resume_area, AGVs(id).wait_resume_mode, event_t)
                conflict_log('AGV%d Waiting_Clearance resolved at %s, resume=%s target=%s', ...
                    id, node_str(AGVs(id).pos), AGVs(id).wait_resume_status, node_str(AGVs(id).wait_resume_target));
                transition_to(id, AGVs(id).wait_resume_status);
                reset_wait_recovery_state(id);
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                AGVs(id).clearance_retry_count = AGVs(id).clearance_retry_count + 1;
                if AGVs(id).clearance_retry_count >= wait_clearance_retry_limit && ...
                        ~is_safe_wait_node(AGVs(id).pos) && ...
                        apply_safe_harbor_strategy(id, AGVs(id).wait_blocker_id, event_t, event_t + max(2, AGVs(id).step_dur))
                    conflict_log('AGV%d Waiting_Clearance retry overflow at %s, escalate to safe harbor, blocker=AGV%d', ...
                        id, node_str(AGVs(id).pos), AGVs(id).wait_blocker_id);
                else
                    conflict_log('AGV%d Waiting_Clearance hold at %s retry=%d blocker=AGV%d resume_target=%s', ...
                        id, node_str(AGVs(id).pos), AGVs(id).clearance_retry_count, AGVs(id).wait_blocker_id, node_str(AGVs(id).wait_resume_target));
                    schedule_in(id, event_t, 1);
                end
            end
            return;
        end

        % Loading and unloading are also legitimate progress states even
        % though the AGV remains physically stationary.
        last_progress_t = event_t;
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
        % All AGVs physically occupy a single grid cell when parking/charging.
        agv_area_sz = [1, 1];

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
        conflict_info = classify_conflict_info(id_self, id_blocker, event_t);

        conflict_pair = sort([id_self, id_blocker]);
        conflict_key = sprintf('%d_%d_%d', round(event_t), conflict_pair(1), conflict_pair(2));
        if isKey(reported_conflict_keys, conflict_key)
            return;
        end
        reported_conflict_keys(conflict_key) = true;

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

        % For occupied-node and rear-end conflicts, the vehicle trying to
        % enter the already-held resource must always yield regardless of AHP.
        if strcmp(conflict_info.name, 'Occupied node') || strcmp(conflict_info.name, 'Rear-end')
            loser_id = id_self;
            winner_id = id_blocker;
        elseif any(strcmp(conflict_info.name, {'Head-on swap', 'Head-on meet'}))
            [loser_id, winner_id] = select_headon_retreat_vehicle(id_self, id_blocker, event_t, P_self, P_blocker);
        end

        if strcmp(conflict_info.name, 'Node contention')
            conflict_log('AGV%d vs AGV%d classified=%s node=%s winner=AGV%d loser=AGV%d -> wait_then_replan/safe_harbor', ...
                id_self, id_blocker, conflict_info.name, node_str(conflict_info.conflict_node), winner_id, loser_id);
            if apply_wait_then_replan_strategy(loser_id, winner_id, conflict_info, event_t)
                % handled
            elseif plan_yield_path(loser_id, winner_id, event_t)
                conflict_log('AGV%d fallback action=yield_path', loser_id);
                AGVs(loser_id).yield_resume_status = AGVs(loser_id).status;
                transition_to(loser_id, 'Yielding');
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                apply_wait_only_strategy(loser_id, winner_id, event_t, 'node_contention_force_graph');
            end
        elseif strcmp(conflict_info.name, 'Occupied node')
            conflict_log('AGV%d vs AGV%d classified=%s blocker_pos=%s actor=AGV%d -> replan dynamic target', ...
                id_self, id_blocker, conflict_info.name, node_str(AGVs(winner_id).pos), loser_id);
            if replan_dynamic_target(loser_id, event_t)
                conflict_log('AGV%d action=replan_dynamic_target success target=%s', loser_id, node_str(AGVs(loser_id).target_node));
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                if AGVs(winner_id).wait_timer > 2
                    sleep_time = AGVs(winner_id).wait_timer - 1;
                    conflict_log('AGV%d action=queue_behind_occupied at %s. Blocker AGV%d busy. Sleeping for %d secs.', ...
                        loser_id, node_str(AGVs(loser_id).pos), winner_id, sleep_time);
                    schedule_in(loser_id, event_t, sleep_time);
                else
                    apply_wait_only_strategy(loser_id, winner_id, event_t, 'occupied_no_dynamic_target');
                end
            end
        elseif strcmp(conflict_info.name, 'Rear-end')
            conflict_log('AGV%d vs AGV%d classified=%s overtaker=AGV%d leader=AGV%d -> bypass/overtake', ...
                id_self, id_blocker, conflict_info.name, loser_id, winner_id);
            if plan_bypass_path(loser_id, winner_id, event_t)
                AGVs(loser_id).rear_end_retry_count = 0;
                conflict_log('AGV%d action=bypass_overtake success', loser_id);
                transition_to(loser_id, 'Yielding');
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            elseif plan_rear_end_escape(loser_id, winner_id, event_t)
                AGVs(loser_id).rear_end_retry_count = 0;
                conflict_log('AGV%d action=replan_rear_end_escape success target=%s', loser_id, node_str(AGVs(loser_id).target_node));
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                AGVs(loser_id).rear_end_retry_count = AGVs(loser_id).rear_end_retry_count + 1;
                if AGVs(loser_id).rear_end_retry_count >= 3 && ...
                        apply_safe_harbor_strategy(loser_id, winner_id, event_t, event_t + max(2, AGVs(winner_id).step_dur))
                    conflict_log('AGV%d action=bypass_overtake retry_overflow -> safe_harbor', loser_id);
                else
                    conflict_log('AGV%d action=bypass_overtake failed retry=%d -> wait_only_strategy', ...
                        loser_id, AGVs(loser_id).rear_end_retry_count);
                    apply_wait_only_strategy(loser_id, winner_id, event_t, 'rear_end_retry');
                end
            end
        else
            conflict_log('AGV%d vs AGV%d classified=%s winner=AGV%d retreat=AGV%d -> safe_harbor/replan/yield', ...
                id_self, id_blocker, conflict_info.name, winner_id, loser_id);
            if apply_safe_harbor_strategy(loser_id, winner_id, event_t, conflict_info.conflict_t + max(1, AGVs(winner_id).step_dur))
                % handled
            elseif replan_dynamic_target(loser_id, event_t)
                conflict_log('AGV%d fallback action=replan_dynamic_target target=%s', loser_id, node_str(AGVs(loser_id).target_node));
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            elseif plan_yield_path(loser_id, winner_id, event_t)
                conflict_log('AGV%d fallback action=yield_path', loser_id);
                AGVs(loser_id).yield_resume_status = AGVs(loser_id).status;
                transition_to(loser_id, 'Yielding');
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                apply_wait_only_strategy(loser_id, winner_id, event_t, 'fallback');
            end
        end

        if AGVs(winner_id).next_event_t == inf && is_moving_state(AGVs(winner_id).status)
            schedule_in(winner_id, event_t, AGVs(winner_id).step_dur);
        end
    end

    function resolve_conflict_precomputed(rec, event_t)
        conflict_pair = sort([rec.self_id, rec.blocker_id]);
        conflict_key = sprintf('%d_%d_%d', round(event_t), conflict_pair(1), conflict_pair(2));
        if isKey(reported_conflict_keys, conflict_key)
            return;
        end
        reported_conflict_keys(conflict_key) = true;

        loser_id = rec.loser_id;
        winner_id = rec.winner_id;
        conflict_name = rec.classified_type;

        if strcmp(conflict_name, 'Node contention')
            conflict_info = struct('name', conflict_name, 'conflict_node', rec.conflict_node, ...
                'conflict_t', rec.first_conflict_t, 'wait_node', get_previous_path_node(loser_id, rec.conflict_node));
            conflict_log('BATCH AGV%d vs AGV%d classified=%s node=%s window=%s first_t=%g winner=AGV%d loser=AGV%d', ...
                rec.self_id, rec.blocker_id, conflict_name, node_str(rec.conflict_node), rec.window_type, rec.first_conflict_t, winner_id, loser_id);
            if apply_wait_then_replan_strategy(loser_id, winner_id, conflict_info, event_t)
                % handled
            elseif plan_yield_path(loser_id, winner_id, event_t)
                conflict_log('AGV%d fallback action=yield_path', loser_id);
                AGVs(loser_id).yield_resume_status = AGVs(loser_id).status;
                transition_to(loser_id, 'Yielding');
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                apply_wait_only_strategy(loser_id, winner_id, event_t, 'batch_node_contention_force_graph');
            end
        elseif strcmp(conflict_name, 'Occupied node')
            conflict_log('BATCH AGV%d vs AGV%d classified=%s blocker_pos=%s window=%s first_t=%g actor=AGV%d -> replan dynamic target', ...
                rec.self_id, rec.blocker_id, conflict_name, node_str(AGVs(winner_id).pos), rec.window_type, rec.first_conflict_t, loser_id);
            if replan_dynamic_target(loser_id, event_t)
                conflict_log('AGV%d action=replan_dynamic_target success target=%s', loser_id, node_str(AGVs(loser_id).target_node));
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                if AGVs(winner_id).wait_timer > 2
                    sleep_time = AGVs(winner_id).wait_timer - 1;
                    conflict_log('AGV%d action=queue_behind_occupied at %s. Blocker AGV%d busy. Sleeping for %d secs.', ...
                        loser_id, node_str(AGVs(loser_id).pos), winner_id, sleep_time);
                    schedule_in(loser_id, event_t, sleep_time);
                else
                    apply_wait_only_strategy(loser_id, winner_id, event_t, 'batch_occupied_no_dynamic_target');
                end
            end
        elseif strcmp(conflict_name, 'Rear-end')
            conflict_log('BATCH AGV%d vs AGV%d classified=%s window=%s first_t=%g overtaker=AGV%d leader=AGV%d', ...
                rec.self_id, rec.blocker_id, conflict_name, rec.window_type, rec.first_conflict_t, loser_id, winner_id);
            if plan_bypass_path(loser_id, winner_id, event_t)
                AGVs(loser_id).rear_end_retry_count = 0;
                conflict_log('AGV%d action=bypass_overtake success', loser_id);
                transition_to(loser_id, 'Yielding');
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            elseif plan_rear_end_escape(loser_id, winner_id, event_t)
                AGVs(loser_id).rear_end_retry_count = 0;
                conflict_log('AGV%d action=replan_rear_end_escape success target=%s', loser_id, node_str(AGVs(loser_id).target_node));
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                AGVs(loser_id).rear_end_retry_count = AGVs(loser_id).rear_end_retry_count + 1;
                if AGVs(loser_id).rear_end_retry_count >= 3 && ...
                        apply_safe_harbor_strategy(loser_id, winner_id, event_t, event_t + max(2, AGVs(winner_id).step_dur))
                    conflict_log('AGV%d action=bypass_overtake retry_overflow -> safe_harbor', loser_id);
                else
                    conflict_log('AGV%d action=bypass_overtake failed retry=%d -> wait_only_strategy', ...
                        loser_id, AGVs(loser_id).rear_end_retry_count);
                    apply_wait_only_strategy(loser_id, winner_id, event_t, 'batch_rear_end_retry');
                end
            end
        else
            conflict_log('BATCH AGV%d vs AGV%d classified=%s window=%s first_t=%g winner=AGV%d retreat=AGV%d', ...
                rec.self_id, rec.blocker_id, conflict_name, rec.window_type, rec.first_conflict_t, winner_id, loser_id);
            if apply_safe_harbor_strategy(loser_id, winner_id, event_t, rec.first_conflict_t + max(1, AGVs(winner_id).step_dur))
                % handled
            elseif replan_dynamic_target(loser_id, event_t)
                conflict_log('AGV%d fallback action=replan_dynamic_target target=%s', loser_id, node_str(AGVs(loser_id).target_node));
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            elseif plan_yield_path(loser_id, winner_id, event_t)
                conflict_log('AGV%d fallback action=yield_path', loser_id);
                AGVs(loser_id).yield_resume_status = AGVs(loser_id).status;
                transition_to(loser_id, 'Yielding');
                schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
            else
                apply_wait_only_strategy(loser_id, winner_id, event_t, 'batch_fallback');
            end
        end
    end

    function success = replan_dynamic_target(id, event_t)
        % Re-select a dynamic target cell inside the logical task area
        % instead of stubbornly retrying a single blocked grid cell.
        success = false;
        st = AGVs(id).status;
        if strcmp(st, 'Moving_Pick')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx > 0
                target_id = task_list(row_idx, 2);
                [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
                success = plan_path(id, pick_anchor, pick_size, 'task', event_t);
            end
        elseif strcmp(st, 'Moving_Drop')
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx > 0
                target_id = task_list(row_idx, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
                success = plan_path(id, drop_anchor, drop_size, 'task', event_t);
            end
        elseif strcmp(st, 'Go_Home')
            success = plan_path(id, AGVs(id).home_pos, [1, 1], 'task', event_t);
        else
            if ~isempty(AGVs(id).target_node)
                success = plan_path(id, AGVs(id).target_node, [1, 1], 'task', event_t);
            end
        end
    end

    function plan_to_charge(id, event_t)
        if isfield(props(AGVs(id).type), 'charge_stations') && ~isempty(props(AGVs(id).type).charge_stations)
            candidate_stations = props(AGVs(id).type).charge_stations;
        else
            candidate_stations = props(AGVs(id).type).charge;
        end

        % Charging berth occupancy is evaluated per single-cell AGV footprint.
        charge_area_sz = [1, 1];

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

    function [best_path, best_target, best_cost, best_wait_steps] = find_best_target_path(id, target_anchor, area_size, planning_mode, current_t)
        if nargin < 3 || isempty(area_size)
            area_size = [2, 2];
        end
        if nargin < 4 || isempty(planning_mode)
            planning_mode = 'task';
        end
        if nargin < 5 || isempty(current_t)
            current_t = current_t_fallback();
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

        reservations = get_reservation_snapshot(current_t);

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

    function assign_planned_path(id, path, actual_target)
        AGVs(id).path = path;
        AGVs(id).path_idx = 2;
        AGVs(id).target_node = actual_target;
        reservation_dirty = true;
    end

    function row_idx = get_task_row(task_id)
        row_idx = 0;
        if isempty(task_id) || task_id < 1 || task_id > numel(task_row_map)
            return;
        end
        row_idx = task_row_map(task_id);
    end

    function success = plan_path(id, target_anchor, area_size, planning_mode, current_t)
        if nargin < 3 || isempty(area_size)
            area_size = [2, 2];
        end
        if nargin < 4 || isempty(planning_mode)
            planning_mode = 'task';
        end
        if nargin < 5 || isempty(current_t)
            current_t = current_t_fallback();
        end
        [path, actual_target, ~, wait_steps] = find_best_target_path(id, target_anchor, area_size, planning_mode, current_t);
        if ~isempty(path)
            assign_planned_path(id, path, actual_target);
            if wait_steps > 0
                AGVs(id).next_event_t = current_t + wait_steps;
            end
            success = true;
        else
            success = false;
        end
    end

    function t_now = current_t_fallback()
        t_now = current_t;
        if isempty(t_now)
            t_now = 0;
        end
    end

    function reservations = get_reservation_snapshot(query_t)
        if reservation_dirty || ~isfinite(reservation_cache.built_at) || ...
                query_t >= reservation_cache.built_at + reservation_horizon_steps
            reservation_cache = build_sliding_window_reservations(query_t);
            reservation_cache.built_at = query_t;
            reservation_dirty = false;
        end
        reservations = reservation_cache;
    end

    function reservations = build_sliding_window_reservations(current_t)
        reservations.node = containers.Map('KeyType', 'char', 'ValueType', 'double');
        reservations.edge = containers.Map('KeyType', 'char', 'ValueType', 'double');
        horizon_t = get_window_horizon_time(current_t);
        for other = 1:num_agvs
            curr_pos = AGVs(other).pos;
            hold_until = min(horizon_t, max(current_t, AGVs(other).next_event_t));
            if ~isempty(AGVs(other).reservation_hold_node)
                hold_until = max(hold_until, min(horizon_t, AGVs(other).reservation_hold_until));
            end
            if ~is_moving_state(AGVs(other).status) || isempty(AGVs(other).path) || AGVs(other).path_idx > size(AGVs(other).path, 1)
                hold_until = max(hold_until, horizon_t);
            end
            reserve_from = current_t;
            for tau = reserve_from:hold_until
                reserve_node(reservations.node, curr_pos, tau, other);
            end
            future_events = build_agv_future_events(other, current_t, horizon_t);
            for idx = 1:numel(future_events)
                evt = future_events(idx);
                for tau = (evt.start_t + 1):evt.end_t
                    reserve_node(reservations.node, evt.to_node, tau, other);
                    if ~isempty(evt.from_node)
                        reserve_edge(reservations.edge, evt.from_node, evt.to_node, tau, other);
                        if tau < evt.end_t
                            reserve_node(reservations.node, evt.from_node, tau, other);
                        end
                    end
                end
            end
        end
    end

    function events = build_agv_future_events(id, current_t, horizon_t)
        events = struct('start_t', {}, 'end_t', {}, 'from_node', {}, 'to_node', {});
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1) || ~is_moving_state(AGVs(id).status)
            return;
        end
        move_t = max(current_t, AGVs(id).next_event_t);
        prev_node = AGVs(id).pos;
        event_idx = 0;
        for idx = AGVs(id).path_idx:size(AGVs(id).path, 1)
            if move_t > horizon_t
                break;
            end
            event_idx = event_idx + 1;
            arrival_t = move_t + max(1, AGVs(id).step_dur);
            events(event_idx).start_t = move_t;
            events(event_idx).end_t = arrival_t;
            events(event_idx).from_node = prev_node;
            events(event_idx).to_node = AGVs(id).path(idx, 1:2);
            prev_node = AGVs(id).path(idx, 1:2);
            move_t = arrival_t;
        end
    end

    function [is_feasible, conflict_count, best_wait_steps] = evaluate_candidate_path_window(id, candidate_path, current_t, reservations)
        step_time = max(1, AGVs(id).step_dur);
        horizon_t = get_window_horizon_time(current_t);
        best_wait_steps = 0;
        best_conflict = inf;
        is_feasible = false;

        for wait_steps = 0:max_departure_wait_steps
            conflict_count = 0;
            hold_until = min(horizon_t, current_t + wait_steps);
            for tau = current_t:hold_until
                if is_reserved_node(reservations.node, candidate_path(1, :), tau, id)
                    conflict_count = conflict_count + 1;
                end
            end

            prev_pos = candidate_path(1, :);
            node_t = current_t + wait_steps;
            for p_idx = 2:size(candidate_path, 1)
                start_tau = node_t;
                node_t = node_t + step_time;
                node_pos = candidate_path(p_idx, 1:2);
                if start_tau >= horizon_t
                    break;
                end
                check_end = min(node_t, horizon_t);
                % Evaluate the whole traversal interval, not just the arrival
                % instant, so continuous reservations remain collision-safe.
                for tau = (start_tau + 1):check_end
                    if is_reserved_node(reservations.node, node_pos, tau, id)
                        conflict_count = conflict_count + 1;
                    end
                    if is_reserved_edge(reservations.edge, prev_pos, node_pos, tau, id)
                        conflict_count = conflict_count + 1;
                    end
                end
                prev_pos = node_pos;
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
        last_window_conflict = struct('self_id', id, 'blocker_id', 0, 'type', 'none', 'first_t', -inf, 'node', []);
        reservations = get_reservation_snapshot(current_t);
        horizon_t = get_window_horizon_time(current_t);
        curr_pos = AGVs(id).pos;
        hold_until = min(horizon_t, max(current_t, AGVs(id).next_event_t));
        for tau = current_t:hold_until
            owner = lookup_reserved_node(reservations.node, curr_pos, tau);
            if owner > 0 && owner ~= id
                blocker_id = owner;
                last_window_conflict = struct('self_id', id, 'blocker_id', owner, 'type', 'reserved_node', 'first_t', tau, 'node', curr_pos);
                return;
            end
        end
        future_events = build_agv_future_events(id, current_t, horizon_t);
        for idx = 1:numel(future_events)
            evt = future_events(idx);
            for tau = (evt.start_t + 1):evt.end_t
                owner = lookup_reserved_node(reservations.node, evt.to_node, tau);
                if owner > 0 && owner ~= id
                    blocker_id = owner;
                    last_window_conflict = struct('self_id', id, 'blocker_id', owner, 'type', 'reserved_node', 'first_t', tau, 'node', evt.to_node);
                    return;
                end
                if ~isempty(evt.from_node)
                    owner = lookup_reserved_edge(reservations.edge, evt.from_node, evt.to_node, tau);
                    if owner > 0 && owner ~= id
                        blocker_id = owner;
                        last_window_conflict = struct('self_id', id, 'blocker_id', owner, 'type', 'reserved_edge_swap', 'first_t', tau, 'node', evt.to_node);
                        return;
                    end
                end
            end
        end
    end

    function conflict_records = collect_due_conflicts_batch(due_ids, current_t, tasks_info)
        conflict_records = struct('self_id', {}, 'blocker_id', {}, 'classified_type', {}, 'winner_id', {}, ...
            'loser_id', {}, 'priority_self', {}, 'priority_blocker', {}, 'window_type', {}, ...
            'first_conflict_t', {}, 'conflict_node', {});
        pair_seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');

        for idx = 1:numel(due_ids)
            id = due_ids(idx);
            if ~is_moving_state(AGVs(id).status)
                continue;
            end

            window_type = 'none';
            first_conflict_t = current_t;
            conflict_info = [];

            blocker_id = detect_runtime_blocker_due(id, current_t);
            if blocker_id > 0
                window_type = ['runtime_' last_runtime_conflict.reason];
                first_conflict_t = current_t;
            else
                blocker_id = detect_future_window_conflict(id, current_t);
                if blocker_id > 0
                    conflict_info = classify_conflict_info(id, blocker_id, current_t);
                    if should_handle_window_conflict_now(id, current_t, conflict_info)
                        window_type = last_window_conflict.type;
                        first_conflict_t = last_window_conflict.first_t;
                    else
                        blocker_id = 0;
                        conflict_info = [];
                    end
                end
            end
            if blocker_id <= 0
                continue;
            end

            pair = sort([id, blocker_id]);
            pair_key = sprintf('%d_%d_%d', round(current_t), pair(1), pair(2));
            if isKey(pair_seen, pair_key)
                continue;
            end
            pair_seen(pair_key) = true;

            if isempty(conflict_info)
                conflict_info = classify_conflict_info(id, blocker_id, current_t);
            end
            P_self = calculate_ahp_priority(AGVs(id), tasks_info, current_t);
            P_blocker = calculate_ahp_priority(AGVs(blocker_id), tasks_info, current_t);
            should_self_yield = (P_self < P_blocker) || (P_self == P_blocker && id > blocker_id);
            if should_self_yield
                loser_id = id;
                winner_id = blocker_id;
            else
                loser_id = blocker_id;
                winner_id = id;
            end

            % For occupied-node and rear-end conflicts, the actor attempting
            % to enter the held node/segment is always the yielding side.
            if strcmp(conflict_info.name, 'Occupied node') || strcmp(conflict_info.name, 'Rear-end')
                loser_id = id;
                winner_id = blocker_id;
            elseif any(strcmp(conflict_info.name, {'Head-on swap', 'Head-on meet'}))
                [loser_id, winner_id] = select_headon_retreat_vehicle(id, blocker_id, current_t, P_self, P_blocker);
            end

            conflict_records(end + 1) = struct( ... %#ok<AGROW>
                'self_id', id, ...
                'blocker_id', blocker_id, ...
                'classified_type', conflict_info.name, ...
                'winner_id', winner_id, ...
                'loser_id', loser_id, ...
                'priority_self', P_self, ...
                'priority_blocker', P_blocker, ...
                'window_type', window_type, ...
                'first_conflict_t', first_conflict_t, ...
                'conflict_node', conflict_info.conflict_node);
        end
    end

    function blocker_id = detect_runtime_blocker_due(id, event_t)
        blocker_id = 0;
        last_runtime_conflict = struct('self_id', id, 'blocker_id', 0, 'reason', 'none', 'event_t', event_t, 'node', []);
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
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
                blocker_id = other;
                last_runtime_conflict = struct('self_id', id, 'blocker_id', other, 'reason', 'same_next_node', 'event_t', event_t, 'node', [nr, nc]);
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2) && ...
                    other_next(1) == curr_pos(1) && other_next(2) == curr_pos(2)
                blocker_id = other;
                last_runtime_conflict = struct('self_id', id, 'blocker_id', other, 'reason', 'edge_swap', 'event_t', event_t, 'node', [nr, nc]);
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2)
                blocker_id = other;
                last_runtime_conflict = struct('self_id', id, 'blocker_id', other, 'reason', 'occupied_node', 'event_t', event_t, 'node', [nr, nc]);
                return;
            end
        end
    end

    function conflict = classify_conflict_info(id_self, id_blocker, event_t)
        pos_self = AGVs(id_self).pos;
        target_self = AGVs(id_self).path(AGVs(id_self).path_idx, 1:2);
        pos_blocker = AGVs(id_blocker).pos;
        other_next = get_planned_next_cell(id_blocker);

        conflict = struct('name', 'Node contention', 'conflict_node', target_self, ...
            'conflict_t', event_t, 'wait_node', []);

        if last_runtime_conflict.self_id == id_self && ...
                last_runtime_conflict.blocker_id == id_blocker && ...
                last_runtime_conflict.event_t == event_t
            switch last_runtime_conflict.reason
                case 'same_next_node'
                    conflict.name = 'Node contention';
                    conflict.conflict_node = last_runtime_conflict.node;
                    conflict.conflict_t = event_t;
                    conflict.wait_node = get_previous_path_node(id_self, conflict.conflict_node);
                    return;
                case 'edge_swap'
                    conflict.name = 'Head-on swap';
                    conflict.conflict_node = last_runtime_conflict.node;
                    conflict.conflict_t = event_t;
                    return;
                case 'occupied_node'
                    conflict.name = 'Occupied node';
                    conflict.conflict_node = last_runtime_conflict.node;
                    conflict.conflict_t = event_t;
                    return;
            end
        end

        if last_window_conflict.self_id == id_self && last_window_conflict.blocker_id == id_blocker
            % Force fallback classification to inherit the real future
            % conflict time/node from the window detector so wait/clearance
            % timing is based on the true projected conflict, not "now".
            conflict.conflict_t = last_window_conflict.first_t;
            if isfield(last_window_conflict, 'node') && ~isempty(last_window_conflict.node)
                conflict.conflict_node = last_window_conflict.node;
                conflict.wait_node = get_previous_path_node(id_self, conflict.conflict_node);
            end
            if strcmp(last_window_conflict.type, 'reserved_edge_swap')
                conflict.name = 'Head-on swap';
                conflict.conflict_node = target_self;
                conflict.conflict_t = last_window_conflict.first_t;
                return;
            elseif strcmp(last_window_conflict.type, 'reserved_node') && last_window_conflict.first_t >= event_t
                self_evt = find_future_event_at_t(build_agv_future_events(id_self, event_t, last_window_conflict.first_t), last_window_conflict.first_t);
                blocker_evt = find_future_event_at_t(build_agv_future_events(id_blocker, event_t, last_window_conflict.first_t), last_window_conflict.first_t);
                if ~isempty(self_evt)
                    if isempty(blocker_evt) || ...
                            (AGVs(id_blocker).next_event_t > last_window_conflict.first_t) || ...
                            ~is_moving_state(AGVs(id_blocker).status)
                        if isequal(self_evt.to_node, AGVs(id_blocker).pos)
                            self_dir = get_future_motion_direction(id_self, event_t, last_window_conflict.first_t);
                            blocker_dir = get_future_motion_direction(id_blocker, event_t, last_window_conflict.first_t);
                            if ~isempty(self_dir) && ~isempty(blocker_dir) && dot(self_dir, blocker_dir) > 0 && ...
                                    AGVs(id_self).step_dur < AGVs(id_blocker).step_dur
                                conflict.name = 'Rear-end';
                                conflict.conflict_node = AGVs(id_blocker).pos;
                                conflict.conflict_t = last_window_conflict.first_t;
                            else
                                conflict.name = 'Occupied node';
                                conflict.conflict_node = AGVs(id_blocker).pos;
                                conflict.conflict_t = last_window_conflict.first_t;
                            end
                            return;
                        end
                    end

                    if ~isempty(blocker_evt) && ~isempty(self_evt.from_node) && ~isempty(blocker_evt.from_node)
                        dir_self = self_evt.to_node - self_evt.from_node;
                        dir_blocker = blocker_evt.to_node - blocker_evt.from_node;
                        if dot(dir_self, dir_blocker) > 0 && ...
                                isequal(self_evt.to_node, blocker_evt.from_node) && ...
                                AGVs(id_self).step_dur < AGVs(id_blocker).step_dur
                            conflict.name = 'Rear-end';
                            conflict.conflict_node = self_evt.to_node;
                            conflict.conflict_t = last_window_conflict.first_t;
                            return;
                        end
                    end

                    if ~isempty(blocker_evt) && isequal(self_evt.to_node, blocker_evt.to_node)
                        conflict.conflict_node = self_evt.to_node;
                        conflict.conflict_t = last_window_conflict.first_t;
                        conflict.wait_node = get_previous_path_node(id_self, self_evt.to_node);
                        if ~isempty(self_evt.from_node) && ~isempty(blocker_evt.from_node)
                            dir_self = self_evt.to_node - self_evt.from_node;
                            dir_blocker = blocker_evt.to_node - blocker_evt.from_node;
                            if dot(dir_self, dir_blocker) < 0
                                conflict.name = 'Head-on meet';
                                return;
                            end
                        end
                        conflict.name = 'Node contention';
                        return;
                    end
                end
            end
        end

        if isequal(target_self, pos_blocker) && isequal(other_next, pos_self)
            conflict.name = 'Head-on swap';
            conflict.conflict_node = target_self;
            return;
        end

        if isequal(target_self, pos_blocker)
            conflict.conflict_node = pos_blocker;
            if AGVs(id_blocker).next_event_t > event_t || ~is_moving_state(AGVs(id_blocker).status)
                conflict.name = 'Occupied node';
            else
                conflict.name = 'Rear-end';
            end
            return;
        end

        if isequal(target_self, other_next)
            conflict.name = 'Node contention';
            conflict.conflict_node = target_self;
            conflict.conflict_t = estimate_conflict_time(id_self, target_self, event_t);
            conflict.wait_node = get_previous_path_node(id_self, target_self);
        end
    end

    function evt = find_future_event_at_t(events, target_t)
        evt = [];
        for idx = 1:numel(events)
            if target_t > events(idx).start_t && target_t <= events(idx).end_t
                evt = events(idx);
                return;
            end
        end
    end

    function dir = get_future_motion_direction(id, current_t, target_t)
        dir = [];
        evt = find_future_event_at_t(build_agv_future_events(id, current_t, target_t), target_t);
        if isempty(evt) || isempty(evt.from_node)
            return;
        end
        dir = evt.to_node - evt.from_node;
    end

    function conflict_t = estimate_conflict_time(id, target_node, current_t)
        conflict_t = current_t;
        future_events = build_agv_future_events(id, current_t, get_window_horizon_time(current_t));
        for idx = 1:numel(future_events)
            if isequal(future_events(idx).to_node, target_node)
                conflict_t = future_events(idx).end_t;
                return;
            end
        end
    end

    function prev_node = get_previous_path_node(id, conflict_node)
        prev_node = AGVs(id).pos;
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            return;
        end
        prev_candidate = AGVs(id).pos;
        for idx = AGVs(id).path_idx:size(AGVs(id).path, 1)
            node = AGVs(id).path(idx, 1:2);
            if isequal(node, conflict_node)
                prev_node = prev_candidate;
                return;
            end
            prev_candidate = node;
        end
    end

    function success = apply_wait_then_replan_strategy(loser_id, winner_id, conflict_info, event_t)
        success = false;
        wait_node = conflict_info.wait_node;
        if isempty(wait_node)
            wait_node = AGVs(loser_id).pos;
        end

        % Do not allow the retreat node to sit on the winner's imminent
        % route; otherwise two AGVs can livelock by repeatedly stepping into
        % each other's next corridor cell ("corridor dance").
        winner_future_path = [];
        if ~isempty(AGVs(winner_id).path) && AGVs(winner_id).path_idx <= size(AGVs(winner_id).path, 1)
            winner_future_path = AGVs(winner_id).path(AGVs(winner_id).path_idx:end, 1:2);
        end
        if ismember(wait_node, winner_future_path, 'rows') || isequal(wait_node, AGVs(winner_id).pos)
            conflict_log('AGV%d action=wait_then_replan wait_node=%s blocks winner AGV%d -> safe_harbor', ...
                loser_id, node_str(wait_node), winner_id);
            success = apply_safe_harbor_strategy(loser_id, winner_id, event_t, conflict_info.conflict_t + max(1, AGVs(winner_id).step_dur));
            return;
        end

        % Allow waiting on ordinary corridor-adjacent cells as long as the
        % chosen wait node does not block the winner's future path. This
        % produces more natural "drive to the stop line, then wait"
        % behaviour instead of over-escalating to a distant safe harbor.

        % Preserve the original task context when a waiting/yielding AGV is
        % reassigned again, so temporary states do not overwrite the real
        % resume state and target.
        if ismember(AGVs(loser_id).status, {'Waiting_Clearance', 'Yielding'}) && ~isempty(AGVs(loser_id).wait_resume_status)
            original_target = AGVs(loser_id).wait_resume_target;
            resume_st = AGVs(loser_id).wait_resume_status;
        else
            original_target = AGVs(loser_id).target_node;
            resume_st = AGVs(loser_id).status;
        end

        [repeat_count, should_reroute] = record_wait_pattern(loser_id, winner_id, wait_node, original_target, event_t);
        if should_reroute && ~isempty(original_target)
            conflict_log('AGV%d action=wait_then_replan repeat_wait=%d blocker=AGV%d wait_node=%s resume_target=%s -> reroute_fallback', ...
                loser_id, repeat_count, winner_id, node_str(wait_node), node_str(original_target));
            return;
        end

        if ~isequal(AGVs(loser_id).pos, wait_node)
            [prefix_path, prefix_cost] = astar_planner_turn3(get_dynamic_eval_map(loser_id, wait_node), AGVs(loser_id).pos, wait_node, ...
                AGVs(loser_id).payload_weight, [], AGVs(loser_id).type);
            if isempty(prefix_path) || ~isfinite(prefix_cost)
                return;
            end
            assign_planned_path(loser_id, prefix_path, wait_node);
        else
            AGVs(loser_id).path = wait_node;
            AGVs(loser_id).path_idx = 2;
            AGVs(loser_id).target_node = wait_node;
            reservation_dirty = true;
        end

        AGVs(loser_id).yield_resume_status = resume_st;
        AGVs(loser_id).wait_resume_status = resume_st;
        AGVs(loser_id).wait_resume_target = original_target;
        AGVs(loser_id).wait_resume_area = [1, 1];
        AGVs(loser_id).wait_resume_mode = 'task';
        AGVs(loser_id).reservation_hold_node = wait_node;
        AGVs(loser_id).reservation_hold_until = conflict_info.conflict_t + max(1, AGVs(winner_id).step_dur);
        AGVs(loser_id).resume_after_wait = ~isempty(original_target);
        AGVs(loser_id).wait_blocker_id = winner_id;
        AGVs(loser_id).wait_start_t = event_t;
        AGVs(loser_id).clearance_retry_count = 0;
        conflict_log('AGV%d action=wait_then_replan wait_node=%s hold_until=%g resume_target=%s blocker=AGV%d', ...
            loser_id, node_str(wait_node), AGVs(loser_id).reservation_hold_until, node_str(original_target), winner_id);

        if isequal(AGVs(loser_id).pos, wait_node)
            transition_to(loser_id, 'Waiting_Clearance');
            schedule_in(loser_id, event_t, max(1, AGVs(loser_id).reservation_hold_until - event_t));
        else
            transition_to(loser_id, 'Yielding');
            schedule_in(loser_id, event_t, AGVs(loser_id).step_dur);
        end
        success = true;
    end

    function success = plan_bypass_path(id, blocker_id, event_t)
        success = false;
        curr_pos = AGVs(id).pos;
        blocker_pos = AGVs(blocker_id).pos;
        next_blocker = get_planned_next_cell(blocker_id);
        blocker_dir = next_blocker - blocker_pos;
        if isequal(blocker_dir, [0, 0])
            blocker_dir = blocker_pos - curr_pos;
        end

        lateral_dirs = [0 1; 0 -1; 1 0; -1 0];
        if abs(blocker_dir(1)) >= abs(blocker_dir(2))
            lateral_dirs = [0 1; 0 -1; 1 0; -1 0];
        else
            lateral_dirs = [1 0; -1 0; 0 1; 0 -1];
        end

        candidate_waypoints = [];
        for k = 1:size(lateral_dirs, 1)
            side = blocker_pos + lateral_dirs(k, :);
            ahead = side + blocker_dir;
            candidate_waypoints = [candidate_waypoints; side; ahead]; %#ok<AGROW>
        end

        [~, uidx] = unique(candidate_waypoints, 'rows', 'stable');
        candidate_waypoints = candidate_waypoints(uidx, :);
        best_path = [];
        best_cost = inf;
        for k = 1:size(candidate_waypoints, 1)
            waypoint = candidate_waypoints(k, :);
            if ~is_cell_navigable(waypoint) || isequal(waypoint, blocker_pos)
                continue;
            end
            [p1, c1] = astar_planner_turn3(get_dynamic_eval_map(id, waypoint), curr_pos, waypoint, ...
                AGVs(id).payload_weight, [], AGVs(id).type);
            if isempty(p1) || ~isfinite(c1)
                continue;
            end
            if isempty(AGVs(id).target_node)
                candidate_path = p1;
                total_cost = c1;
            else
                [p2, c2] = astar_planner_turn3(get_dynamic_eval_map(id, AGVs(id).target_node), waypoint, AGVs(id).target_node, ...
                    AGVs(id).payload_weight, [], AGVs(id).type);
                if isempty(p2) || ~isfinite(c2)
                    continue;
                end
                candidate_path = [p1; p2(2:end, :)];
                total_cost = c1 + c2;
            end
            if total_cost < best_cost
                best_cost = total_cost;
                best_path = candidate_path;
            end
        end

        if ~isempty(best_path)
            assign_planned_path(id, best_path, AGVs(id).target_node);
            % Do not overwrite the original task context if this AGV is
            % already executing a temporary waiting/yielding maneuver.
            if ~ismember(AGVs(id).status, {'Waiting_Clearance', 'Yielding'})
                AGVs(id).yield_resume_status = AGVs(id).status;
                AGVs(id).wait_resume_status = AGVs(id).status;
                AGVs(id).wait_resume_target = AGVs(id).target_node;
            end
            conflict_log('AGV%d action=plan_bypass_path blocker=AGV%d success path_to=%s', id, blocker_id, node_str(AGVs(id).target_node));
            success = true;
        end
    end

    function success = plan_rear_end_escape(id, blocker_id, ~)
        success = false;
        original_target = AGVs(id).target_node;
        if isempty(original_target)
            return;
        end

        evalMap = get_dynamic_eval_map(id, original_target);
        blocker_curr = AGVs(blocker_id).pos;
        blocker_next = get_planned_next_cell(blocker_id);

        if ~(blocker_curr(1) == AGVs(id).pos(1) && blocker_curr(2) == AGVs(id).pos(2)) && ...
                ~(blocker_curr(1) == original_target(1) && blocker_curr(2) == original_target(2))
            evalMap(blocker_curr(1), blocker_curr(2)) = 1;
        end
        if ~(blocker_next(1) == AGVs(id).pos(1) && blocker_next(2) == AGVs(id).pos(2)) && ...
                ~(blocker_next(1) == original_target(1) && blocker_next(2) == original_target(2))
            evalMap(blocker_next(1), blocker_next(2)) = 1;
        end

        if AGVs(id).type == 2
            current_costmap = costmap_type2;
        else
            current_costmap = costmap_type1;
        end

        [escape_path, escape_cost] = astar_planner_turn3(evalMap, AGVs(id).pos, original_target, ...
            AGVs(id).payload_weight, current_costmap, AGVs(id).type);
        if isempty(escape_path) || ~isfinite(escape_cost)
            return;
        end

        assign_planned_path(id, escape_path, original_target);
        success = true;
    end

    function [retreat_id, hold_id] = select_headon_retreat_vehicle(id_a, id_b, event_t, priority_a, priority_b)
        score_a = estimate_safe_harbor_retreat_score(id_a, id_b, event_t);
        score_b = estimate_safe_harbor_retreat_score(id_b, id_a, event_t);
        if isfinite(score_a) && isfinite(score_b)
            if score_a < score_b - 1e-9
                retreat_id = id_a;
                hold_id = id_b;
                return;
            elseif score_b < score_a - 1e-9
                retreat_id = id_b;
                hold_id = id_a;
                return;
            end
        elseif isfinite(score_a)
            retreat_id = id_a;
            hold_id = id_b;
            return;
        elseif isfinite(score_b)
            retreat_id = id_b;
            hold_id = id_a;
            return;
        end

        if (priority_a < priority_b) || (priority_a == priority_b && id_a > id_b)
            retreat_id = id_a;
            hold_id = id_b;
        else
            retreat_id = id_b;
            hold_id = id_a;
        end
    end

    function score = estimate_safe_harbor_retreat_score(id, blocker_id, event_t)
        [harbor_node, harbor_path, harbor_cost] = find_best_safe_harbor(id, blocker_id, event_t);
        if isempty(harbor_node) || isempty(harbor_path) || ~isfinite(harbor_cost)
            score = inf;
            return;
        end
        blocker_pos = AGVs(blocker_id).pos;
        score = harbor_cost + 0.25 * max(0, 4 - manhattan_dist(harbor_node, blocker_pos));
    end

    function success = apply_safe_harbor_strategy(id, blocker_id, event_t, hold_until)
        success = false;
        [harbor_node, harbor_path] = find_best_safe_harbor(id, blocker_id, event_t);
        if isempty(harbor_node)
            conflict_log('AGV%d action=safe_harbor failed blocker=AGV%d', id, blocker_id);
            return;
        end

        % Preserve the original task context across nested temporary states.
        if ismember(AGVs(id).status, {'Waiting_Clearance', 'Yielding'}) && ~isempty(AGVs(id).wait_resume_status)
            resume_status = AGVs(id).wait_resume_status;
            resume_target = AGVs(id).wait_resume_target;
        else
            resume_status = AGVs(id).status;
            resume_target = AGVs(id).target_node;
        end

        [repeat_count, should_reroute] = record_wait_pattern(id, blocker_id, harbor_node, resume_target, event_t);
        if should_reroute && ~isempty(resume_target)
            conflict_log('AGV%d action=safe_harbor repeat_wait=%d blocker=AGV%d harbor=%s resume_target=%s -> reroute_fallback', ...
                id, repeat_count, blocker_id, node_str(harbor_node), node_str(resume_target));
            return;
        end
        AGVs(id).yield_resume_status = resume_status;
        AGVs(id).wait_resume_status = resume_status;
        AGVs(id).wait_resume_target = resume_target;
        AGVs(id).wait_resume_area = [1, 1];
        AGVs(id).wait_resume_mode = 'task';
        AGVs(id).reservation_hold_node = harbor_node;
        AGVs(id).reservation_hold_until = max(event_t + max(1, AGVs(id).step_dur), hold_until);
        AGVs(id).resume_after_wait = ~isempty(resume_target);
        AGVs(id).wait_blocker_id = blocker_id;
        AGVs(id).wait_start_t = event_t;
        AGVs(id).clearance_retry_count = 0;
        conflict_log('AGV%d action=safe_harbor blocker=AGV%d harbor=%s hold_until=%g resume_target=%s', ...
            id, blocker_id, node_str(harbor_node), AGVs(id).reservation_hold_until, node_str(resume_target));

        if isequal(AGVs(id).pos, harbor_node)
            transition_to(id, 'Waiting_Clearance');
            schedule_in(id, event_t, max(1, AGVs(id).reservation_hold_until - event_t));
        else
            assign_planned_path(id, harbor_path, harbor_node);
            transition_to(id, 'Yielding');
            schedule_in(id, event_t, AGVs(id).step_dur);
        end
        success = true;
    end

    function [best_node, best_path, best_cost] = find_best_safe_harbor(id, blocker_id, event_t)
        best_node = [];
        best_path = [];
        best_cost = inf;
        if isempty(safe_harbor_nodes)
            return;
        end

        % Search only the closest harbors first; safe harbor is a local
        % retreat action, and exhaustive full-map A* over thousands of
        % candidates causes severe performance avalanches.
        curr_pos = AGVs(id).pos;
        dists = abs(safe_harbor_nodes(:, 1) - curr_pos(1)) + abs(safe_harbor_nodes(:, 2) - curr_pos(2));
        [~, sorted_idx] = sort(dists);
        max_checks = min(15, size(safe_harbor_nodes, 1));

        blocker_pos = [];
        blocker_future_path = [];
        if blocker_id >= 1 && blocker_id <= num_agvs
            blocker_pos = AGVs(blocker_id).pos;
            if ~isempty(AGVs(blocker_id).path) && AGVs(blocker_id).path_idx <= size(AGVs(blocker_id).path, 1)
                blocker_future_path = AGVs(blocker_id).path(AGVs(blocker_id).path_idx:end, 1:2);
            end
        end
        reservations = get_reservation_snapshot(event_t);
        if AGVs(id).type == 2
            current_costmap = costmap_type2;
        else
            current_costmap = costmap_type1;
        end

        for i = 1:max_checks
            candidate = safe_harbor_nodes(sorted_idx(i), :);
            if isequal(candidate, AGVs(id).target_node)
                continue;
            end
            if ~isempty(blocker_pos) && manhattan_dist(candidate, blocker_pos) < 2
                continue;
            end
            if ~isempty(blocker_future_path) && ismember(candidate, blocker_future_path, 'rows')
                continue;
            end
            if is_harbor_reserved(candidate, id, event_t, reservations)
                continue;
            end

            evalMap = get_dynamic_eval_map(id, candidate);
            if ~isempty(blocker_pos) && ~(blocker_pos(1) == candidate(1) && blocker_pos(2) == candidate(2))
                evalMap(blocker_pos(1), blocker_pos(2)) = 1;
            end
            [candidate_path, candidate_cost] = astar_planner_turn3(evalMap, AGVs(id).pos, candidate, ...
                AGVs(id).payload_weight, current_costmap, AGVs(id).type);
            if isempty(candidate_path) || ~isfinite(candidate_cost)
                continue;
            end
            [~, conflict_count, wait_steps] = evaluate_candidate_path_window(id, candidate_path, event_t, reservations);
            score = candidate_cost + 5 * conflict_count + wait_steps;
            if ~isempty(blocker_pos)
                score = score + 0.25 * max(0, 4 - manhattan_dist(candidate, blocker_pos));
            end
            if score < best_cost
                best_cost = score;
                best_node = candidate;
                best_path = candidate_path;
            end
        end
    end

    function evalMap = get_dynamic_eval_map(id, candidate_target)
        evalMap = create_binary_grid_map(mapW, mapH, 0);
        evalMap = evalMap > 0;
        for other = 1:num_agvs
            if other == id
                continue;
            end
            pos_r = AGVs(other).pos(1);
            pos_c = AGVs(other).pos(2);
            if ~(pos_r == candidate_target(1) && pos_c == candidate_target(2))
                evalMap(pos_r, pos_c) = 1;
            end
        end
    end

    function tf = is_cell_navigable(node)
        tf = node(1) >= 1 && node(1) <= mapH && node(2) >= 1 && node(2) <= mapW;
        if ~tf
            return;
        end
        baseMap = create_binary_grid_map(mapW, mapH, 0);
        tf = baseMap(node(1), node(2)) == 0;
    end

    function nodes = build_safe_harbor_nodes()
        baseMap = create_binary_grid_map(mapW, mapH, 0);
        nodes = zeros(0, 2);
        for r = 2:(mapH - 1)
            for c = 2:(mapW - 1)
                if baseMap(r, c) ~= 0
                    continue;
                end
                degree = free_neighbor_degree([r, c], baseMap);
                if degree >= 3
                    nodes(end + 1, :) = [r, c]; %#ok<AGROW>
                end
            end
        end
    end

    function tf = is_safe_wait_node(node)
        tf = false;
        if isempty(node) || ~is_cell_navigable(node)
            return;
        end
        if isempty(safe_harbor_nodes)
            return;
        end
        tf = ismember(node, safe_harbor_nodes, 'rows');
    end

    function degree = free_neighbor_degree(node, baseMap)
        dirs = [-1 0; 1 0; 0 -1; 0 1];
        degree = 0;
        for d = 1:size(dirs, 1)
            nbr = node + dirs(d, :);
            if nbr(1) >= 1 && nbr(1) <= mapH && nbr(2) >= 1 && nbr(2) <= mapW && baseMap(nbr(1), nbr(2)) == 0
                degree = degree + 1;
            end
        end
    end

    function tf = is_harbor_reserved(node, owner_id, event_t, reservations)
        tf = false;
        for tau = event_t:get_window_horizon_time(event_t)
            if is_reserved_node(reservations.node, node, tau, owner_id)
                tf = true;
                return;
            end
        end
    end

    function d = manhattan_dist(node_a, node_b)
        if isempty(node_a) || isempty(node_b)
            d = inf;
            return;
        end
        d = abs(node_a(1) - node_b(1)) + abs(node_a(2) - node_b(2));
    end

    function horizon_t = get_window_horizon_time(current_t)
        max_step = 1;
        for agv_idx = 1:num_agvs
            max_step = max(max_step, max(1, AGVs(agv_idx).step_dur));
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
        if ~isKey(edge_map, key)
            edge_map(key) = owner_id;
        end
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
        key = sprintf('%d_%d_%d_%d_%d', round(to_pos(1)), round(to_pos(2)), round(from_pos(1)), round(from_pos(2)), round(t));
        if isKey(edge_map, key)
            owner = edge_map(key);
        else
            owner = 0;
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

    function success = plan_yield_path(id, blocker_id, event_t)
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
            if plan_path(id, candidate, [1, 1], 'task', event_t)
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

        % When the event loop temporarily marks this AGV as "in progress",
        % next_event_t may already have been cleared/shifted. Restore a
        % movement-consistent timestamp during future-window probing so the
        % AGV is not misread as permanently occupying its current node.
        temp_next_t = AGVs(id).next_event_t;
        AGVs(id).next_event_t = event_t;
        blocker_id = detect_future_window_conflict(id, event_t);
        AGVs(id).next_event_t = temp_next_t;
        window_conflict_info = [];
        if blocker_id > 0
            window_conflict_info = classify_conflict_info(id, blocker_id, event_t);
        end
        if blocker_id > 0 && should_handle_window_conflict_now(id, event_t, window_conflict_info)
            conflict_log('AGV%d runtime_blocked_by_window blocker=AGV%d type=%s classified=%s first_t=%g pos=%s next=%s status=%s', ...
                id, blocker_id, last_window_conflict.type, window_conflict_info.name, last_window_conflict.first_t, ...
                node_str(AGVs(id).pos), node_str(AGVs(id).path(AGVs(id).path_idx, 1:2)), AGVs(id).status);
            status = -blocker_id;
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
                conflict_log('AGV%d runtime_blocked_by_immediate blocker=AGV%d reason=same_next_node self_next=%s other_next=%s', ...
                    id, other, node_str([nr, nc]), node_str(other_next));
                status = -other;
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2) && ...
                    other_next(1) == curr_pos(1) && other_next(2) == curr_pos(2)
                conflict_log('AGV%d runtime_blocked_by_immediate blocker=AGV%d reason=edge_swap self_next=%s other_curr=%s', ...
                    id, other, node_str([nr, nc]), node_str(other_curr));
                status = -other;
                return;
            end
            if nr == other_curr(1) && nc == other_curr(2)
                conflict_log('AGV%d runtime_blocked_by_immediate blocker=AGV%d reason=occupied_node blocker_pos=%s', ...
                    id, other, node_str(other_curr));
                status = -other;
                return;
            end
        end

        AGVs(id).pos = [nr, nc];
        last_progress_t = event_t;
        AGVs(id).rear_end_retry_count = 0;
        clear_wait_pattern_memory(id);
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
        reservation_dirty = true;

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
            if AGVs(id).resume_after_wait
                transition_to(id, 'Waiting_Clearance');
                schedule_in(id, event_t, max(1, AGVs(id).reservation_hold_until - event_t));
            else
                resume_after_yield(id, event_t);
            end
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
                reset_wait_recovery_state(id);
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
                reset_wait_recovery_state(id);
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        elseif strcmp(resume_status, 'Go_Home')
            % Returning home after yielding uses the same single-cell
            % footprint model as idle parking and charging.
            area_sz = [1, 1];
            if plan_path(id, AGVs(id).home_pos, area_sz)
                transition_to(id, 'Go_Home');
                AGVs(id).yield_resume_status = '';
                reset_wait_recovery_state(id);
                schedule_in(id, event_t, AGVs(id).step_dur);
            else
                schedule_in(id, event_t, 1);
            end
        elseif strcmp(resume_status, 'Going_Charge')
            AGVs(id).yield_resume_status = '';
            reset_wait_recovery_state(id);
            plan_to_charge(id, event_t);
        else
            transition_to(id, resume_status);
            AGVs(id).yield_resume_status = '';
            reset_wait_recovery_state(id);
            schedule_now(id, event_t);
        end
    end

    function reset_wait_recovery_state(id)
        AGVs(id).resume_after_wait = false;
        AGVs(id).wait_resume_status = '';
        AGVs(id).wait_resume_target = [];
        AGVs(id).wait_resume_area = [1, 1];
        AGVs(id).wait_resume_mode = 'task';
        AGVs(id).reservation_hold_node = [];
        AGVs(id).reservation_hold_until = -inf;
        AGVs(id).wait_blocker_id = 0;
        AGVs(id).wait_start_t = -inf;
        AGVs(id).clearance_retry_count = 0;
    end

    function apply_wait_only_strategy(id, blocker_id, event_t, reason_tag)
        if nargin < 4
            reason_tag = 'wait_only';
        end
        conflict_log('AGV%d action=wait_only_strategy reason=%s at %s blocker=AGV%d', ...
            id, reason_tag, node_str(AGVs(id).pos), blocker_id);
        if ismember(AGVs(id).status, {'Waiting_Clearance', 'Yielding'}) && ~isempty(AGVs(id).wait_resume_status)
            resume_status = AGVs(id).wait_resume_status;
            resume_target = AGVs(id).wait_resume_target;
        else
            resume_status = AGVs(id).status;
            resume_target = AGVs(id).target_node;
        end
        AGVs(id).yield_resume_status = resume_status;
        AGVs(id).wait_resume_status = resume_status;
        AGVs(id).wait_resume_target = resume_target;
        AGVs(id).wait_resume_area = [1, 1];
        AGVs(id).wait_resume_mode = 'task';
        AGVs(id).resume_after_wait = ~isempty(resume_target);
        AGVs(id).reservation_hold_node = AGVs(id).pos;
        AGVs(id).reservation_hold_until = event_t + max(1, AGVs(id).step_dur);
        AGVs(id).wait_blocker_id = blocker_id;
        AGVs(id).wait_start_t = event_t;
        AGVs(id).clearance_retry_count = 0;
        transition_to(id, 'Waiting_Clearance');
        schedule_in(id, event_t, max(1, AGVs(id).step_dur));
    end

    function tf = is_window_conflict_imminent(id, current_t)
        tf = last_window_conflict.self_id == id && ...
            isfinite(last_window_conflict.first_t) && ...
            last_window_conflict.first_t <= current_t + max(imminent_window_buffer_steps, AGVs(id).step_dur);
    end

    function tf = should_handle_window_conflict_now(id, current_t, conflict_info)
        if isempty(conflict_info)
            tf = false;
            return;
        end
        % Node contention keeps the near-distance guard to avoid aggressive
        % early braking, while occupied/head-on/rear-end conflicts should
        % trigger as soon as they enter the sliding reservation window.
        tf = ~strcmp(conflict_info.name, 'Node contention') || is_window_conflict_imminent(id, current_t);
    end

    function [repeat_count, should_reroute] = record_wait_pattern(id, blocker_id, hold_node, resume_target, event_t)
        signature = sprintf('B%d|H%s|R%s', blocker_id, mat2str(reshape(hold_node, 1, [])), mat2str(reshape(resume_target, 1, [])));
        if strcmp(AGVs(id).last_wait_signature, signature) && ...
                isfinite(AGVs(id).last_wait_assign_t) && ...
                event_t <= AGVs(id).last_wait_assign_t + repeat_wait_memory_horizon
            AGVs(id).repeat_wait_count = AGVs(id).repeat_wait_count + 1;
        else
            AGVs(id).repeat_wait_count = 1;
        end
        AGVs(id).last_wait_signature = signature;
        AGVs(id).last_wait_assign_t = event_t;
        repeat_count = AGVs(id).repeat_wait_count;
        should_reroute = repeat_count >= repeat_wait_replan_threshold;
    end

    function clear_wait_pattern_memory(id)
        AGVs(id).last_wait_signature = '';
        AGVs(id).last_wait_assign_t = -inf;
        AGVs(id).repeat_wait_count = 0;
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


