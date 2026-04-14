clear;
clc;
close all;

cfg.rows = 20;
cfg.cols = 20;
cfg.obstacle_rate = 0.10;
cfg.random_seed = 20260410;
cfg.event_t = 10;
cfg.reservation_horizon_steps = 6;
cfg.show_cell_ids = true;
cfg.save_figures = true;
cfg.rebuild_map = false;

cell_id_map = build_cell_id_map(cfg.rows, cfg.cols);
cases = build_default_cases_by_id(cfg.event_t);

forced_free_cells = collect_forced_free_cells(cases, cell_id_map);
[grid_map, cell_id_map, map_file_path, map_source] = load_or_create_smallmap(cfg, cell_id_map, forced_free_cells);

timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
base_dir = fileparts(mfilename('fullpath'));
output_dir = fullfile(base_dir, 'experiment_outputs', ['conflict_validation_' timestamp]);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

save(fullfile(output_dir, 'smallmap_case_data.mat'), 'cfg', 'grid_map', 'cell_id_map', 'cases');
writematrix(grid_map, fullfile(output_dir, 'smallmap_obstacle_map.csv'));
writematrix(cell_id_map, fullfile(output_dir, 'smallmap_cell_ids.csv'));

plot_numbered_map(grid_map, cell_id_map, cfg.show_cell_ids, ...
    fullfile(output_dir, 'smallmap_with_cell_ids.png'));

summary_rows = cell(numel(cases) + 1, 20);
summary_rows(1, :) = {'case_name', 'expected_type', 'runtime_detected', 'runtime_blocker', ...
    'window_detected', 'window_blocker', 'window_type', 'window_time', ...
    'classified_type', 'winner', 'loser', 'priority_a', 'priority_b', ...
    'step_durs', 'strategy', 'strategy_desc', 'priority_snapshot', 'pairwise_priority', ...
    'first_decision_t', 'latest_decision_t'};
timeline_rows = cell(1, 8);
timeline_rows(1, :) = {'case_name', 'agv_id', 'role', 'sim_t', 'cell_id', 'row', 'col', 'state_tag'};
case_results = cell(numel(cases), 1);

fprintf('>> Conflict validation based on run_visualization_loop_event_sm_text\n');
fprintf('>> Output directory: %s\n', output_dir);
fprintf('>> Map source: %s\n', map_source);
fprintf('>> Persistent map file: %s\n', map_file_path);

for case_idx = 1:numel(cases)
    case_cfg = cases(case_idx);
    result = simulate_case_event_driven_smallmap(case_cfg, grid_map, cell_id_map, cfg);
    case_timeline = result.timeline_rows;
    timeline_rows = [timeline_rows; case_timeline]; %#ok<AGROW>
    case_log_path = fullfile(output_dir, sprintf('case_%02d_%s_log.txt', case_idx, case_cfg.name));
    print_conflict_validation_case_log(case_idx, case_cfg, result, case_log_path);
    case_results{case_idx} = struct('case_cfg', case_cfg, 'result', result);

    summary_rows{case_idx + 1, 1} = case_cfg.name;
    summary_rows{case_idx + 1, 2} = case_cfg.expected_type;
    summary_rows{case_idx + 1, 3} = result.runtime_detected;
    summary_rows{case_idx + 1, 4} = result.runtime_blocker;
    summary_rows{case_idx + 1, 5} = result.window_detected;
    summary_rows{case_idx + 1, 6} = result.window_blocker;
    summary_rows{case_idx + 1, 7} = result.window_type;
    summary_rows{case_idx + 1, 8} = result.first_conflict_t;
    summary_rows{case_idx + 1, 9} = result.classified_type;
    summary_rows{case_idx + 1, 10} = result.winner_id;
    summary_rows{case_idx + 1, 11} = result.loser_id;
    summary_rows{case_idx + 1, 12} = result.priority_a;
    summary_rows{case_idx + 1, 13} = result.priority_b;
    summary_rows{case_idx + 1, 14} = sprintf('[%s]', num2str([result.AGVs.step_dur], '%.2f '));
    summary_rows{case_idx + 1, 15} = result.strategy_name;
    summary_rows{case_idx + 1, 16} = result.strategy_desc;
    summary_rows{case_idx + 1, 17} = result.priority_snapshot_str;
    summary_rows{case_idx + 1, 18} = result.priority_pairwise_str;
    summary_rows{case_idx + 1, 19} = result.first_decision_t;
    summary_rows{case_idx + 1, 20} = result.priority_snapshot_t;

    if cfg.save_figures
        case_png = fullfile(output_dir, sprintf('case_%02d_%s.png', case_idx, case_cfg.name));
        plot_case_runtime_visualization(grid_map, cell_id_map, case_cfg, result, case_png);
    end
end

writecell(summary_rows, fullfile(output_dir, 'conflict_validation_summary.csv'));
writecell(timeline_rows, fullfile(output_dir, 'conflict_validation_timelines.csv'));
save(fullfile(output_dir, 'conflict_validation_case_results.mat'), 'cfg', 'grid_map', 'cell_id_map', 'cases', 'case_results', 'summary_rows', 'timeline_rows');
fprintf('\n>> Validation finished.\n');

function cell_id_map = build_cell_id_map(rows, cols)
    cell_id_map = reshape(1:(rows * cols), cols, rows)';
end

function cases = build_default_cases_by_id(event_t)
    cases(1) = struct( ...
        'name', 'node_contention', ...
        'expected_type', 'Node contention', ...
        'agv1', build_agv_case_by_id(211, 391, [231 251 271 291 311 331 351 371 ], 'Moving_Drop', 1, 300, 78, 1, 1, event_t, 1.0), ...
        'agv2', build_agv_case_by_id(306, 315, [307 308 309 310 311 312 313 314], 'Moving_Pick', 1, 0, 62, 1, 8, event_t, 1.0), ...
        'agv3', [], 'agv4', [], 'agv5', [], 'agv6', [], ...
        'agv7', build_agv_case_by_id(342, 372, [343 344 345 346 347 367 368 369 370 371], 'Moving_Drop', 1, 30, 95, 2, 12, event_t, 1.0), ...
        'agv8', [], 'agv9', [], 'agv10', [], 'agv11', []);

    cases(2) = struct( ...
        'name', 'reserved_edge_swap', ...
        'expected_type', 'Head-on swap', ...
        'agv1', [], 'agv2', [], ...
        'agv3', build_agv_case_by_id(243, 251, [244 245 246 247 248 249 250], 'Moving_Drop', 1, 280, 74, 1, 3, event_t, 1.0), ...
        'agv4', build_agv_case_by_id(251, 243, [250 249 248 247 246 245 244], 'Moving_Pick', 1, 0, 69, 1, 4, event_t, 1.0), ...
        'agv5', [], 'agv6', [], 'agv7', [], 'agv8', [], 'agv9', [], 'agv10', [], 'agv11', []);

    cases(3) = struct( ...
        'name', 'occupied_node', ...
        'expected_type', 'Occupied node', ...
        'agv1', [], 'agv2', [], 'agv3', [], 'agv4', [], 'agv5', [], 'agv6', [], 'agv7', [], ...
        'agv8', build_agv_case_by_id(41, 46, [42 43 44 45], 'Moving_Drop', 1, 320, 71, 1, 5, event_t, 1.0), ...
        'agv9', build_agv_case_by_id(43, 44, [43 43 43 43], 'Loading', 1, 67, 55, 2, 6, event_t, 1.0), ...
        'agv10', [], 'agv11', []);

    cases(4) = struct( ...
        'name', 'head_on_meet', ...
        'expected_type', 'Head-on meet', ...
        'agv1', [], 'agv2', [], 'agv3', [], 'agv4', [], ...
        'agv5', build_agv_case_by_id(54, 154, [74 94 114 134], 'Moving_Drop', 1, 350, 80, 2, 5, event_t, 1.0), ...
        'agv6', build_agv_case_by_id(154, 54, [134 114 94 74], 'Moving_Drop', 1, 200, 66, 2, 12, event_t, 1.0), ...
        'agv7', [], 'agv8', [], 'agv9', [], 'agv10', [], 'agv11', []);
    
    cases(5) = struct( ...
        'name', 'rear_end_overtake', ...
        'expected_type', 'Rear-end', ...
        'agv1', [], 'agv2', [], 'agv3', [], 'agv4', [], 'agv5', [], 'agv6', [], 'agv7', [], 'agv8', [], 'agv9', [], ...
        'agv10', build_agv_case_by_id(178, 318, [198 218 238 258 278 298], 'Moving_Drop', 1, 350, 80, 2, 7, event_t, 2.0), ...
        'agv11', build_agv_case_by_id(218, 278, [238 258], 'Moving_Drop', 1, 200, 66, 2, 8, event_t, 1.0));
end

function agv_case = build_agv_case_by_id(start_id, end_id, via_ids, status, load_flag, payload_weight, battery, agv_type, active_task_id, next_event_t, step_dur)
    agv_case = struct();
    agv_case.start_id = start_id;
    agv_case.end_id = end_id;
    agv_case.via_ids = via_ids(:)';
    agv_case.status = status;
    agv_case.load = load_flag;
    agv_case.payload_weight = payload_weight;
    agv_case.battery = battery;
    agv_case.type = agv_type;
    agv_case.active_task_id = active_task_id;
    agv_case.next_event_t = next_event_t;
    agv_case.step_dur = step_dur;
end

