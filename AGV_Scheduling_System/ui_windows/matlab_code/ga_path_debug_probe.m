function ga_path_debug_probe(task_list, depots, agv_types, agv_params, label)
%GA_PATH_DEBUG_PROBE Preflight path reachability probe for GA debugging.

    if nargin < 5 || isempty(label)
        label = 'unknown';
    end

    if isempty(task_list) || isempty(depots) || isempty(agv_types)
        fprintf('[PathProbe][%s] Empty input, skipping probe.\n', label);
        return;
    end

    fprintf('[PathProbe][%s] Starting depot-to-target reachability probe...\n', label);

    global costmap_type1 costmap_type2;
    if isempty(costmap_type1) || isempty(costmap_type2)
        init_global_costmaps();
    end

    target_ids = unique(task_list(:, 2))';
    for target_id = target_ids
        if target_id <= 12
            agv_type = 1;
        else
            agv_type = 2;
        end

        depot_index = find(agv_types == agv_type, 1, 'first');
        if isempty(depot_index)
            fprintf('[PathProbe][%s] Target %d has no AGV of type %d, skipped.\n', label, target_id, agv_type);
            continue;
        end

        depot_rc = depots(depot_index, :);
        task_rows = task_list(task_list(:, 2) == target_id, :);
        sample_weight = 0;
        if ~isempty(task_rows)
            sample_weight = task_rows(1, 3);
        end

        pickup_info = probe_segment(depot_rc, target_id, 'pickup', agv_type, 0);
        if pickup_info.reachable
            drop_start = pickup_info.best_rc;
        else
            drop_start = depot_rc;
        end
        drop_info = probe_segment(drop_start, target_id, 'dropoff', agv_type, sample_weight);

        fprintf('[PathProbe][%s][Target %d][Type %d] pickup from %s | candidates=%d | in_bounds=%d | free=%d | reachable=%d', ...
            label, target_id, agv_type, mat2str(depot_rc), pickup_info.total_candidates, ...
            pickup_info.in_bounds_candidates, pickup_info.free_candidates, pickup_info.reachable_candidates);
        if pickup_info.reachable
            fprintf(' | best_rc=%s | dist=%.1f\n', mat2str(pickup_info.best_rc), pickup_info.best_dist);
        else
            fprintf(' | reason=%s\n', pickup_info.failure_reason);
        end

        fprintf('[PathProbe][%s][Target %d][Type %d] dropoff from %s | candidates=%d | in_bounds=%d | free=%d | reachable=%d', ...
            label, target_id, agv_type, mat2str(drop_start), drop_info.total_candidates, ...
            drop_info.in_bounds_candidates, drop_info.free_candidates, drop_info.reachable_candidates);
        if drop_info.reachable
            fprintf(' | best_rc=%s | dist=%.1f\n', mat2str(drop_info.best_rc), drop_info.best_dist);
        else
            fprintf(' | reason=%s\n', drop_info.failure_reason);
        end
    end

    fprintf('[PathProbe][%s] Probe finished.\n', label);
end

function info = probe_segment(curr_pos, target_id, phase, agv_type, payload_weight)
    [cost_map, map_rows, map_cols] = get_probe_costmap(agv_type);
    planning_map = create_binary_grid_map(map_cols - 1, map_rows - 1, target_id);
    candidates = get_probe_candidates(target_id, phase);

    info = struct();
    info.reachable = false;
    info.best_rc = [];
    info.best_dist = inf;
    info.best_cost = inf;
    info.total_candidates = size(candidates, 1);
    info.in_bounds_candidates = 0;
    info.free_candidates = 0;
    info.reachable_candidates = 0;
    info.failure_reason = 'unknown';

    if curr_pos(1) < 1 || curr_pos(1) > map_rows || curr_pos(2) < 1 || curr_pos(2) > map_cols
        info.failure_reason = sprintf('start out of bounds %s / map [%d,%d]', mat2str(curr_pos), map_rows, map_cols);
        return;
    end

    eval_map = planning_map;
    eval_map(curr_pos(1), curr_pos(2)) = 0;

    for i = 1:size(candidates, 1)
        candidate = candidates(i, :);
        if candidate(1) < 1 || candidate(1) > map_rows || candidate(2) < 1 || candidate(2) > map_cols
            continue;
        end

        info.in_bounds_candidates = info.in_bounds_candidates + 1;
        if planning_map(candidate(1), candidate(2)) == 1
            continue;
        end

        info.free_candidates = info.free_candidates + 1;
        [path, g_cost, ~, ~, path_length] = astar_planner_turn3(eval_map, curr_pos, candidate, payload_weight, cost_map, agv_type);
        if isempty(path) || ~isfinite(g_cost)
            continue;
        end

        info.reachable_candidates = info.reachable_candidates + 1;
        segment_dist = max(path_length - 1, 0);
        if (g_cost < info.best_cost - 1e-9) || ...
           (abs(g_cost - info.best_cost) <= 1e-9 && segment_dist < info.best_dist) || ...
           (abs(g_cost - info.best_cost) <= 1e-9 && abs(segment_dist - info.best_dist) <= 1e-9 && isempty(info.best_rc))
            info.best_rc = candidate;
            info.best_dist = segment_dist;
            info.best_cost = g_cost;
            info.reachable = true;
        end
    end

    if info.reachable
        info.failure_reason = '';
    elseif info.free_candidates == 0
        info.failure_reason = 'all target candidates are blocked by the planning map';
    elseif info.reachable_candidates == 0
        info.failure_reason = 'free candidates exist, but A* cannot reach them';
    end
end

function candidates = get_probe_candidates(target_id, phase)
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

function [cost_map, map_rows, map_cols] = get_probe_costmap(agv_type)
    global costmap_type1 costmap_type2;
    if agv_type == 1
        cost_map = costmap_type1;
    else
        cost_map = costmap_type2;
    end
    [map_rows, map_cols] = size(cost_map);
end

