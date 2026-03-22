function varargout = region_distance_oracle(action, varargin)
% REGION_DISTANCE_ORACLE
% ---------------------------------------------------------------
% A region-distance precomputation utility for GA fitness evaluation.
%
% Motivation:
%   The current GA repeatedly calls A* for many candidate target cells.
%   This file implements the "direction 1" idea discussed in the project:
%   build a precomputed cost field for each fixed target region, then
%   estimate path cost by table lookup instead of repeated forward A*.
%
% Design:
%   1) For each AGV type + target region + phase, build one reverse
%      multi-source shortest-path field on the static map.
%   2) The field stores:
%        - minimum travel cost from any grid cell to the region
%        - minimum hop count (grid distance)
%        - best target cell inside the region
%   3) During GA evaluation, query by current position:
%        [best_rc, best_dist, best_cost, feasible] =
%            region_distance_oracle('query', oracle, curr_pos, target_id, phase, agv_type)
%
% Notes:
%   - This method is intended for GA fitness evaluation on a mostly static
%     map, not for the execution loop with dynamic conflicts.
%   - To keep precomputation efficient, this version models static travel
%     cost using the same obstacle map and terrain costmap as the execution
%     layer, but does not explicitly model direction-state turn penalties.
%   - A practical hybrid strategy is:
%        * GA stage: use this oracle for fast cost estimation
%        * Final refinement: run exact A* on elite solutions if needed
%
% Supported actions:
%   oracle = region_distance_oracle('build')
%   oracle = region_distance_oracle('build', optionsStruct)
%   [best_rc, best_dist, best_cost, feasible] =
%       region_distance_oracle('query', oracle, curr_pos, target_id, phase, agv_type)
%
% Recommended integration:
%   Replace repeated calls to get_best_astar_segment(...) in the GA with
%   a call to this oracle.
% ---------------------------------------------------------------

    switch lower(action)
        case 'build'
            if nargin >= 2
                options = varargin{1};
            else
                options = struct();
            end
            varargout{1} = build_oracle(options);

        case 'query'
            [best_rc, best_dist, best_cost, feasible] = query_oracle(varargin{:});
            varargout = {best_rc, best_dist, best_cost, feasible};

        otherwise
            error('region_distance_oracle:UnknownAction', ...
                'Unsupported action "%s". Use "build" or "query".', action);
    end
end

function oracle = build_oracle(options)
    if nargin < 1 || isempty(options)
        options = struct();
    end

    if ~isfield(options, 'agv_types')
        options.agv_types = [1, 2];
    end
    if ~isfield(options, 'task_target_ids')
        options.task_target_ids = 1:16;
    end
    if ~isfield(options, 'include_charge_regions')
        options.include_charge_regions = true;
    end

    field_map = containers.Map('KeyType', 'char', 'ValueType', 'any');

    for agv_type = options.agv_types
        task_target_ids = options.task_target_ids;
        for target_id = task_target_ids
            field_map = build_single_field_into_map(field_map, agv_type, target_id, 'pickup');
            field_map = build_single_field_into_map(field_map, agv_type, target_id, 'dropoff');
        end

        if options.include_charge_regions
            charge_target_id = get_charge_target_id(agv_type);
            field_map = build_single_field_into_map(field_map, agv_type, charge_target_id, 'charge');
        end
    end

    oracle = struct();
    oracle.mode = 'region_distance_precompute';
    oracle.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    oracle.field_map = field_map;
    oracle.options = options;
    oracle.notes = [
        "Static region-distance oracle for GA evaluation";
        "Uses reverse multi-source shortest-path search";
        "Same obstacle map and terrain costmap as GA/execution static layer";
        "Turn-state penalty is not explicitly modeled in the field"
    ];
end