function forced_cells = collect_forced_free_cells(cases, cell_id_map)
    forced_ids = [];
    for i = 1:numel(cases)
        fields = fieldnames(cases(i));
        agv_fields = fields(startsWith(fields, 'agv'));
        for j = 1:numel(agv_fields)
            agv_data = cases(i).(agv_fields{j});
            if isempty(agv_data)
                continue;
            end
            forced_ids = [forced_ids, agv_data.start_id, agv_data.via_ids, agv_data.end_id]; %#ok<AGROW>
        end
    end
    forced_ids = unique(forced_ids(:)');
    forced_cells = zeros(numel(forced_ids), 2);
    for i = 1:numel(forced_ids)
        forced_cells(i, :) = rc_from_id(forced_ids(i), cell_id_map);
    end
end

function [grid_map, cell_id_map] = generate_smallmap(rows, cols, obstacle_rate, seed, forced_free_cells)
    rng(seed);
    grid_map = rand(rows, cols) < obstacle_rate;
    if nargin >= 5 && ~isempty(forced_free_cells)
        for i = 1:size(forced_free_cells, 1)
            r = forced_free_cells(i, 1);
            c = forced_free_cells(i, 2);
            if r >= 1 && r <= rows && c >= 1 && c <= cols
                grid_map(r, c) = 0;
            end
        end
    end
end

function [grid_map, cell_id_map, map_file_path, map_source] = load_or_create_smallmap(cfg, cell_id_map, forced_free_cells)
    base_dir = fileparts(mfilename('fullpath'));
    map_file_path = fullfile(base_dir, 'smallmap_fixed_20x20.mat');

    if exist(map_file_path, 'file') && ~cfg.rebuild_map
        map_data = load(map_file_path, 'grid_map', 'cell_id_map');
        grid_map = map_data.grid_map;
        cell_id_map = map_data.cell_id_map;
        grid_map = enforce_forced_free_cells(grid_map, forced_free_cells);
        save(map_file_path, 'grid_map', 'cell_id_map');
        map_source = 'loaded existing fixed map';
        return;
    end

    [grid_map, cell_id_map] = generate_smallmap(cfg.rows, cfg.cols, cfg.obstacle_rate, cfg.random_seed, forced_free_cells);
    save(map_file_path, 'grid_map', 'cell_id_map');
    map_source = 'generated new fixed map';
end

function grid_map = enforce_forced_free_cells(grid_map, forced_free_cells)
    for i = 1:size(forced_free_cells, 1)
        r = forced_free_cells(i, 1);
        c = forced_free_cells(i, 2);
        if r >= 1 && r <= size(grid_map, 1) && c >= 1 && c <= size(grid_map, 2)
            grid_map(r, c) = 0;
        end
    end
end

function [AGVs, task_list] = build_case_agvs(case_cfg, cell_id_map)
    fields = fieldnames(case_cfg);
    agv_fields = fields(startsWith(fields, 'agv'));

    AGVs = [];
    task_list = zeros(0, 4);
    for i = 1:numel(agv_fields)
        agv_data = case_cfg.(agv_fields{i});
        if isempty(agv_data)
            continue;
        end
        display_id = parse_display_id_from_field(agv_fields{i}, i);
        AGVs = [AGVs, init_case_agv(agv_data, cell_id_map, display_id)]; %#ok<AGROW>
        task_list(end + 1, :) = [agv_data.active_task_id, 1, max(1, agv_data.payload_weight), 120]; %#ok<AGROW>
    end
end

function agv = init_case_agv(agv_case, cell_id_map, display_id)
    path_ids = [agv_case.start_id, agv_case.via_ids, agv_case.end_id];
    service_wait_steps = 0;
    for idx = 2:numel(path_ids)
        if path_ids(idx) == path_ids(1)
            service_wait_steps = service_wait_steps + 1;
        else
            break;
        end
    end
    path_rc = rc_path_from_ids(path_ids, cell_id_map);
    agv = struct();
    agv.pos = path_rc(1, :);
    agv.path = path_rc;
    agv.path_idx = 2;
    agv.status = agv_case.status;
    agv.load = agv_case.load;
    agv.payload_weight = agv_case.payload_weight;
    agv.battery = agv_case.battery;
    agv.type = agv_case.type;
    agv.active_task_id = agv_case.active_task_id;
    agv.tasks = agv_case.active_task_id;
    agv.target_node = path_rc(end, :);
    agv.next_event_t = agv_case.next_event_t;
    agv.step_dur = agv_case.step_dur;
    agv.yield_resume_status = '';
    agv.path_ids = path_ids;
    agv.service_wait_steps = service_wait_steps;
    agv.display_id = display_id;
end

function result = simulate_case_event_driven_smallmap(case_cfg, grid_map, cell_id_map, cfg)
    [AGVs, task_list] = build_case_agvs(case_cfg, cell_id_map);
    num_agvs = numel(AGVs);
    max_events = 200;
    event_count = 0;
    current_t = cfg.event_t;

    for id = 1:num_agvs
        AGVs(id).path = normalize_path_four_connected(AGVs(id).path, AGVs(id).payload_weight, AGVs(id).type);
        AGVs(id).path_idx = min(2, size(AGVs(id).path, 1) + 1);
        AGVs(id).target_node = AGVs(id).path(end, 1:2);
        AGVs(id).yield_resume_status = AGVs(id).status;
        AGVs(id).yield_resume_target = [];
        AGVs(id).resume_after_wait = false;
        AGVs(id).wait_resume_status = '';
        AGVs(id).wait_resume_target = [];
        AGVs(id).wait_resume_path = [];
        AGVs(id).wait_node = [];
        AGVs(id).wait_resume_t = inf;
    end

    traces = repmat(struct('cells', [], 'times', [], 'tags', {{}}, 'display_id', []), 1, num_agvs);
    for id = 1:num_agvs
        traces(id).cells = AGVs(id).pos;
        traces(id).times = cfg.event_t;
        traces(id).tags = {'current'};
        traces(id).display_id = AGVs(id).display_id;
    end

    result = struct();
    result.AGVs = AGVs;
    result.runtime_detected = 0;
    result.runtime_blocker = 0;
    result.window_detected = 0;
    result.window_blocker = 0;
    result.window_type = 'none';
    result.first_conflict_t = -1;
    result.classified_type = 'none';
    result.winner_id = 0;
    result.loser_id = 0;
    if numel(AGVs) >= 1
        result.priority_a = calculate_ahp_priority(AGVs(1), task_list, cfg.event_t);
    else
        result.priority_a = NaN;
    end
    if numel(AGVs) >= 2
        result.priority_b = calculate_ahp_priority(AGVs(2), task_list, cfg.event_t);
    else
        result.priority_b = NaN;
    end
    result.strategy_name = 'none';
    result.strategy_desc = '';
    result.yield_goal = [];
    result.priority_snapshot_t = cfg.event_t;
    result.display_ids = arrayfun(@(agv) agv.display_id, AGVs);
    result.priority_snapshot = arrayfun(@(agv) calculate_ahp_priority(agv, task_list, cfg.event_t), AGVs);
    result.priority_snapshot_str = format_priority_snapshot_smallmap(result.priority_snapshot, result.display_ids);
    result.priority_pairwise_str = format_pairwise_priority_smallmap(result.priority_snapshot, 1:numel(AGVs), result.display_ids);
    result.first_decision_t = NaN;
    result.first_priority_snapshot_str = '';
    result.first_priority_pairwise_str = '';
    result.interlock_cycle_nodes = [];
    result.conflict_points = zeros(0, 2);
    result.wait_points = zeros(0, 2);
    result.replan_paths = {};
    result.timeline_rows = {};
    result.debug_logs = {};
    result.conflict_history = struct('detection_t', {}, 'predicted_conflict_t', {}, 'self_id', {}, ...
        'blocker_id', {}, 'conflict_source', {}, 'window_type', {}, 'classified_type', {}, ...
        'winner_id', {}, 'loser_id', {}, 'priority_a', {}, 'priority_b', {}, ...
        'self_status', {}, 'blocker_status', {}, 'self_pos', {}, 'self_next', {}, ...
        'blocker_pos', {}, 'blocker_next', {}, 'conflict_node', {}, 'reason', {}, ...
        'strategy_name', {}, 'strategy_desc', {}, 'yield_goal', {}, 'replanned_path', {});

    while event_count < max_events
        pending = [AGVs.next_event_t];
        finite_pending = pending(isfinite(pending));
        if isempty(finite_pending)
            break;
        end

        current_t = min(finite_pending);

        due_ids = find([AGVs.next_event_t] == current_t);
        if isempty(due_ids)
            break;
        end

        snapshot_AGVs = AGVs;
        for idx = 1:numel(due_ids)
            AGVs(due_ids(idx)).next_event_t = inf;
        end

        conflict_records = collect_due_conflicts_smallmap(snapshot_AGVs, due_ids, current_t, cfg.reservation_horizon_steps, task_list);
        [debug_lines, cycle_nodes, breaker_id, breaker_blocker_id, breaker_debug] = ...
            build_interlock_debug_lines(snapshot_AGVs, conflict_records, current_t, task_list);
        if ~isempty(debug_lines)
            result.debug_logs = [result.debug_logs; debug_lines(:)]; %#ok<AGROW>
        end
        if ~isempty(cycle_nodes)
            result.interlock_cycle_nodes = cycle_nodes;
            result.priority_snapshot_t = current_t;
            result.priority_snapshot = arrayfun(@(agv) calculate_ahp_priority(agv, task_list, current_t), AGVs);
            result.priority_snapshot_str = format_priority_snapshot_smallmap(result.priority_snapshot, result.display_ids);
            result.priority_pairwise_str = format_pairwise_priority_smallmap(result.priority_snapshot, 1:numel(AGVs), result.display_ids);
            result.debug_logs{end + 1, 1} = sprintf('  interlock_breaker[t=%g]: breaker=AGV%d blocker=AGV%d', ...
                current_t, agv_display_id(AGVs, breaker_id), agv_display_id(AGVs, breaker_blocker_id)); %#ok<AGROW>
            result.debug_logs{end + 1, 1} = sprintf('  interlock_breaker_scores[t=%g]: %s', ...
                current_t, breaker_debug); %#ok<AGROW>

            breaker_rec_idx = find([conflict_records.self_id] == breaker_id & [conflict_records.blocker_id] == breaker_blocker_id, 1, 'first');
            if isempty(breaker_rec_idx)
                breaker_rec_idx = find([conflict_records.self_id] == breaker_id, 1, 'first');
            end
            if ~isempty(breaker_rec_idx) && breaker_rec_idx ~= 1
                conflict_records = conflict_records([breaker_rec_idx, 1:breaker_rec_idx-1, breaker_rec_idx+1:end]);
            end
        end
        blocked_ids = zeros(0, 1);
        silent_handled_ids = zeros(0, 1);
        for rec_idx = 1:numel(conflict_records)
            rec = conflict_records(rec_idx);
            if ~isempty(cycle_nodes) && rec.self_id == breaker_id
                [strategy_name, strategy_desc, yield_goal, replanned_path, strategy_info] = ...
                    resolve_interlock_break_strategy_like_event_sm(snapshot_AGVs, grid_map, breaker_id, breaker_blocker_id, ...
                    cycle_nodes, current_t, rec.first_conflict_t);
                result.debug_logs{end + 1, 1} = sprintf('  interlock_break_action[t=%g]: AGV%d -> %s', ...
                    current_t, agv_display_id(snapshot_AGVs, breaker_id), strategy_name); %#ok<AGROW>
                rec.winner_id = breaker_blocker_id;
                rec.loser_id = breaker_id;
            else
                [strategy_name, strategy_desc, yield_goal, replanned_path, strategy_info] = ...
                    resolve_strategy_like_event_sm(snapshot_AGVs, grid_map, rec.loser_id, rec.winner_id, ...
                    rec.classified_type, rec.window_type, current_t, rec.first_conflict_t, rec.window_detected);
            end

            if strcmp(rec.conflict_source, 'runtime')
                result.runtime_detected = 1;
                result.runtime_blocker = rec.blocker_id;
            end
            if rec.window_detected
                result.window_detected = 1;
                result.window_blocker = rec.window_blocker;
                result.window_type = rec.window_type;
                result.first_conflict_t = rec.first_conflict_t;
            end
            if ~isempty(cycle_nodes) && rec.self_id == breaker_id
                result.classified_type = 'Three-way interlock';
            else
                result.classified_type = rec.classified_type;
            end
            result.winner_id = rec.winner_id;
            result.loser_id = rec.loser_id;
            result.priority_a = rec.priority_a;
            result.priority_b = rec.priority_b;
            if isempty(result.interlock_cycle_nodes)
                result.priority_snapshot_t = current_t;
                result.priority_snapshot = arrayfun(@(agv) calculate_ahp_priority(agv, task_list, current_t), AGVs);
                result.priority_snapshot_str = format_priority_snapshot_smallmap(result.priority_snapshot, result.display_ids);
                result.priority_pairwise_str = format_pairwise_priority_smallmap(result.priority_snapshot, 1:numel(AGVs), result.display_ids);
            end
            if isnan(result.first_decision_t)
                result.first_decision_t = current_t;
                result.first_priority_snapshot_str = result.priority_snapshot_str;
                result.first_priority_pairwise_str = result.priority_pairwise_str;
            end
            result.strategy_name = strategy_name;
            result.strategy_desc = strategy_desc;
            result.yield_goal = yield_goal;
            result.conflict_history(end + 1) = build_conflict_log_entry_smallmap( ... %#ok<AGROW>
                snapshot_AGVs, rec, current_t, strategy_name, strategy_desc, yield_goal, replanned_path);

            if isfield(strategy_info, 'conflict_node') && ~isempty(strategy_info.conflict_node)
                result.conflict_points(end + 1, :) = strategy_info.conflict_node; %#ok<AGROW>
            elseif snapshot_AGVs(rec.self_id).path_idx <= size(snapshot_AGVs(rec.self_id).path, 1)
                result.conflict_points(end + 1, :) = snapshot_AGVs(rec.self_id).path(snapshot_AGVs(rec.self_id).path_idx, 1:2); %#ok<AGROW>
            end
            if ~isempty(yield_goal)
                result.wait_points(end + 1, :) = yield_goal; %#ok<AGROW>
            end
            if ~isempty(replanned_path)
                replanned_path = normalize_path_four_connected(replanned_path, snapshot_AGVs(rec.loser_id).payload_weight, snapshot_AGVs(rec.loser_id).type);
                result.replan_paths{end + 1} = struct('agv_id', rec.loser_id, 'path', replanned_path, 'reason', strategy_name); %#ok<AGROW>
            end

            apply_strategy_to_agvs_smallmap(rec.loser_id, rec.winner_id, strategy_name, replanned_path, strategy_info, current_t);
            if strcmp(strategy_name, 'replan_original_target') && isfield(strategy_info, 'immediate_move') && strategy_info.immediate_move
                silent_handled_ids(end + 1, 1) = rec.loser_id; %#ok<AGROW>
            else
                blocked_ids(end + 1, 1) = rec.loser_id; %#ok<AGROW>
            end
        end

        for idx = 1:numel(due_ids)
            id = due_ids(idx);
            event_count = event_count + 1;
            if any(silent_handled_ids == id)
                continue;
            end
            if any(blocked_ids == id)
                append_trace(id, AGVs(id).pos, current_t, 'hold');
                continue;
            end
            if is_moving_state_local(AGVs(id).status)
                post_blocker_id = detect_runtime_blocker_like_event_sm(AGVs, id, current_t);
                if post_blocker_id > 0
                    AGVs(id).next_event_t = current_t + max(1, AGVs(id).step_dur);
                    append_trace(id, AGVs(id).pos, current_t, 'hold');
                    result.debug_logs{end + 1, 1} = sprintf( ...
                        '  post_strategy_block[t=%g]: AGV%d blocked by AGV%d after breaker/strategy application', ...
                        current_t, agv_display_id(AGVs, id), agv_display_id(AGVs, post_blocker_id)); %#ok<AGROW>
                    continue;
                end
                execute_scheduled_move_smallmap(id, current_t);
            else
                handle_waiting_smallmap(id, current_t);
            end
        end

        if all(~isfinite([AGVs.next_event_t]))
            break;
        end
    end

    result.AGVs = AGVs;
    result.timeline_rows = build_runtime_timeline_rows(case_cfg.name, traces, cell_id_map, result.winner_id, result.loser_id);

    function execute_scheduled_move_smallmap(id, event_t)
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            AGVs(id).next_event_t = inf;
            return;
        end

        next_node = AGVs(id).path(AGVs(id).path_idx, 1:2);
        AGVs(id).pos = next_node;
        AGVs(id).path_idx = AGVs(id).path_idx + 1;
        append_trace(id, next_node, display_event_time(event_t, AGVs(id).step_dur), 'executed');

        if AGVs(id).path_idx > size(AGVs(id).path, 1)
            handle_arrival_smallmap(id, event_t);
        else
            AGVs(id).next_event_t = event_t + max(1, AGVs(id).step_dur);
        end
    end

    function handle_waiting_smallmap(id, event_t)
        if strcmp(AGVs(id).status, 'Waiting_Clearance')
            if event_t < AGVs(id).wait_resume_t
                AGVs(id).next_event_t = AGVs(id).wait_resume_t;
                append_trace(id, AGVs(id).pos, display_event_time(event_t, AGVs(id).step_dur), 'wait_then_replan');
                return;
            end

            if ~isempty(AGVs(id).wait_resume_path)
                assign_path_to_agv_smallmap(id, AGVs(id).wait_resume_path, AGVs(id).wait_resume_target);
                AGVs(id).status = AGVs(id).wait_resume_status;
                AGVs(id).resume_after_wait = false;
                AGVs(id).next_event_t = event_t + max(1, AGVs(id).step_dur);
            else
                AGVs(id).next_event_t = event_t + 1;
                append_trace(id, AGVs(id).pos, display_event_time(event_t, AGVs(id).step_dur), 'wait_then_replan');
            end
            return;
        end

        if any(strcmp(AGVs(id).status, {'Loading', 'Unloading'}))
            if AGVs(id).service_wait_steps > 0
                AGVs(id).service_wait_steps = AGVs(id).service_wait_steps - 1;
                AGVs(id).next_event_t = event_t + 1;
                append_trace(id, AGVs(id).pos, display_event_time(event_t, AGVs(id).step_dur), 'hold');
            else
                AGVs(id).status = infer_resume_status_after_service(AGVs(id));
                AGVs(id).next_event_t = event_t + max(1, AGVs(id).step_dur);
                append_trace(id, AGVs(id).pos, display_event_time(event_t, AGVs(id).step_dur), 'hold');
            end
            return;
        end

        AGVs(id).next_event_t = event_t + 1;
        append_trace(id, AGVs(id).pos, display_event_time(event_t, AGVs(id).step_dur), 'hold');
    end

    function resume_status = infer_resume_status_after_service(agv)
        if strcmp(agv.status, 'Loading')
            if agv.load == 1
                resume_status = 'Moving_Drop';
            else
                resume_status = 'Moving_Pick';
            end
        elseif strcmp(agv.status, 'Unloading')
            if agv.load == 1
                resume_status = 'Moving_Drop';
            else
                resume_status = 'Moving_Pick';
            end
        else
            resume_status = 'Moving_Drop';
        end
    end

    function handle_arrival_smallmap(id, event_t)
        if strcmp(AGVs(id).status, 'Yielding')
            if AGVs(id).resume_after_wait
                AGVs(id).status = 'Waiting_Clearance';
                AGVs(id).next_event_t = AGVs(id).wait_resume_t;
            elseif ~isempty(AGVs(id).yield_resume_target)
                [resume_path, resume_cost] = astar_planner_turn3(grid_map, AGVs(id).pos, AGVs(id).yield_resume_target, ...
                    AGVs(id).payload_weight, [], AGVs(id).type);
                if ~isempty(resume_path) && isfinite(resume_cost)
                    resume_path = normalize_path_four_connected(resume_path, AGVs(id).payload_weight, AGVs(id).type);
                    assign_path_to_agv_smallmap(id, resume_path, AGVs(id).yield_resume_target);
                    AGVs(id).status = AGVs(id).yield_resume_status;
                    AGVs(id).next_event_t = event_t + max(1, AGVs(id).step_dur);
                    result.replan_paths{end + 1} = struct('agv_id', id, 'path', resume_path, 'reason', 'resume_after_yield'); %#ok<AGROW>
                else
                    AGVs(id).next_event_t = inf;
                end
            else
                AGVs(id).next_event_t = inf;
            end
            return;
        end

        AGVs(id).status = 'Idle';
        AGVs(id).next_event_t = inf;
    end

    function apply_strategy_to_agvs_smallmap(loser_id, winner_id, strategy_name, replanned_path, strategy_info, event_t)
        switch strategy_name
            case 'wait_then_replan'
                original_status = AGVs(loser_id).status;
                wait_node = strategy_info.wait_node;
                prefix_path = build_prefix_path_to_wait_node(AGVs(loser_id), wait_node);
                AGVs(loser_id).resume_after_wait = true;
                AGVs(loser_id).wait_resume_status = original_status;
                AGVs(loser_id).wait_resume_target = AGVs(loser_id).target_node;
                AGVs(loser_id).wait_resume_path = replanned_path;
                AGVs(loser_id).wait_resume_t = strategy_info.resume_t;
                AGVs(loser_id).wait_node = wait_node;
                if size(prefix_path, 1) > 1
                    assign_path_to_agv_smallmap(loser_id, prefix_path, wait_node);
                    AGVs(loser_id).status = 'Yielding';
                    AGVs(loser_id).next_event_t = event_t + max(1, AGVs(loser_id).step_dur);
                else
                    AGVs(loser_id).status = 'Waiting_Clearance';
                    AGVs(loser_id).next_event_t = strategy_info.resume_t;
                end
            case 'yield_path'
                assign_path_to_agv_smallmap(loser_id, replanned_path, AGVs(loser_id).target_node);
                AGVs(loser_id).yield_resume_status = AGVs(loser_id).status;
                AGVs(loser_id).yield_resume_target = AGVs(loser_id).target_node;
                AGVs(loser_id).status = 'Yielding';
                AGVs(loser_id).next_event_t = event_t + max(1, AGVs(loser_id).step_dur);
            case 'replan_original_target'
                assign_path_to_agv_smallmap(loser_id, replanned_path, AGVs(loser_id).target_node);
                if isfield(strategy_info, 'immediate_move') && strategy_info.immediate_move && ...
                        ~isempty(AGVs(loser_id).path) && AGVs(loser_id).path_idx <= size(AGVs(loser_id).path, 1)
                    execute_immediate_replan_move_smallmap(loser_id, event_t, strategy_name);
                else
                    AGVs(loser_id).next_event_t = event_t + max(1, AGVs(loser_id).step_dur);
                end
            otherwise
                % wait_only means "stay in place for one turn" while keeping the
                % original moving identity. Changing status to Waiting_Clearance
                % turns a temporary stop into a permanent pseudo-wait state.
                AGVs(loser_id).resume_after_wait = false;
                AGVs(loser_id).wait_resume_status = '';
                AGVs(loser_id).wait_resume_target = [];
                AGVs(loser_id).wait_resume_path = [];
                AGVs(loser_id).wait_node = [];
                AGVs(loser_id).wait_resume_t = inf;
                AGVs(loser_id).next_event_t = event_t + max(1, AGVs(loser_id).step_dur);
        end
    end

    function prefix_path = build_prefix_path_to_wait_node(agv, wait_node)
        prefix_path = agv.pos;
        if isempty(wait_node)
            return;
        end
        if isempty(agv.path) || agv.path_idx > size(agv.path, 1)
            return;
        end
        remain = agv.path(agv.path_idx:end, 1:2);
        prefix_path = [agv.pos; remain]; %#ok<AGROW>
        idx = find(ismember(prefix_path, wait_node, 'rows'), 1, 'first');
        if isempty(idx)
            prefix_path = agv.pos;
        else
            prefix_path = prefix_path(1:idx, :);
        end
    end

    function assign_path_to_agv_smallmap(id, path_rc, target_node)
        current_pos = AGVs(id).pos;
        path_rc = normalize_path_four_connected(path_rc, AGVs(id).payload_weight, AGVs(id).type);

        if ~isempty(path_rc) && ~isequal(path_rc(1, :), current_pos)
            [prefix_path, prefix_cost] = astar_planner_turn3(grid_map, current_pos, path_rc(1, :), ...
                AGVs(id).payload_weight, [], AGVs(id).type);
            if ~isempty(prefix_path) && isfinite(prefix_cost)
                prefix_path = normalize_path_four_connected(prefix_path, AGVs(id).payload_weight, AGVs(id).type);
                path_rc = [prefix_path(1:end-1, :); path_rc]; %#ok<AGROW>
            else
                path_rc = [current_pos; path_rc]; %#ok<AGROW>
            end
        end

        AGVs(id).pos = current_pos;
        AGVs(id).path = path_rc;
        AGVs(id).path_idx = min(2, size(path_rc, 1) + 1);
        AGVs(id).target_node = target_node;
    end

    function path_rc = normalize_path_four_connected(path_rc, payload_weight, agv_type)
        if isempty(path_rc) || size(path_rc, 1) <= 1
            return;
        end

        normalized_path = path_rc(1, :);
        for seg_idx = 2:size(path_rc, 1)
            prev_node = normalized_path(end, :);
            curr_node = path_rc(seg_idx, :);
            if isequal(curr_node, prev_node)
                continue;
            end
            if abs(curr_node(1) - prev_node(1)) + abs(curr_node(2) - prev_node(2)) <= 1
                normalized_path(end + 1, :) = curr_node; %#ok<AGROW>
                continue;
            end

            [bridge_path, bridge_cost] = astar_planner_turn3(grid_map, prev_node, curr_node, payload_weight, [], agv_type);
            if ~isempty(bridge_path) && isfinite(bridge_cost)
                normalized_path = [normalized_path; bridge_path(2:end, 1:2)]; %#ok<AGROW>
            else
                bridge_path = build_axis_aligned_bridge(prev_node, curr_node);
                normalized_path = [normalized_path; bridge_path]; %#ok<AGROW>
            end
        end

        path_rc = normalized_path;
    end

    function bridge_path = build_axis_aligned_bridge(start_node, end_node)
        bridge_path = zeros(0, 2);
        probe = start_node;
        while probe(1) ~= end_node(1)
            probe = probe + [sign(end_node(1) - probe(1)), 0];
            bridge_path(end + 1, :) = probe; %#ok<AGROW>
        end
        while probe(2) ~= end_node(2)
            probe = probe + [0, sign(end_node(2) - probe(2))];
            bridge_path(end + 1, :) = probe; %#ok<AGROW>
        end
    end

    function execute_immediate_replan_move_smallmap(id, event_t, tag)
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            AGVs(id).next_event_t = inf;
            return;
        end

        [next_idx, next_node] = select_adjacent_path_step(AGVs(id).path, AGVs(id).pos, AGVs(id).path_idx);
        if isempty(next_node)
            fallback_goal = AGVs(id).target_node;
            if isempty(fallback_goal) && ~isempty(AGVs(id).path)
                fallback_goal = AGVs(id).path(end, 1:2);
            end
            if ~isempty(fallback_goal)
                [fallback_path, fallback_cost] = astar_planner_turn3(grid_map, AGVs(id).pos, fallback_goal, ...
                    AGVs(id).payload_weight, [], AGVs(id).type);
                if ~isempty(fallback_path) && isfinite(fallback_cost)
                    fallback_path = normalize_path_four_connected(fallback_path, AGVs(id).payload_weight, AGVs(id).type);
                    AGVs(id).path = fallback_path;
                    AGVs(id).path_idx = min(2, size(fallback_path, 1) + 1);
                    [next_idx, next_node] = select_adjacent_path_step(AGVs(id).path, AGVs(id).pos, AGVs(id).path_idx);
                end
            end
        end

        if isempty(next_node)
            AGVs(id).next_event_t = event_t + max(1, AGVs(id).step_dur);
            append_trace(id, AGVs(id).pos, display_event_time(event_t, AGVs(id).step_dur), 'hold');
            return;
        end

        AGVs(id).pos = next_node;
        AGVs(id).path_idx = next_idx + 1;
        append_trace(id, next_node, display_event_time(event_t, AGVs(id).step_dur), tag);

        if AGVs(id).path_idx > size(AGVs(id).path, 1)
            handle_arrival_smallmap(id, event_t);
        else
            AGVs(id).next_event_t = event_t + max(1, AGVs(id).step_dur);
        end
    end

    function [next_idx, next_node] = select_adjacent_path_step(path_rc, curr_pos, start_idx)
        next_idx = [];
        next_node = [];
        if isempty(path_rc)
            return;
        end
        for k = max(1, start_idx):size(path_rc, 1)
            candidate = path_rc(k, 1:2);
            if abs(candidate(1) - curr_pos(1)) + abs(candidate(2) - curr_pos(2)) == 1
                next_idx = k;
                next_node = candidate;
                return;
            end
        end
    end

    function append_trace(id, node_rc, t_disp, tag)
        if isempty(traces(id).times) || traces(id).times(end) ~= t_disp || ~isequal(traces(id).cells(end, :), node_rc)
            traces(id).cells(end + 1, :) = node_rc; %#ok<AGROW>
            traces(id).times(end + 1, 1) = t_disp; %#ok<AGROW>
            traces(id).tags{end + 1, 1} = tag; %#ok<AGROW>
        end
    end
end

function [debug_lines, cycle_nodes, breaker_id, breaker_blocker_id, breaker_debug] = build_interlock_debug_lines(AGVs, conflict_records, current_t, task_list)
    debug_lines = {};
    cycle_nodes = [];
    breaker_id = 0;
    breaker_blocker_id = 0;
    breaker_debug = '';
    num_agvs = numel(AGVs);
    if num_agvs < 3 || isempty(conflict_records)
        return;
    end

    edges = cell(1, num_agvs);
    reasons = cell(1, num_agvs);
    for i = 1:numel(conflict_records)
        rec = conflict_records(i);
        if rec.self_id <= 0 || rec.blocker_id <= 0 || rec.self_id == rec.blocker_id
            continue;
        end
        % Use the true wait-dependency direction: self -> blocker.
        edges{rec.self_id} = unique([edges{rec.self_id}, rec.blocker_id]);
        reasons{rec.self_id}{end + 1} = sprintf('%s/%s@t=%g', rec.classified_type, rec.window_type, rec.first_conflict_t); %#ok<AGROW>
    end

    edge_parts = {};
    for id = 1:num_agvs
        if isempty(edges{id})
            continue;
        end
        reason_txt = '';
        if ~isempty(reasons{id})
            reason_txt = strjoin(reasons{id}, ',');
        end
        target_ids = arrayfun(@(x) agv_display_id(AGVs, x), edges{id}, 'UniformOutput', true);
        edge_parts{end + 1} = sprintf('AGV%d->[%s]{%s}', agv_display_id(AGVs, id), sprintf('AGV%d ', target_ids), reason_txt); %#ok<AGROW>
        edge_parts{end} = strrep(edge_parts{end}, ' ]', ']');
    end
    if ~isempty(edge_parts)
        debug_lines{end + 1} = sprintf('  interlock_graph[t=%g]: %s', current_t, strjoin(edge_parts, ' ; ')); %#ok<AGROW>
    end

    dep_graph = struct('edges', {edges});
    sccs = tarjan_scc_smallmap(dep_graph, num_agvs);
    cycle_parts = {};
    for i = 1:numel(sccs)
        comp = sccs{i};
        if numel(comp) <= 1
            continue;
        end
        comp_disp = arrayfun(@(x) agv_display_id(AGVs, x), comp, 'UniformOutput', true);
        cycle_parts{end + 1} = sprintf('{%s}', sprintf('AGV%d ', comp_disp)); %#ok<AGROW>
        cycle_parts{end} = strrep(cycle_parts{end}, ' }', '}');
    end
    if ~isempty(cycle_parts)
        debug_lines{end + 1} = sprintf('  interlock_scc[t=%g]: %s', current_t, strjoin(cycle_parts, ' ')); %#ok<AGROW>
        cycle_nodes = sccs{find(cellfun(@numel, sccs) > 1, 1, 'first')}; %#ok<FNDSB>
        debug_lines{end + 1} = sprintf('  interlock_cycle_state[t=%g]: %s', current_t, ...
            format_cycle_state_smallmap(AGVs, cycle_nodes, task_list, current_t)); %#ok<AGROW>
        [breaker_id, breaker_debug] = select_interlock_breaker_smallmap(AGVs, cycle_nodes, task_list, current_t);
        if any(edges{breaker_id} > 0)
            breaker_blocker_id = edges{breaker_id}(1);
        else
            breaker_blocker_id = cycle_nodes(1);
        end
    end
end

function txt = format_cycle_state_smallmap(AGVs, cycle_nodes, task_list, current_t)
    parts = cell(1, numel(cycle_nodes));
    for i = 1:numel(cycle_nodes)
        id = cycle_nodes(i);
        p = calculate_ahp_priority(AGVs(id), task_list, current_t);
        parts{i} = sprintf('AGV%d[state=%s,pos=[%d,%d],next_t=%g,target=[%d,%d],p=%.3f]', ...
            agv_display_id(AGVs, id), AGVs(id).status, AGVs(id).pos(1), AGVs(id).pos(2), AGVs(id).next_event_t, ...
            AGVs(id).target_node(1), AGVs(id).target_node(2), p);
    end
    txt = strjoin(parts, ' | ');
end

function [breaker_id, debug_str] = select_interlock_breaker_smallmap(AGVs, cycle_nodes, task_list, current_t)
    breaker_id = cycle_nodes(1);
    best_score = inf;
    parts = cell(1, numel(cycle_nodes));
    for i = 1:numel(cycle_nodes)
        id = cycle_nodes(i);
        p = calculate_ahp_priority(AGVs(id), task_list, current_t);
        score = p + 0.0001 * AGVs(id).payload_weight + 0.01 * id;
        parts{i} = sprintf('AGV%d[p=%.3f,payload=%g,score=%.4f]', agv_display_id(AGVs, id), p, AGVs(id).payload_weight, score);
        if score < best_score
            best_score = score;
            breaker_id = id;
        end
    end
    debug_str = strjoin(parts, ' | ');
end

function txt = format_priority_snapshot_smallmap(priority_values, display_ids)
    if isempty(priority_values)
        txt = '';
        return;
    end
    if nargin < 2 || isempty(display_ids)
        display_ids = 1:numel(priority_values);
    end
    parts = cell(1, numel(priority_values));
    for i = 1:numel(priority_values)
        parts{i} = sprintf('AGV-%d=%.3f', display_ids(i), priority_values(i));
    end
    txt = strjoin(parts, ' | ');
end

function txt = format_pairwise_priority_smallmap(priority_values, agv_ids, display_ids)
    txt = '';
    if isempty(priority_values) || numel(agv_ids) < 2
        return;
    end
    if nargin < 3 || isempty(display_ids)
        display_ids = 1:numel(priority_values);
    end

    agv_ids = unique(agv_ids(:)');
    parts = cell(0, 1);
    for i = 1:numel(agv_ids)
        for j = i + 1:numel(agv_ids)
            id_a = agv_ids(i);
            id_b = agv_ids(j);
            pa = priority_values(id_a);
            pb = priority_values(id_b);
            if pa < pb || (pa == pb && id_a > id_b)
                winner = id_b;
                loser = id_a;
            else
                winner = id_a;
                loser = id_b;
            end
            parts{end + 1, 1} = sprintf('AGV-%d(%.3f) vs AGV-%d(%.3f) -> winner=AGV-%d loser=AGV-%d', ... %#ok<AGROW>
                display_ids(id_a), pa, display_ids(id_b), pb, display_ids(winner), display_ids(loser));
        end
    end
    txt = strjoin(parts, ' ; ');
end

function [strategy_name, strategy_desc, yield_goal, replanned_path, strategy_info] = ...
    resolve_interlock_break_strategy_like_event_sm(AGVs, grid_map, breaker_id, blocker_id, cycle_nodes, current_t, first_conflict_t)
    strategy_info = struct('wait_node', [], 'resume_t', [], 'last_preconflict_t', [], ...
        'first_conflict_t', first_conflict_t, 'conflict_node', [], 'immediate_move', false);
    yield_goal = [];
    replanned_path = [];

    [escape_success, escape_path, escape_goal] = plan_interlock_escape_path_like_event_sm(AGVs, grid_map, breaker_id, cycle_nodes);
    if escape_success
        strategy_name = 'yield_path';
        strategy_desc = 'interlock break: breaker retreats out of cycle corridor';
        yield_goal = escape_goal;
        replanned_path = escape_path;
        return;
    end

    if ~isempty(AGVs(breaker_id).target_node)
        [replanned_path, goal_cost] = replan_avoiding_winner_window(AGVs, grid_map, breaker_id, blocker_id, current_t, first_conflict_t);
        if ~isempty(replanned_path) && isfinite(goal_cost) && ...
                has_clear_first_step_for_breaker(AGVs, breaker_id, blocker_id, replanned_path)
            strategy_name = 'replan_original_target';
            strategy_desc = 'interlock break: breaker replans first';
            return;
        end
    end

    [yield_success, yield_path, yield_goal] = plan_yield_path_like_event_sm(AGVs, grid_map, breaker_id, blocker_id);
    if yield_success
        strategy_name = 'yield_path';
        strategy_desc = 'interlock break: breaker yields locally';
        replanned_path = yield_path;
        return;
    end

    [wait_success, wait_node, resume_t, last_preconflict_t, conflict_node, replanned_path] = ...
        plan_wait_then_replan_like_event_sm(AGVs, grid_map, breaker_id, blocker_id, current_t, first_conflict_t);
    if wait_success
        strategy_name = 'wait_then_replan';
        strategy_desc = 'interlock break: breaker waits then replans';
        yield_goal = wait_node;
        strategy_info.wait_node = wait_node;
        strategy_info.resume_t = resume_t;
        strategy_info.last_preconflict_t = last_preconflict_t;
        strategy_info.conflict_node = conflict_node;
        return;
    end

    strategy_name = 'wait_only';
    strategy_desc = 'interlock break fallback: stop and wait';
end

function [success, best_path, best_goal] = plan_interlock_escape_path_like_event_sm(AGVs, grid_map, breaker_id, cycle_nodes)
    success = false;
    best_path = [];
    best_goal = [];

    curr_pos = AGVs(breaker_id).pos;
    reserved_nodes = zeros(0, 2);
    for i = 1:numel(cycle_nodes)
        id = cycle_nodes(i);
        reserved_nodes(end + 1, :) = AGVs(id).pos; %#ok<AGROW>
        if ~isempty(AGVs(id).path) && AGVs(id).path_idx <= size(AGVs(id).path, 1)
            reserved_nodes = [reserved_nodes; AGVs(id).path(AGVs(id).path_idx:end, 1:2)]; %#ok<AGROW>
        end
    end
    if ~isempty(reserved_nodes)
        reserved_nodes = unique(reserved_nodes, 'rows');
    end

    best_score = -inf;
    max_radius = 5;
    for radius = 1:max_radius
        candidate_nodes = zeros(0, 2);
        for dr = -radius:radius
            for dc = -radius:radius
                if abs(dr) + abs(dc) ~= radius
                    continue;
                end
                candidate = curr_pos + [dr, dc];
                if candidate(1) < 1 || candidate(1) > size(grid_map, 1) || candidate(2) < 1 || candidate(2) > size(grid_map, 2)
                    continue;
                end
                if grid_map(candidate(1), candidate(2)) == 1
                    continue;
                end
                if ismember(candidate, reserved_nodes, 'rows')
                    continue;
                end
                candidate_nodes(end + 1, :) = candidate; %#ok<AGROW>
            end
        end

        for i = 1:size(candidate_nodes, 1)
            candidate = candidate_nodes(i, :);
            [candidate_path, candidate_cost] = astar_planner_turn3(grid_map, curr_pos, candidate, ...
                AGVs(breaker_id).payload_weight, [], AGVs(breaker_id).type);
            if isempty(candidate_path) || ~isfinite(candidate_cost)
                continue;
            end
            candidate_path = normalize_path_four_connected(candidate_path, AGVs(breaker_id).payload_weight, AGVs(breaker_id).type);
            if ~has_clear_first_step_for_cycle(AGVs, breaker_id, cycle_nodes, candidate_path)
                % First step must immediately move away from the current cycle blockage.
                continue;
            end

            min_gap = inf;
            for j = 1:numel(cycle_nodes)
                if cycle_nodes(j) == breaker_id
                    continue;
                end
                min_gap = min(min_gap, manhattan_dist_local(candidate, AGVs(cycle_nodes(j)).pos));
            end
            score = 5 * min_gap - candidate_cost - 0.2 * radius;
            if score > best_score
                best_score = score;
                best_goal = candidate;
                best_path = candidate_path;
            end
        end

        if ~isempty(best_path)
            success = true;
            return;
        end
    end
end

function tf = has_clear_first_step_for_cycle(AGVs, breaker_id, cycle_nodes, replanned_path)
    tf = false;
    if isempty(replanned_path)
        return;
    end

    curr_pos = AGVs(breaker_id).pos;
    first_step = [];
    for k = 1:size(replanned_path, 1)
        candidate = replanned_path(k, 1:2);
        if abs(candidate(1) - curr_pos(1)) + abs(candidate(2) - curr_pos(2)) == 1
            first_step = candidate;
            break;
        end
    end
    if isempty(first_step)
        return;
    end

    for i = 1:numel(cycle_nodes)
        id = cycle_nodes(i);
        if id == breaker_id
            continue;
        end
        if isequal(first_step, AGVs(id).pos)
            return;
        end
        if ~isempty(AGVs(id).path) && AGVs(id).path_idx <= size(AGVs(id).path, 1)
            if isequal(first_step, AGVs(id).path(AGVs(id).path_idx, 1:2))
                return;
            end
        end
    end

    tf = true;
end

function tf = has_clear_first_step_for_breaker(AGVs, breaker_id, blocker_id, replanned_path)
    tf = false;
    if isempty(replanned_path)
        return;
    end

    curr_pos = AGVs(breaker_id).pos;
    first_step = [];
    for k = 1:size(replanned_path, 1)
        candidate = replanned_path(k, 1:2);
        if abs(candidate(1) - curr_pos(1)) + abs(candidate(2) - curr_pos(2)) == 1
            first_step = candidate;
            break;
        end
    end
    if isempty(first_step)
        return;
    end

    blocker_pos = AGVs(blocker_id).pos;
    if isequal(first_step, blocker_pos)
        return;
    end

    if ~isempty(AGVs(blocker_id).path) && AGVs(blocker_id).path_idx <= size(AGVs(blocker_id).path, 1)
        blocker_next = AGVs(blocker_id).path(AGVs(blocker_id).path_idx, 1:2);
        if isequal(first_step, blocker_next)
            return;
        end
    end

    tf = true;
end

function comps = tarjan_scc_smallmap(dep_graph, num_nodes)
    index = 0;
    stack = [];
    on_stack = false(1, num_nodes);
    indices = zeros(1, num_nodes);
    lowlink = zeros(1, num_nodes);
    comps = {};

    for v = 1:num_nodes
        if indices(v) == 0
            strongconnect(v);
        end
    end

    function strongconnect(v)
        index = index + 1;
        indices(v) = index;
        lowlink(v) = index;
        stack(end + 1) = v; %#ok<AGROW>
        on_stack(v) = true;

        neighbors = dep_graph.edges{v};
        for n_idx = 1:numel(neighbors)
            w = neighbors(n_idx);
            if indices(w) == 0
                strongconnect(w);
                lowlink(v) = min(lowlink(v), lowlink(w));
            elseif on_stack(w)
                lowlink(v) = min(lowlink(v), indices(w));
            end
        end

        if lowlink(v) == indices(v)
            comp = [];
            while true
                w = stack(end);
                stack(end) = [];
                on_stack(w) = false;
                comp(end + 1) = w; %#ok<AGROW>
                if w == v
                    break;
                end
            end
            comps{end + 1} = comp; %#ok<AGROW>
        end
    end
end

function conflict_records = collect_due_conflicts_smallmap(AGVs, due_ids, current_t, horizon_steps, task_list)
    conflict_records = struct('self_id', {}, 'blocker_id', {}, 'window_detected', {}, 'window_blocker', {}, ...
        'window_type', {}, 'first_conflict_t', {}, 'conflict_source', {}, 'classified_type', {}, ...
        'winner_id', {}, 'loser_id', {}, 'priority_a', {}, 'priority_b', {});
    pair_seen = containers.Map('KeyType', 'char', 'ValueType', 'logical');

    for idx = 1:numel(due_ids)
        id = due_ids(idx);
        if ~is_moving_state_local(AGVs(id).status)
            continue;
        end

        [window_detected, window_blocker, window_type, first_conflict_t] = ...
            detect_event_window_conflict_like_event_sm(AGVs, id, current_t, horizon_steps);
        runtime_blocker = detect_runtime_blocker_like_event_sm(AGVs, id, current_t);

        blocker = 0;
        conflict_source = 'none';
        if runtime_blocker > 0
            blocker = runtime_blocker;
            conflict_source = 'runtime';
            window_type = 'none';
            first_conflict_t = current_t;
        elseif window_detected
            blocker = window_blocker;
            conflict_source = 'window';
        end

        if blocker <= 0
            continue;
        end

        pair = sort([id, blocker]);
        pair_key = sprintf('%d_%d_%d', round(current_t), pair(1), pair(2));
        if isKey(pair_seen, pair_key)
            continue;
        end
        pair_seen(pair_key) = true;

        classified_type = classify_conflict_with_window_like_event_sm(AGVs, id, blocker, current_t, window_detected, window_type, first_conflict_t);
        [winner_id, loser_id, priority_a, priority_b] = decide_priority_outcome(AGVs, id, blocker, task_list, current_t);
        if strcmp(classified_type, 'Occupied node') || strcmp(classified_type, 'Rear-end')
            loser_id = id;
            winner_id = blocker;
        end

        conflict_records(end + 1) = struct( ... %#ok<AGROW>
            'self_id', id, ...
            'blocker_id', blocker, ...
            'window_detected', window_detected, ...
            'window_blocker', window_blocker, ...
            'window_type', window_type, ...
            'first_conflict_t', first_conflict_t, ...
            'conflict_source', conflict_source, ...
            'classified_type', classified_type, ...
            'winner_id', winner_id, ...
            'loser_id', loser_id, ...
            'priority_a', priority_a, ...
            'priority_b', priority_b);
    end
end

function case_timeline = build_runtime_timeline_rows(case_name, traces, cell_id_map, winner_id, loser_id)
    case_timeline = {};
    for agv_id = 1:numel(traces)
        role = 'peer';
        if agv_id == winner_id
            role = 'winner';
        elseif agv_id == loser_id
            role = 'loser';
        end
        [dense_times, dense_cells, dense_tags] = densify_trace_steps(traces(agv_id));
        for k = 1:numel(dense_times)
            rc = dense_cells(k, :);
            case_timeline(end + 1, :) = { ...
                case_name, traces(agv_id).display_id, role, dense_times(k), ...
                cell_id_map(rc(1), rc(2)), rc(1), rc(2), dense_tags{k}}; %#ok<AGROW>
        end
    end
end

function entry = build_conflict_log_entry_smallmap(AGVs, rec, current_t, strategy_name, strategy_desc, yield_goal, replanned_path)
    self_id = rec.self_id;
    blocker_id = rec.blocker_id;
    self_pos = AGVs(self_id).pos;
    blocker_pos = AGVs(blocker_id).pos;
    self_next = get_planned_next_cell_local(AGVs, self_id, current_t);
    blocker_next = get_planned_next_cell_local(AGVs, blocker_id, current_t);
    self_status = AGVs(self_id).status;
    blocker_status = AGVs(blocker_id).status;

    self_events = build_agv_future_events_like_event_sm(AGVs(self_id), current_t, max(current_t, rec.first_conflict_t));
    blocker_events = build_agv_future_events_like_event_sm(AGVs(blocker_id), current_t, max(current_t, rec.first_conflict_t));
    self_evt = find_future_event_at_t(self_events, rec.first_conflict_t);
    blocker_evt = find_future_event_at_t(blocker_events, rec.first_conflict_t);

    conflict_node = [];
    if ~isempty(self_evt)
        conflict_node = self_evt.to_node;
    elseif ~isempty(self_next)
        conflict_node = self_next;
    end

    reason = explain_conflict_reason_smallmap(rec.classified_type, rec.conflict_source, rec.window_type, ...
        self_pos, self_next, blocker_pos, blocker_next, self_status, blocker_status, self_evt, blocker_evt);

    entry = struct( ...
        'detection_t', current_t, ...
        'predicted_conflict_t', rec.first_conflict_t, ...
        'self_id', self_id, ...
        'blocker_id', blocker_id, ...
        'conflict_source', rec.conflict_source, ...
        'window_type', rec.window_type, ...
        'classified_type', rec.classified_type, ...
        'winner_id', rec.winner_id, ...
        'loser_id', rec.loser_id, ...
        'priority_a', rec.priority_a, ...
        'priority_b', rec.priority_b, ...
        'self_status', self_status, ...
        'blocker_status', blocker_status, ...
        'self_pos', self_pos, ...
        'self_next', self_next, ...
        'blocker_pos', blocker_pos, ...
        'blocker_next', blocker_next, ...
        'conflict_node', conflict_node, ...
        'reason', reason, ...
        'strategy_name', strategy_name, ...
        'strategy_desc', strategy_desc, ...
        'yield_goal', yield_goal, ...
        'replanned_path', replanned_path);
end

function reason = explain_conflict_reason_smallmap(classified_type, conflict_source, window_type, ...
    self_pos, self_next, blocker_pos, blocker_next, self_status, blocker_status, self_evt, blocker_evt)
    source_text = sprintf('source=%s', conflict_source);
    if ~strcmp(window_type, 'none')
        source_text = sprintf('%s, window=%s', source_text, window_type);
    end

    switch classified_type
        case 'Occupied node'
            reason = sprintf('%s. self_next=%s equals blocker_pos=%s, blocker_status=%s, blocker_next=%s.', ...
                source_text, node_str_local(self_next), node_str_local(blocker_pos), blocker_status, node_str_local(blocker_next));
        case 'Rear-end'
            reason = sprintf('%s. same travel direction inferred: self_pos=%s -> self_next=%s, blocker_pos=%s -> blocker_next=%s.', ...
                source_text, node_str_local(self_pos), node_str_local(self_next), node_str_local(blocker_pos), node_str_local(blocker_next));
        case 'Head-on swap'
            reason = sprintf('%s. swap detected: self_next=%s == blocker_pos=%s and blocker_next=%s == self_pos=%s.', ...
                source_text, node_str_local(self_next), node_str_local(blocker_pos), node_str_local(blocker_next), node_str_local(self_pos));
        case 'Head-on meet'
            if ~isempty(self_evt) && ~isempty(blocker_evt) && ~isempty(self_evt.from_node) && ~isempty(blocker_evt.from_node)
                reason = sprintf('%s. opposite directions into same conflict node=%s: self %s->%s, blocker %s->%s.', ...
                    source_text, node_str_local(self_evt.to_node), node_str_local(self_evt.from_node), node_str_local(self_evt.to_node), ...
                    node_str_local(blocker_evt.from_node), node_str_local(blocker_evt.to_node));
            else
                reason = sprintf('%s. opposite-direction meet inferred near self_next=%s and blocker_next=%s.', ...
                    source_text, node_str_local(self_next), node_str_local(blocker_next));
            end
        otherwise
            reason = sprintf('%s. same target contention inferred: self_next=%s, blocker_next=%s.', ...
                source_text, node_str_local(self_next), node_str_local(blocker_next));
    end
end

function [dense_times, dense_cells, dense_tags] = densify_trace_steps(trace)
    if isempty(trace.times)
        dense_times = [];
        dense_cells = zeros(0, 2);
        dense_tags = {};
        return;
    end

    times = trace.times(:);
    cells = trace.cells;
    tags = trace.tags;
    dense_times = (times(1):times(end))';
    dense_cells = zeros(numel(dense_times), 2);
    dense_tags = cell(numel(dense_times), 1);

    src_idx = 1;
    for i = 1:numel(dense_times)
        t = dense_times(i);
        while src_idx < numel(times) && times(src_idx + 1) <= t
            src_idx = src_idx + 1;
        end
        dense_cells(i, :) = cells(src_idx, :);
        if times(src_idx) == t
            dense_tags{i} = tags{src_idx};
        else
            dense_tags{i} = 'hold';
        end
    end
end

function plot_case_runtime_visualization(grid_map, ~, ~, result, output_png)
    style = agv_plot_theme();
    fig = figure('Color', 'w', 'Position', [120, 120, 980, 860], 'Name', 'Conflict Validation Runtime');
    ax = axes(fig);
    hold(ax, 'on');

    imagesc(ax, [1 size(grid_map, 2)], [1 size(grid_map, 1)], grid_map);
    colormap(ax, [1 1 1; 0 0 0]);
    clim(ax, [0 1]);
    axis(ax, 'equal');
    axis(ax, [0.5, size(grid_map, 2) + 0.5, 0.5, size(grid_map, 1) + 0.5]);
    set(ax, 'YDir', 'reverse');
    set(ax, 'XTick', 1:size(grid_map, 2), 'YTick', 1:size(grid_map, 1), ...
        'LineWidth', 1.0, 'TickLength', [0 0], ...
        'FontName', style.cn_font, 'FontSize', 9);
    draw_cell_boundaries_local(ax, size(grid_map, 1), size(grid_map, 2), [0.62 0.62 0.62], 0.65);

    runtime_traces = reconstruct_traces_from_rows(result.timeline_rows);
    palette = lines(max(2, numel(runtime_traces)));
    for agv_id = 1:numel(runtime_traces)
        tr = runtime_traces(agv_id);
        if isempty(tr.cells)
            continue;
        end
        [plot_x, plot_y] = build_non_diagonal_polyline(tr.cells);
        plot(ax, plot_x, plot_y, '-', 'Color', palette(agv_id, :), 'LineWidth', 2.6);
        scatter(ax, tr.cells(:, 2), tr.cells(:, 1), 30, 'filled', 'MarkerFaceColor', palette(agv_id, :), 'MarkerEdgeColor', 'none');
        scatter(ax, tr.cells(1, 2), tr.cells(1, 1), 130, 'o', 'filled', 'MarkerFaceColor', palette(agv_id, :), 'MarkerEdgeColor', 'k');
        text(ax, tr.cells(1, 2) + 0.2, tr.cells(1, 1) - 0.2, sprintf('AGV-%d', tr.display_id), 'Color', palette(agv_id, :), 'FontWeight', 'bold');
    end

    xlabel(ax, 'Column', 'FontName', style.en_font);
    ylabel(ax, 'Row', 'FontName', style.en_font);
    exportgraphics(fig, output_png, 'Resolution', 220);
end

function traces = reconstruct_traces_from_rows(case_timeline)
    if isempty(case_timeline)
        traces = struct('cells', {}, 'times', {}, 'tags', {});
        return;
    end
    agv_ids = unique(cell2mat(case_timeline(:, 2)));
    traces = repmat(struct('cells', [], 'times', [], 'tags', {{}}, 'display_id', []), 1, numel(agv_ids));
    for i = 1:numel(agv_ids)
        agv_id = agv_ids(i);
        rows = case_timeline(cell2mat(case_timeline(:, 2)) == agv_id, :);
        cells = zeros(size(rows, 1), 2);
        times = zeros(size(rows, 1), 1);
        tags = cell(size(rows, 1), 1);
        for k = 1:size(rows, 1)
            cells(k, :) = [rows{k, 6}, rows{k, 7}];
            times(k) = rows{k, 4};
            tags{k} = rows{k, 8};
        end
        traces(i).cells = cells;
        traces(i).times = times;
        traces(i).tags = tags;
        traces(i).display_id = agv_id;
    end
end

function [plot_x, plot_y] = build_non_diagonal_polyline(cells)
    plot_x = [];
    plot_y = [];
    if isempty(cells)
        return;
    end

    plot_x(end + 1, 1) = cells(1, 2); %#ok<AGROW>
    plot_y(end + 1, 1) = cells(1, 1); %#ok<AGROW>
    for i = 2:size(cells, 1)
        prev = cells(i - 1, :);
        curr = cells(i, :);
        manhattan_step = abs(curr(1) - prev(1)) + abs(curr(2) - prev(2));

        if manhattan_step <= 1
            plot_x(end + 1, 1) = curr(2); %#ok<AGROW>
            plot_y(end + 1, 1) = curr(1); %#ok<AGROW>
        else
            % Break the polyline instead of drawing a fake diagonal jump.
            plot_x(end + 1, 1) = NaN; %#ok<AGROW>
            plot_y(end + 1, 1) = NaN; %#ok<AGROW>
            plot_x(end + 1, 1) = curr(2); %#ok<AGROW>
            plot_y(end + 1, 1) = curr(1); %#ok<AGROW>
        end
    end
end

function blocker_id = detect_runtime_blocker_like_event_sm(AGVs, id, event_t)
    blocker_id = 0;
    if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
        return;
    end

    curr_pos = AGVs(id).pos;
    next_node = AGVs(id).path(AGVs(id).path_idx, 1:2);
    nr = next_node(1);
    nc = next_node(2);

    for other = 1:numel(AGVs)
        if other == id
            continue;
        end
        other_curr = AGVs(other).pos;
        if AGVs(other).next_event_t == event_t && is_moving_state_local(AGVs(other).status) && ...
                ~isempty(AGVs(other).path) && AGVs(other).path_idx <= size(AGVs(other).path, 1)
            other_next = AGVs(other).path(AGVs(other).path_idx, 1:2);
        else
            other_next = other_curr;
        end

        if nr == other_next(1) && nc == other_next(2)
            blocker_id = other;
            return;
        end
        if nr == other_curr(1) && nc == other_curr(2) && ...
                other_next(1) == curr_pos(1) && other_next(2) == curr_pos(2)
            blocker_id = other;
            return;
        end
        if nr == other_curr(1) && nc == other_curr(2) && AGVs(other).next_event_t > event_t
            blocker_id = other;
            return;
        end
    end
end

function [detected, blocker_id, conflict_type, first_conflict_t] = detect_event_window_conflict_like_event_sm(AGVs, id_self, current_t, horizon_steps)
    horizon_t = current_t + horizon_steps;
    reservations = build_event_window_reservations_like_event_sm(AGVs, id_self, current_t, horizon_t);

    detected = false;
    blocker_id = 0;
    conflict_type = 'none';
    first_conflict_t = -1;

    self_events = build_agv_future_events_like_event_sm(AGVs(id_self), current_t, horizon_t);
    for i = 1:numel(self_events)
        evt = self_events(i);
        node_key = make_node_key(evt.to_node, evt.t);
        if isKey(reservations.node, node_key)
            detected = true;
            blocker_id = reservations.node(node_key);
            conflict_type = 'reserved_node';
            first_conflict_t = evt.t;
            return;
        end

        if ~isempty(evt.from_node)
            rev_edge_key = make_edge_key(evt.to_node, evt.from_node, evt.t);
            if isKey(reservations.edge, rev_edge_key)
                detected = true;
                blocker_id = reservations.edge(rev_edge_key);
                conflict_type = 'reserved_edge_swap';
                first_conflict_t = evt.t;
                return;
            end
        end
    end
end

function reservations = build_event_window_reservations_like_event_sm(AGVs, ignore_id, current_t, horizon_t)
    reservations.node = containers.Map('KeyType', 'char', 'ValueType', 'double');
    reservations.edge = containers.Map('KeyType', 'char', 'ValueType', 'double');

    for id = 1:numel(AGVs)
        if id == ignore_id
            continue;
        end

        wait_until = current_t;
        if ~is_moving_state_local(AGVs(id).status) || isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            wait_until = horizon_t;
        elseif AGVs(id).next_event_t > current_t
            wait_until = min(AGVs(id).next_event_t, horizon_t);
        end

        for t = current_t:wait_until
            key = make_node_key(AGVs(id).pos, t);
            if ~isKey(reservations.node, key)
                reservations.node(key) = id;
            end
        end

        other_events = build_agv_future_events_like_event_sm(AGVs(id), current_t, horizon_t);
        for k = 1:numel(other_events)
            evt = other_events(k);
            node_key = make_node_key(evt.to_node, evt.t);
            if ~isKey(reservations.node, node_key)
                reservations.node(node_key) = id;
            end
            if ~isempty(evt.from_node)
                edge_key = make_edge_key(evt.from_node, evt.to_node, evt.t);
                if ~isKey(reservations.edge, edge_key)
                    reservations.edge(edge_key) = id;
                end
            end
        end
    end
end

function events = build_agv_future_events_like_event_sm(agv, current_t, horizon_t)
    events = struct('t', {}, 'from_node', {}, 'to_node', {});
    if isempty(agv.path) || agv.path_idx > size(agv.path, 1) || ~is_moving_state_local(agv.status)
        return;
    end

    move_t = max(current_t, agv.next_event_t);
    prev_node = agv.pos;
    event_idx = 0;
    for idx = agv.path_idx:size(agv.path, 1)
        if move_t > horizon_t
            break;
        end
        event_idx = event_idx + 1;
        events(event_idx).t = move_t;
        events(event_idx).from_node = prev_node;
        events(event_idx).to_node = agv.path(idx, 1:2);
        prev_node = agv.path(idx, 1:2);
        move_t = move_t + max(1, agv.step_dur);
    end
end

function key = make_node_key(node_rc, t)
    key = sprintf('%d_%d_%d', node_rc(1), node_rc(2), round(t));
end

function key = make_edge_key(from_rc, to_rc, t)
    key = sprintf('%d_%d_%d_%d_%d', from_rc(1), from_rc(2), to_rc(1), to_rc(2), round(t));
end

function name = classify_conflict_like_event_sm(AGVs, id_self, id_blocker, event_t)
    target_self = AGVs(id_self).path(AGVs(id_self).path_idx, 1:2);
    pos_self = AGVs(id_self).pos;
    pos_blocker = AGVs(id_blocker).pos;
    other_next = get_planned_next_cell_local(AGVs, id_blocker, event_t);

    is_swapping = isequal(target_self, pos_blocker) && isequal(other_next, pos_self);
    is_same_target = isequal(target_self, other_next);

    name = 'Node contention';
    if is_swapping
        name = 'Head-on swap';
    elseif isequal(target_self, pos_blocker)
        if AGVs(id_blocker).next_event_t > event_t || ...
                ~is_moving_state_local(AGVs(id_blocker).status) || ...
                strcmp(AGVs(id_blocker).status, 'Waiting_Clearance')
            name = 'Occupied node';
        else
            name = 'Rear-end';
        end
    elseif is_same_target
        name = 'Node contention';
    end
end

function name = classify_conflict_with_window_like_event_sm(AGVs, id_self, id_blocker, current_t, window_detected, window_type, first_conflict_t)
    name = classify_conflict_like_event_sm(AGVs, id_self, id_blocker, current_t);

    if strcmp(window_type, 'reserved_edge_swap')
        name = 'Head-on swap';
        return;
    end

    if ~window_detected || first_conflict_t < current_t || ~strcmp(name, 'Node contention')
        return;
    end

    self_events = build_agv_future_events_like_event_sm(AGVs(id_self), current_t, first_conflict_t);
    blocker_events = build_agv_future_events_like_event_sm(AGVs(id_blocker), current_t, first_conflict_t);
    self_evt = find_future_event_at_t(self_events, first_conflict_t);
    blocker_evt = find_future_event_at_t(blocker_events, first_conflict_t);
    if isempty(self_evt)
        return;
    end

    blocker_static = isempty(blocker_evt) || ...
        (AGVs(id_blocker).next_event_t > first_conflict_t) || ...
        ~is_moving_state_local(AGVs(id_blocker).status);

    if ~isempty(blocker_evt) && ~isempty(self_evt.from_node) && ~isempty(blocker_evt.from_node)
        dir_self = self_evt.to_node - self_evt.from_node;
        dir_blocker = blocker_evt.to_node - blocker_evt.from_node;
        if dot(dir_self, dir_blocker) > 0 && ...
                isequal(self_evt.to_node, blocker_evt.from_node) && ...
                AGVs(id_self).step_dur < AGVs(id_blocker).step_dur
            name = 'Rear-end';
            return;
        end
    end

    if isempty(blocker_evt) || ~isequal(self_evt.to_node, blocker_evt.to_node)
        if blocker_static && isequal(self_evt.to_node, AGVs(id_blocker).pos)
            self_dir = get_agv_motion_direction_at_time(AGVs(id_self), current_t, first_conflict_t);
            blocker_dir = get_agv_motion_direction_at_time(AGVs(id_blocker), current_t, first_conflict_t);
            if ~isempty(self_dir) && ~isempty(blocker_dir) && dot(self_dir, blocker_dir) > 0 && ...
                    AGVs(id_self).step_dur < AGVs(id_blocker).step_dur
                name = 'Rear-end';
            else
                name = 'Occupied node';
            end
        end
        return;
    end

    if isempty(self_evt.from_node) || isempty(blocker_evt.from_node)
        return;
    end

    dir_self = self_evt.to_node - self_evt.from_node;
    dir_blocker = blocker_evt.to_node - blocker_evt.from_node;
    if dot(dir_self, dir_blocker) < 0
        name = 'Head-on meet';
    elseif dot(dir_self, dir_blocker) > 0 && AGVs(id_self).step_dur < AGVs(id_blocker).step_dur
        behind_metric = dot((blocker_evt.to_node - self_evt.from_node), dir_self);
        if behind_metric >= 0
            name = 'Rear-end';
        end
    end
end

function dir = get_agv_motion_direction_at_time(agv, current_t, target_t)
    dir = [];
    events = build_agv_future_events_like_event_sm(agv, current_t, target_t);
    evt = find_future_event_at_t(events, target_t);
    if isempty(evt) || isempty(evt.from_node)
        return;
    end
    dir = evt.to_node - evt.from_node;
end

function evt = find_future_event_at_t(events, target_t)
    evt = [];
    for i = 1:numel(events)
        if events(i).t == target_t
            evt = events(i);
            return;
        end
    end
end

function next_cell = get_planned_next_cell_local(AGVs, id, event_t)
    if AGVs(id).next_event_t == event_t && is_moving_state_local(AGVs(id).status) && ...
            ~isempty(AGVs(id).path) && AGVs(id).path_idx <= size(AGVs(id).path, 1)
        next_cell = AGVs(id).path(AGVs(id).path_idx, 1:2);
    elseif ~isempty(AGVs(id).path) && AGVs(id).path_idx <= size(AGVs(id).path, 1)
        next_cell = AGVs(id).path(AGVs(id).path_idx, 1:2);
    else
        next_cell = AGVs(id).pos;
    end
end

function tf = is_moving_state_local(state_name)
    tf = ismember(state_name, {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home', 'Yielding'});
end

function [winner_id, loser_id, priority_a, priority_b] = decide_priority_outcome(AGVs, id_a, id_b, task_list, event_t)
    priority_a = calculate_ahp_priority(AGVs(id_a), task_list, event_t);
    priority_b = calculate_ahp_priority(AGVs(id_b), task_list, event_t);

    should_first_yield = (priority_a < priority_b) || (priority_a == priority_b && id_a > id_b);
    if should_first_yield
        loser_id = id_a;
        winner_id = id_b;
    else
        loser_id = id_b;
        winner_id = id_a;
    end
end

function [strategy_name, strategy_desc, yield_goal, replanned_path, strategy_info] = ...
    resolve_strategy_like_event_sm(AGVs, grid_map, loser_id, winner_id, classified_type, window_type, current_t, first_conflict_t, window_detected)
    replanned_path = [];
    strategy_info = struct('wait_node', [], 'resume_t', [], 'last_preconflict_t', [], ...
        'first_conflict_t', first_conflict_t, 'conflict_node', [], 'immediate_move', false);

    if strcmp(window_type, 'reserved_edge_swap') || ismember(classified_type, {'Head-on swap', 'Head-on meet'})
        if ~isempty(AGVs(loser_id).target_node)
            [replanned_path, goal_cost] = replan_avoiding_winner_window(AGVs, grid_map, loser_id, winner_id, current_t, first_conflict_t);
            if ~isempty(replanned_path) && isfinite(goal_cost) && ...
                    has_clear_first_step_for_breaker(AGVs, loser_id, winner_id, replanned_path)
                strategy_name = 'replan_original_target';
                if strcmp(classified_type, 'Head-on meet')
                    strategy_desc = 'head-on meet: loser replans first';
                else
                    strategy_desc = 'edge-swap: loser replans first';
                end
                yield_goal = [];
                return;
            end
        end

        [yield_success, yield_path, yield_goal] = plan_yield_path_like_event_sm(AGVs, grid_map, loser_id, winner_id);
        if yield_success
            strategy_name = 'yield_path';
            if strcmp(classified_type, 'Head-on meet')
                strategy_desc = 'head-on meet fallback: local yield';
            else
                strategy_desc = 'edge-swap fallback: local yield';
            end
            replanned_path = yield_path;
            return;
        end

        strategy_name = 'wait_only';
        if strcmp(classified_type, 'Head-on meet')
            strategy_desc = 'head-on meet fallback: stop and wait';
        else
            strategy_desc = 'edge-swap fallback: stop and wait';
        end
        yield_goal = [];
        return;
    end

    if strcmp(classified_type, 'Rear-end')
        if ~isempty(AGVs(loser_id).target_node)
            [replanned_path, goal_cost] = replan_avoiding_winner_window(AGVs, grid_map, loser_id, winner_id, current_t, first_conflict_t);
            if ~isempty(replanned_path) && isfinite(goal_cost)
                strategy_name = 'replan_original_target';
                strategy_desc = 'rear-end: faster follower overtakes via bypass';
                strategy_info.immediate_move = true;
                yield_goal = [];
                return;
            end
        end

        strategy_name = 'wait_only';
        strategy_desc = 'rear-end fallback: faster follower waits';
        yield_goal = [];
        return;
    end

    if strcmp(classified_type, 'Occupied node')
        if ~isempty(AGVs(loser_id).target_node)
            dynamic_map = grid_map;
            blocker_pos = AGVs(winner_id).pos;
            if ~isequal(blocker_pos, AGVs(loser_id).pos) && ~isequal(blocker_pos, AGVs(loser_id).target_node)
                dynamic_map(blocker_pos(1), blocker_pos(2)) = 1;
            end
            [replanned_path, goal_cost] = astar_planner_turn3(dynamic_map, AGVs(loser_id).pos, AGVs(loser_id).target_node, ...
                AGVs(loser_id).payload_weight, [], AGVs(loser_id).type);
            if ~isempty(replanned_path) && isfinite(goal_cost)
                strategy_name = 'replan_original_target';
                strategy_desc = 'occupied node: moving AGV replans around static blocker';
                yield_goal = [];
                return;
            end
        end

        strategy_name = 'wait_only';
        strategy_desc = 'occupied node fallback: stop and wait';
        yield_goal = [];
        return;
    end

    if strcmp(classified_type, 'Node contention') && window_detected && first_conflict_t >= current_t
        [wait_success, wait_node, resume_t, last_preconflict_t, conflict_node, replanned_path] = ...
            plan_wait_then_replan_like_event_sm(AGVs, grid_map, loser_id, winner_id, current_t, first_conflict_t);
        if wait_success
            strategy_name = 'wait_then_replan';
            strategy_desc = '冲突前一节点停车等待，窗口释放后重规划';
            yield_goal = wait_node;
            strategy_info.wait_node = wait_node;
            strategy_info.resume_t = resume_t;
            strategy_info.last_preconflict_t = last_preconflict_t;
            strategy_info.conflict_node = conflict_node;
            return;
        end
    end

    [yield_success, yield_path, yield_goal] = plan_yield_path_like_event_sm(AGVs, grid_map, loser_id, winner_id);
    if yield_success
        strategy_name = 'yield_path';
        strategy_desc = '让行避让到邻近安全格，不是超车';
        replanned_path = yield_path;
        return;
    end

    if ~isempty(AGVs(loser_id).target_node)
        [replanned_path, goal_cost] = astar_planner_turn3(grid_map, AGVs(loser_id).pos, AGVs(loser_id).target_node, ...
            AGVs(loser_id).payload_weight, [], AGVs(loser_id).type);
        if ~isempty(replanned_path) && isfinite(goal_cost)
            strategy_name = 'replan_original_target';
            strategy_desc = '原目标路径重规划';
            return;
        end
    end

    strategy_name = 'wait_only';
    strategy_desc = '停车等待';
end

function [replanned_path, goal_cost] = replan_avoiding_winner_window(AGVs, grid_map, loser_id, winner_id, current_t, first_conflict_t)
    replanned_path = [];
    goal_cost = inf;
    if isempty(AGVs(loser_id).target_node)
        return;
    end

    dynamic_map = grid_map;
    winner_pos = AGVs(winner_id).pos;
    if ~isequal(winner_pos, AGVs(loser_id).pos) && ~isequal(winner_pos, AGVs(loser_id).target_node)
        dynamic_map(winner_pos(1), winner_pos(2)) = 1;
    end
    horizon_t = current_t + 20;
    winner_events = build_agv_future_events_like_event_sm(AGVs(winner_id), current_t, horizon_t);
    for i = 1:numel(winner_events)
        evt = winner_events(i);
        if evt.t < first_conflict_t
            continue;
        end
        node = evt.to_node;
        if isequal(node, AGVs(loser_id).pos) || isequal(node, AGVs(loser_id).target_node)
            continue;
        end
        dynamic_map(node(1), node(2)) = 1;
    end

    [replanned_path, goal_cost] = astar_planner_turn3(dynamic_map, AGVs(loser_id).pos, AGVs(loser_id).target_node, ...
        AGVs(loser_id).payload_weight, [], AGVs(loser_id).type);
end

function [success, wait_node, resume_t, last_preconflict_t, conflict_node, replanned_path] = ...
    plan_wait_then_replan_like_event_sm(AGVs, grid_map, loser_id, winner_id, current_t, first_conflict_t)
    success = false;
    wait_node = [];
    resume_t = [];
    last_preconflict_t = current_t;
    conflict_node = [];
    replanned_path = [];

    loser_events = build_agv_future_events_like_event_sm(AGVs(loser_id), current_t, current_t + 200);
    blocker_events = build_agv_future_events_like_event_sm(AGVs(winner_id), current_t, current_t + 200);
    if isempty(loser_events)
        return;
    end

    conflict_idx = find([loser_events.t] == first_conflict_t, 1, 'first');
    if isempty(conflict_idx)
        return;
    end

    wait_node = loser_events(conflict_idx).from_node;
    conflict_node = loser_events(conflict_idx).to_node;
    if conflict_idx > 1
        last_preconflict_t = loser_events(conflict_idx - 1).t;
    end

    clear_t = first_conflict_t + max(1, AGVs(winner_id).step_dur);
    blocker_idx = find(arrayfun(@(evt) evt.t >= first_conflict_t && isequal(evt.to_node, conflict_node), blocker_events), 1, 'first');
    if ~isempty(blocker_idx)
        clear_t = blocker_events(blocker_idx).t + max(1, AGVs(winner_id).step_dur);
    end

    [replanned_path, goal_cost] = astar_planner_turn3(grid_map, wait_node, AGVs(loser_id).target_node, ...
        AGVs(loser_id).payload_weight, [], AGVs(loser_id).type);
    if isempty(replanned_path) || ~isfinite(goal_cost)
        return;
    end

    resume_t = clear_t;
    success = true;
end


function [success, best_path, best_goal] = plan_yield_path_like_event_sm(AGVs, grid_map, loser_id, winner_id)
    success = false;
    best_path = [];
    best_goal = [];

    curr_pos = AGVs(loser_id).pos;
    blocker_pos = AGVs(winner_id).pos;
    current_gap = norm(curr_pos - blocker_pos, 1);
    directions = [-1, 0; 1, 0; 0, -1; 0, 1];

    candidate_nodes = [];
    for d = 1:size(directions, 1)
        candidate = curr_pos + directions(d, :);
        if candidate(1) < 1 || candidate(1) > size(grid_map, 1) || candidate(2) < 1 || candidate(2) > size(grid_map, 2)
            continue;
        end
        if grid_map(candidate(1), candidate(2)) == 1
            continue;
        end
        candidate_nodes = [candidate_nodes; candidate]; %#ok<AGROW>
    end

    if isempty(candidate_nodes)
        return;
    end

    [~, unique_idx] = unique(candidate_nodes, 'rows', 'stable');
    candidate_nodes = candidate_nodes(unique_idx, :);
    candidate_gap = abs(candidate_nodes(:, 1) - blocker_pos(1)) + abs(candidate_nodes(:, 2) - blocker_pos(2));
    candidate_nodes = [candidate_nodes, candidate_gap];
    candidate_nodes = sortrows(candidate_nodes, -3);

    for i = 1:size(candidate_nodes, 1)
        candidate = candidate_nodes(i, 1:2);
        if isequal(candidate, curr_pos) || isequal(candidate, blocker_pos)
            continue;
        end
        if candidate_nodes(i, 3) < current_gap
            continue;
        end

        [candidate_path, goal_cost] = astar_planner_turn3(grid_map, curr_pos, candidate, ...
            AGVs(loser_id).payload_weight, [], AGVs(loser_id).type);
        if ~isempty(candidate_path) && isfinite(goal_cost)
            success = true;
            best_path = candidate_path;
            best_goal = candidate;
            return;
        end
    end
end

function plot_numbered_map(grid_map, cell_id_map, show_ids, output_png)
    style = agv_plot_theme();
    fig = figure('Color', 'w', 'Position', [80, 80, 900, 860], 'Name', 'Smallmap Cell Index');
    ax = axes(fig);
    hold(ax, 'on');

    imagesc(ax, [1 size(grid_map, 2)], [1 size(grid_map, 1)], grid_map);
    colormap(ax, [1 1 1; 0 0 0]);
    clim(ax, [0 1]);
    axis(ax, 'equal');
    axis(ax, [0.5, size(grid_map, 2) + 0.5, 0.5, size(grid_map, 1) + 0.5]);
    set(ax, 'YDir', 'reverse');
    set(ax, 'XTick', 1:size(grid_map, 2), 'YTick', 1:size(grid_map, 1), ...
        'LineWidth', 1.0, 'TickLength', [0 0], ...
        'FontName', style.cn_font, 'FontSize', 9);
    draw_cell_boundaries_local(ax, size(grid_map, 1), size(grid_map, 2), [0.62 0.62 0.62], 0.65);

    if show_ids
        for r = 1:size(grid_map, 1)
            for c = 1:size(grid_map, 2)
                text(ax, c, r, num2str(cell_id_map(r, c)), ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
                    'FontSize', 10,  'FontWeight', 'bold','Color',[0.35 0.35 0.35], 'Clipping', 'on');
            end
        end
    end

    xlabel(ax, 'Column', 'FontName', style.en_font);
    ylabel(ax, 'Row', 'FontName', style.en_font);

    exportgraphics(fig, output_png, 'Resolution', 220);
end

function plot_case_visualization(grid_map, ~, case_cfg, AGVs, ~, ~, ...
    ~, ~, ~, ~, ~, ~, ...
    ~, ~, yield_goal, replanned_path, output_png)
    style = agv_plot_theme();
    fig = figure('Color', 'w', 'Position', [120, 120, 980, 860], 'Name', ['Conflict Validation - ' case_cfg.name]);
    ax = axes(fig);
    hold(ax, 'on');

    imagesc(ax, [1 size(grid_map, 2)], [1 size(grid_map, 1)], grid_map);
    colormap(ax, [1 1 1; 0 0 0]);
    clim(ax, [0 1]);
    axis(ax, 'equal');
    axis(ax, [0.5, size(grid_map, 2) + 0.5, 0.5, size(grid_map, 1) + 0.5]);
    set(ax, 'YDir', 'reverse');
    set(ax, 'XTick', 1:size(grid_map, 2), 'YTick', 1:size(grid_map, 1), ...
        'LineWidth', 1.0, 'TickLength', [0 0], ...
        'FontName', style.cn_font, 'FontSize', 9);
    draw_cell_boundaries_local(ax, size(grid_map, 1), size(grid_map, 2), [0.62 0.62 0.62], 0.65);

    palette = lines(max(2, numel(AGVs)));
    for agv_id = 1:numel(AGVs)
        draw_agv_case(ax, AGVs(agv_id), palette(agv_id, :), sprintf('AGV-%d', AGVs(agv_id).display_id));
    end

    if ~isempty(yield_goal)
        scatter(ax, yield_goal(2), yield_goal(1), 90, 'p', 'filled', 'MarkerFaceColor', [0.49 0.18 0.56], ...
            'MarkerEdgeColor', 'k');
    end

    xlabel(ax, 'Column', 'FontName', style.en_font);
    ylabel(ax, 'Row', 'FontName', style.en_font);

    exportgraphics(fig, output_png, 'Resolution', 220);
end

function draw_agv_case(ax, agv, color_value, label_text)
    [plot_x, plot_y] = build_non_diagonal_polyline(agv.path(:, 1:2));
    plot(ax, plot_x, plot_y, '-', 'Color', color_value, 'LineWidth', 2.2);
    scatter(ax, agv.path(:, 2), agv.path(:, 1), 28, 'filled', 'MarkerFaceColor', color_value, 'MarkerEdgeColor', 'none');
    scatter(ax, agv.pos(2), agv.pos(1), 120, 'o', 'filled', 'MarkerFaceColor', color_value, 'MarkerEdgeColor', 'k');
    text(ax, agv.pos(2) + 0.2, agv.pos(1) - 0.2, label_text, 'Color', color_value, 'FontWeight', 'bold');
    if ~isempty(agv.target_node)
        scatter(ax, agv.target_node(2), agv.target_node(1), 70, 'd', 'filled', 'MarkerFaceColor', color_value, 'MarkerEdgeColor', 'k');
    end
end

function out = logical_str(tf)
    if tf
        out = 'true';
    else
        out = 'false';
    end
end

function case_timeline = build_case_timeline_rows(case_name, AGVs, cell_id_map, current_t, winner_id, loser_id, strategy_name, replanned_path, strategy_info)
    case_timeline = {};
    for agv_id = 1:numel(AGVs)
        role = 'winner';
        if agv_id == loser_id
            role = 'loser';
        elseif agv_id ~= winner_id
            role = 'peer';
        end

        [timeline_cells, timeline_times, state_tags] = build_agv_post_conflict_timeline( ...
            AGVs, agv_id, loser_id, strategy_name, replanned_path, current_t, strategy_info);
        for k = 1:numel(timeline_times)
            rc = timeline_cells(k, :);
            case_timeline(end + 1, :) = { ...
                case_name, AGVs(agv_id).display_id, role, timeline_times(k), ...
                cell_id_map(rc(1), rc(2)), rc(1), rc(2), state_tags{k}}; %#ok<AGROW>
        end
    end
end

function [timeline_cells, timeline_times, state_tags] = build_agv_post_conflict_timeline(AGVs, agv_id, loser_id, strategy_name, replanned_path, current_t, strategy_info)
    agv = AGVs(agv_id);
    timeline_cells = agv.pos;
    timeline_times = current_t;
    state_tags = {'current'};

    if agv_id == loser_id
        if strcmp(strategy_name, 'wait_then_replan') && ~isempty(strategy_info.wait_node)
            [timeline_cells, timeline_times, state_tags] = build_wait_then_replan_timeline( ...
                agv, replanned_path, current_t, strategy_info);
            return;
        elseif ismember(strategy_name, {'yield_path', 'replan_original_target'}) && ~isempty(replanned_path)
            candidate_path = normalize_path_four_connected(replanned_path, agv.payload_weight, agv.type);
            if size(candidate_path, 1) >= 2
                move_nodes = candidate_path(2:end, 1:2);
                for i = 1:size(move_nodes, 1)
                    timeline_cells(end + 1, :) = move_nodes(i, :); %#ok<AGROW>
                    timeline_times(end + 1, 1) = current_t + i * max(1, agv.step_dur); %#ok<AGROW>
                    state_tags{end + 1, 1} = strategy_name; %#ok<AGROW>
                end
            end
            return;
        elseif strcmp(strategy_name, 'wait_only')
            timeline_cells(end + 1, :) = agv.pos; %#ok<AGROW>
            timeline_times(end + 1, 1) = current_t + max(1, agv.step_dur); %#ok<AGROW>
            state_tags{end + 1, 1} = 'wait_only'; %#ok<AGROW>
            return;
        end
    end

    future_events = build_agv_future_events_like_event_sm(agv, current_t, current_t + 200);
    for i = 1:numel(future_events)
        timeline_cells(end + 1, :) = future_events(i).to_node; %#ok<AGROW>
        timeline_times(end + 1, 1) = display_event_time(future_events(i).t, agv.step_dur); %#ok<AGROW>
        state_tags{end + 1, 1} = 'planned'; %#ok<AGROW>
    end
end

function [timeline_cells, timeline_times, state_tags] = build_wait_then_replan_timeline(agv, replanned_path, current_t, strategy_info)
    timeline_cells = agv.pos;
    timeline_times = current_t;
    state_tags = {'current'};

    future_events = build_agv_future_events_like_event_sm(agv, current_t, current_t + 200);
    stop_added = isequal(agv.pos, strategy_info.wait_node);
    for i = 1:numel(future_events)
        evt = future_events(i);
        if evt.t >= strategy_info.first_conflict_t
            break;
        end
        timeline_cells(end + 1, :) = evt.to_node; %#ok<AGROW>
        timeline_times(end + 1, 1) = display_event_time(evt.t, agv.step_dur); %#ok<AGROW>
        state_tags{end + 1, 1} = 'planned'; %#ok<AGROW>
        if isequal(evt.to_node, strategy_info.wait_node)
            stop_added = true;
        end
    end

    if ~stop_added && ~isempty(strategy_info.wait_node)
        timeline_cells(end + 1, :) = strategy_info.wait_node; 
        timeline_times(end + 1, 1) = display_event_time(strategy_info.last_preconflict_t, agv.step_dur); %#ok<AGROW>
        state_tags{end + 1, 1} = 'planned'; %#ok<AGROW>
    end

    wait_step = max(1, agv.step_dur);
    wait_times = (display_event_time(strategy_info.last_preconflict_t, agv.step_dur) + wait_step):wait_step:(display_event_time(strategy_info.resume_t, agv.step_dur) - wait_step);
    for t = wait_times
        timeline_cells(end + 1, :) = strategy_info.wait_node; %#ok<AGROW>
        timeline_times(end + 1, 1) = t; %#ok<AGROW>
        state_tags{end + 1, 1} = 'wait_then_replan'; %#ok<AGROW>
    end

    if ~isempty(replanned_path) && size(replanned_path, 1) >= 2
        move_nodes = replanned_path(2:end, 1:2);
        for i = 1:size(move_nodes, 1)
            timeline_cells(end + 1, :) = move_nodes(i, :); %#ok<AGROW>
            timeline_times(end + 1, 1) = display_event_time(strategy_info.resume_t, agv.step_dur) + (i - 1) * wait_step; %#ok<AGROW>
            state_tags{end + 1, 1} = 'replan_after_wait'; %#ok<AGROW>
        end
    end
end

function t_disp = display_event_time(event_t, step_dur)
    t_disp = event_t + max(1, step_dur);
end

function print_case_timeline(case_name, case_timeline)
    fprintf('  time-node timeline after conflict handling:\n');
    agv_ids = unique(cell2mat(case_timeline(:, 2)));
    for i = 1:numel(agv_ids)
        agv_id = agv_ids(i);
        rows = case_timeline(cell2mat(case_timeline(:, 2)) == agv_id, :);
        parts = cell(size(rows, 1), 1);
        for k = 1:size(rows, 1)
            parts{k} = sprintf('t=%g->%d(%s)', rows{k, 4}, rows{k, 5}, rows{k, 8});
        end
        fprintf('    %s | AGV-%d: %s\n', case_name, agv_id, strjoin(parts, ' | '));
    end
end

function rc = rc_from_id(cell_id, cell_id_map)
    [r, c] = find(cell_id_map == cell_id, 1);
    if isempty(r)
        error('Cell ID %d is outside the current map.', cell_id);
    end
    rc = [r, c];
end

function path_rc = rc_path_from_ids(path_ids, cell_id_map)
    path_rc = zeros(numel(path_ids), 2);
    for i = 1:numel(path_ids)
        path_rc(i, :) = rc_from_id(path_ids(i), cell_id_map);
    end
end

function draw_cell_boundaries_local(ax, rows, cols, grid_color, line_width)
    x_vals = 0.5:1:(cols + 0.5);
    y_vals = 0.5:1:(rows + 0.5);

    for x = x_vals
        line(ax, [x x], [0.5 rows + 0.5], 'Color', grid_color, 'LineWidth', line_width, 'Clipping', 'on');
    end
    for y = y_vals
        line(ax, [0.5 cols + 0.5], [y y], 'Color', grid_color, 'LineWidth', line_width, 'Clipping', 'on');
    end
end

function display_id = parse_display_id_from_field(field_name, fallback_id)
    token = regexp(field_name, '^agv(\d+)$', 'tokens', 'once');
    if isempty(token)
        display_id = fallback_id;
    else
        display_id = str2double(token{1});
    end
end

function display_id = agv_display_id(AGVs, idx)
    if isempty(idx) || idx < 1 || idx > numel(AGVs) || ~isfield(AGVs, 'display_id') || isempty(AGVs(idx).display_id)
        display_id = idx;
    else
        display_id = AGVs(idx).display_id;
    end
end

function s = node_str_local(node)
    if isempty(node)
        s = '[]';
        return;
    end
    s = sprintf('[%d,%d]', node(1), node(2));
end
