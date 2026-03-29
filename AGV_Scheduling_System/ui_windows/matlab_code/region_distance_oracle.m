function varargout = region_distance_oracle(action, varargin)
    persistent oracle_cache
    global region_distance_cache

    if nargin < 1 || isempty(action)
        error('region_distance_oracle:MissingAction', ...
            'Action is required. Use "build", "query", or "clearcache".');
    end

    switch lower(action)
        case 'build'
            if nargin >= 2
                options = varargin{1};
            else
                options = struct();
            end
            options = normalize_build_options(options);
            cache_meta = build_cache_meta(options);
            oracle = [];

            if ~options.force_rebuild && options.use_persistent_cache && is_valid_cached_oracle(oracle_cache, cache_meta)
                oracle = oracle_cache;
                oracle.cache_source = 'persistent';
            end

            if isempty(oracle) && ~options.force_rebuild && options.use_global_cache && is_valid_cached_oracle(region_distance_cache, cache_meta)
                oracle = region_distance_cache;
                oracle.cache_source = 'global';
            end

            if isempty(oracle) && ~options.force_rebuild && options.use_disk_cache
                [oracle_from_disk, loaded] = try_load_oracle_from_disk(options.cache_file, cache_meta);
                if loaded
                    oracle = oracle_from_disk;
                    oracle.cache_source = 'disk';
                end
            end

            if isempty(oracle)
                oracle = build_oracle(options);
                oracle.cache_meta = cache_meta;
                oracle.cache_source = 'built';

                if options.use_disk_cache
                    try_save_oracle_to_disk(options.cache_file, oracle);
                end
            end

            if options.use_persistent_cache
                oracle_cache = oracle;
            end
            if options.use_global_cache
                region_distance_cache = oracle;
            end

            varargout{1} = oracle;

        case 'query'
            [best_rc, best_dist, best_cost, feasible] = query_oracle(varargin{:});
            varargout = {best_rc, best_dist, best_cost, feasible};

        case 'clearcache'
            clear options;
            if nargin >= 2
                options = varargin{1};
            else
                options = struct();
            end
            options = normalize_build_options(options);
            oracle_cache = [];
            region_distance_cache = [];
            if options.clear_disk_cache && exist(options.cache_file, 'file') == 2
                delete(options.cache_file);
            end
            varargout{1} = true;

        otherwise
            error('region_distance_oracle:UnknownAction', ...
                'Unsupported action "%s". Use "build", "query", or "clearcache".', action);
    end
end

function oracle = build_oracle(options)
    options = normalize_build_options(options);

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
    oracle.schema_version = 2;
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

function options = normalize_build_options(options)
    if nargin < 1 || isempty(options)
        options = struct();
    end

    normalized = struct();

    if isfield(options, 'agv_types') && ~isempty(options.agv_types)
        normalized.agv_types = reshape(options.agv_types, 1, []);
    else
        normalized.agv_types = [1, 2];
    end

    if isfield(options, 'task_target_ids') && ~isempty(options.task_target_ids)
        normalized.task_target_ids = reshape(options.task_target_ids, 1, []);
    else
        normalized.task_target_ids = 1:16;
    end

    if isfield(options, 'include_charge_regions')
        normalized.include_charge_regions = logical(options.include_charge_regions);
    else
        normalized.include_charge_regions = true;
    end

    if isfield(options, 'use_persistent_cache')
        normalized.use_persistent_cache = logical(options.use_persistent_cache);
    else
        normalized.use_persistent_cache = true;
    end

    if isfield(options, 'use_global_cache')
        normalized.use_global_cache = logical(options.use_global_cache);
    else
        normalized.use_global_cache = true;
    end

    if isfield(options, 'use_disk_cache')
        normalized.use_disk_cache = logical(options.use_disk_cache);
    else
        normalized.use_disk_cache = true;
    end

    if isfield(options, 'force_rebuild')
        normalized.force_rebuild = logical(options.force_rebuild);
    else
        normalized.force_rebuild = false;
    end

    if isfield(options, 'clear_disk_cache')
        normalized.clear_disk_cache = logical(options.clear_disk_cache);
    else
        normalized.clear_disk_cache = true;
    end

    if isfield(options, 'cache_file') && ~isempty(options.cache_file)
        normalized.cache_file = options.cache_file;
    else
        normalized.cache_file = default_cache_file();
    end

    options = normalized;