function field_map = build_single_field_into_map(field_map, agv_type, target_id, phase)
    key = build_field_key(agv_type, target_id, phase);
    if isKey(field_map, key)
        return;
    end

    [cost_map, map_rows, map_cols] = get_ga_costmap_local(agv_type);
    planning_map = create_binary_grid_map(map_cols - 1, map_rows - 1, target_id);
    candidates = get_region_candidates(target_id, phase, agv_type);
    candidates = filter_valid_candidates(candidates, planning_map);

    if isempty(candidates)
        field = make_empty_field(agv_type, target_id, phase, planning_map, cost_map, candidates);
        field_map(key) = field;
        return;
    end

    [cost_field, step_field, best_r_field, best_c_field] = ...
        run_reverse_multi_source_search(planning_map, cost_map, candidates);

    field = struct();
    field.agv_type = agv_type;
    field.target_id = target_id;
    field.phase = phase;
    field.planning_map = planning_map;
    field.cost_map = cost_map;
    field.candidates = candidates;
    field.cost_field = cost_field;
    field.step_field = step_field;
    field.best_r_field = best_r_field;
    field.best_c_field = best_c_field;

    field_map(key) = field;
end

function [best_rc, best_dist, best_cost, feasible] = query_oracle(oracle, curr_pos, target_id, phase, agv_type)
    key = build_field_key(agv_type, target_id, phase);
    if ~isfield(oracle, 'field_map') || ~isKey(oracle.field_map, key)
        best_rc = [];
        best_dist = inf;
        best_cost = inf;
        feasible = false;
        return;
    end

    field = oracle.field_map(key);
    [rows, cols] = size(field.cost_field);

    if curr_pos(1) < 1 || curr_pos(1) > rows || curr_pos(2) < 1 || curr_pos(2) > cols
        best_rc = [];
        best_dist = inf;
        best_cost = inf;
        feasible = false;
        return;
    end

    best_cost = field.cost_field(curr_pos(1), curr_pos(2));
    best_dist = field.step_field(curr_pos(1), curr_pos(2));
    best_r = field.best_r_field(curr_pos(1), curr_pos(2));
    best_c = field.best_c_field(curr_pos(1), curr_pos(2));

    feasible = isfinite(best_cost) && best_r > 0 && best_c > 0;
    if feasible
        best_rc = [best_r, best_c];
    else
        best_rc = [];
        best_dist = inf;
        best_cost = inf;
    end
end

function [cost_field, step_field, best_r_field, best_c_field] = ...
    run_reverse_multi_source_search(planning_map, cost_map, candidates)

    [rows, cols] = size(planning_map);
    cost_field = inf(rows, cols);
    step_field = inf(rows, cols);
    best_r_field = zeros(rows, cols);
    best_c_field = zeros(rows, cols);

    open_r = zeros(0, 1);
    open_c = zeros(0, 1);
    open_cost = zeros(0, 1);
    open_steps = zeros(0, 1);
    open_src_r = zeros(0, 1);
    open_src_c = zeros(0, 1);

    for i = 1:size(candidates, 1)
        r = candidates(i, 1);
        c = candidates(i, 2);
        cost_field(r, c) = 0;
        step_field(r, c) = 0;
        best_r_field(r, c) = r;
        best_c_field(r, c) = c;

        open_r(end + 1, 1) = r; %#ok<AGROW>
        open_c(end + 1, 1) = c; %#ok<AGROW>
        open_cost(end + 1, 1) = 0; %#ok<AGROW>
        open_steps(end + 1, 1) = 0; %#ok<AGROW>
        open_src_r(end + 1, 1) = r; %#ok<AGROW>
        open_src_c(end + 1, 1) = c; %#ok<AGROW>
    end

    dir_vecs = [-1, 0; 1, 0; 0, -1; 0, 1];

    while ~isempty(open_cost)
        [~, idx] = min(open_cost);
        curr_r = open_r(idx);
        curr_c = open_c(idx);
        curr_cost = open_cost(idx);
        curr_steps = open_steps(idx);
        curr_src_r = open_src_r(idx);
        curr_src_c = open_src_c(idx);

        open_r(idx) = [];
        open_c(idx) = [];
        open_cost(idx) = [];
        open_steps(idx) = [];
        open_src_r(idx) = [];
        open_src_c(idx) = [];

        if curr_cost > cost_field(curr_r, curr_c) + 1e-9
            continue;
        end
        if abs(curr_cost - cost_field(curr_r, curr_c)) <= 1e-9 && curr_steps > step_field(curr_r, curr_c)
            continue;
        end

        for d = 1:4
            nr = curr_r + dir_vecs(d, 1);
            nc = curr_c + dir_vecs(d, 2);

            if nr < 1 || nr > rows || nc < 1 || nc > cols
                continue;
            end
            if planning_map(nr, nc) == 1
                continue;
            end

            move_cost = cost_map(nr, nc);
            tentative_cost = curr_cost + move_cost;
            tentative_steps = curr_steps + 1;

            should_update = false;
            if tentative_cost < cost_field(nr, nc) - 1e-9
                should_update = true;
            elseif abs(tentative_cost - cost_field(nr, nc)) <= 1e-9 && tentative_steps < step_field(nr, nc)
                should_update = true;
            elseif abs(tentative_cost - cost_field(nr, nc)) <= 1e-9 && ...
                   tentative_steps == step_field(nr, nc) && ...
                   lexicographically_smaller(curr_src_r, curr_src_c, best_r_field(nr, nc), best_c_field(nr, nc))
                should_update = true;
            end

            if should_update
                cost_field(nr, nc) = tentative_cost;
                step_field(nr, nc) = tentative_steps;
                best_r_field(nr, nc) = curr_src_r;
                best_c_field(nr, nc) = curr_src_c;

                open_r(end + 1, 1) = nr; %#ok<AGROW>
                open_c(end + 1, 1) = nc; %#ok<AGROW>
                open_cost(end + 1, 1) = tentative_cost; %#ok<AGROW>
                open_steps(end + 1, 1) = tentative_steps; %#ok<AGROW>
                open_src_r(end + 1, 1) = curr_src_r; %#ok<AGROW>
                open_src_c(end + 1, 1) = curr_src_c; %#ok<AGROW>
            end
        end
    end
end

function tf = lexicographically_smaller(r1, c1, r2, c2)
    if r2 == 0 && c2 == 0
        tf = true;
        return;
    end
    tf = (r1 < r2) || (r1 == r2 && c1 < c2);
end

function field = make_empty_field(agv_type, target_id, phase, planning_map, cost_map, candidates)
    [rows, cols] = size(planning_map);
    field = struct();
    field.agv_type = agv_type;
    field.target_id = target_id;
    field.phase = phase;
    field.planning_map = planning_map;
    field.cost_map = cost_map;
    field.candidates = candidates;
    field.cost_field = inf(rows, cols);
    field.step_field = inf(rows, cols);
    field.best_r_field = zeros(rows, cols);
    field.best_c_field = zeros(rows, cols);
end

function key = build_field_key(agv_type, target_id, phase)
    key = sprintf('%d|%d|%s', agv_type, target_id, lower(phase));
end

function candidates = filter_valid_candidates(candidates, planning_map)
    if isempty(candidates)
        return;
    end

    [rows, cols] = size(planning_map);
    keep_mask = false(size(candidates, 1), 1);
    for i = 1:size(candidates, 1)
        r = candidates(i, 1);
        c = candidates(i, 2);
        if r >= 1 && r <= rows && c >= 1 && c <= cols && planning_map(r, c) == 0
            keep_mask(i) = true;
        end
    end
    candidates = candidates(keep_mask, :);
end

function [cost_map, map_rows, map_cols] = get_ga_costmap_local(agv_type)
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

function charge_target_id = get_charge_target_id(agv_type)
    if agv_type == 1
        charge_target_id = 17;
    else
        charge_target_id = 18;
    end
end

function candidates = get_region_candidates(target_id, phase, agv_type)
    phase = lower(phase);
    switch phase
        case 'pickup'
            [pickup_anchor, ~, pickup_size, ~] = get_task_coordinates(target_id);
            candidates = expand_anchor_area(pickup_anchor, pickup_size);

        case 'dropoff'
            [~, dropoff_anchor, ~, dropoff_size] = get_task_coordinates(target_id);
            candidates = expand_anchor_area(dropoff_anchor, dropoff_size);

        case 'charge'
            if agv_type == 1
                candidates = xy2rc([2, 2; 2, 3; 3, 2; 3, 3]);
            else
                candidates = xy2rc([39, 2]);
            end

        otherwise
            error('region_distance_oracle:UnknownPhase', ...
                'Unsupported phase "%s". Use pickup, dropoff, or charge.', phase);
    end
end

function candidates = expand_anchor_area(anchor, area_size)
    rows = anchor(1):(anchor(1) + area_size(1) - 1);
    cols = anchor(2):(anchor(2) + area_size(2) - 1);
    [grid_cols, grid_rows] = meshgrid(cols, rows);
    candidates = [grid_rows(:), grid_cols(:)];
end