end

function cache_meta = build_cache_meta(options)
    global mapW mapH;
    global costmap_type1 costmap_type2;

    if isempty(costmap_type1) || isempty(costmap_type2)
        init_global_costmaps();
    end

    cache_meta = struct();
    cache_meta.oracle_schema_version = 2;
    cache_meta.mapW = mapW;
    cache_meta.mapH = mapH;
    cache_meta.options = struct( ...
        'agv_types', options.agv_types, ...
        'task_target_ids', options.task_target_ids, ...
        'include_charge_regions', options.include_charge_regions);
    cache_meta.costmap_type1 = costmap_type1;
    cache_meta.costmap_type2 = costmap_type2;
end

function tf = is_valid_cached_oracle(oracle, expected_meta)
    tf = false;
    if isempty(oracle) || ~isstruct(oracle) || ~isfield(oracle, 'cache_meta')
        return;
    end
    if ~isfield(oracle, 'field_map')
        return;
    end
    tf = isequaln(oracle.cache_meta, expected_meta);
end

function [oracle, loaded] = try_load_oracle_from_disk(cache_file, expected_meta)
    oracle = [];
    loaded = false;

    if exist(cache_file, 'file') ~= 2
        return;
    end

    try
        payload = load(cache_file, 'oracle');
    catch
        return;
    end

    if ~isfield(payload, 'oracle')
        return;
    end

    oracle = payload.oracle;
    loaded = is_valid_cached_oracle(oracle, expected_meta);
    if ~loaded
        oracle = [];
    end
end

function try_save_oracle_to_disk(cache_file, oracle)
    try
        cache_dir = fileparts(cache_file);
        if ~isempty(cache_dir) && exist(cache_dir, 'dir') ~= 7
            mkdir(cache_dir);
        end
        save(cache_file, 'oracle', '-v7.3');
    catch ME
        warning('region_distance_oracle:DiskCacheSaveFailed', ...
            'Failed to save disk cache: %s', ME.message);
    end
end

function cache_file = default_cache_file()
    cache_file = fullfile(fileparts(mfilename('fullpath')), 'region_distance_oracle_cache.mat');
end

function field_map = build_single_field_into_map(field_map, agv_type, target_id, phase)
    key = build_field_key(agv_type, target_id, phase);
    if isKey(field_map, key)
        return;
    end

    [cost_map, map_rows, map_cols] = get_ga_costmap_local(agv_type);
    planning_map = create_binary_grid_map(map_cols - 1, map_rows - 1, target_id);
    candidates = get_region_candidates(target_id, phase, agv_type);
    candidates = normalize_candidates(candidates);
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

    candidates = normalize_candidates(candidates);
    if isempty(candidates)
        return;
    end

    for i = 1:size(candidates, 1)
        r = candidates(i, 1);
        c = candidates(i, 2);
        if ~is_valid_grid_index(r, c, rows, cols)
            continue;
        end
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

        if ~is_valid_grid_index(curr_r, curr_c, rows, cols)
            continue;
        end
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
            if ~isfinite(move_cost)
                continue;
            end
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
    candidates = normalize_candidates(candidates);
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

function candidates = normalize_candidates(candidates)
    if isempty(candidates)
        candidates = zeros(0, 2);
        return;
    end

    if isvector(candidates) && numel(candidates) == 2
        candidates = reshape(candidates, 1, 2);
    end

    if size(candidates, 2) ~= 2
        error('region_distance_oracle:InvalidCandidates', ...
            'Candidates must be an N-by-2 matrix of [row, col] coordinates.');
    end

    candidates = double(candidates);
    finite_mask = all(isfinite(candidates), 2);
    candidates = candidates(finite_mask, :);

    if isempty(candidates)
        candidates = zeros(0, 2);
        return;
    end

    candidates = round(candidates);
    candidates = unique(candidates, 'rows', 'stable');
end

function tf = is_valid_grid_index(r, c, rows, cols)
    tf = isfinite(r) && isfinite(c) && ...
         r >= 1 && r <= rows && c >= 1 && c <= cols && ...
         abs(r - round(r)) <= 1e-9 && abs(c - round(c)) <= 1e-9;
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
