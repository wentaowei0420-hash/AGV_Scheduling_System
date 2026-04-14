function print_conflict_validation_case_log(case_idx, case_cfg, result, case_log_path)
fid = fopen(case_log_path, 'w');
if fid < 0
    error('Cannot open case log file for writing: %s', case_log_path);
end
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

display_ids = get_result_display_ids(result);

emit('');
emit(sprintf('[Case %d] %s', case_idx, case_cfg.name));

agv_fields = fieldnames(case_cfg);
agv_fields = agv_fields(startsWith(agv_fields, 'agv'));
active_idx = 0;
for i = 1:numel(agv_fields)
    agv_data = case_cfg.(agv_fields{i});
    if isempty(agv_data)
        continue;
    end
    active_idx = active_idx + 1;
    emit(sprintf('  AGV-%d: start=%d | via=[%s] | end=%d | step_dur=%.2f', ...
        display_ids(active_idx), agv_data.start_id, num2str(agv_data.via_ids), agv_data.end_id, result.AGVs(active_idx).step_dur));
end

emit(sprintf('  expected=%s | runtime_detected=%d | runtime_blocker=%d | classified=%s', ...
    case_cfg.expected_type, result.runtime_detected, map_display_id(result.runtime_blocker, display_ids), result.classified_type));
emit(sprintf('  event_window: detected=%d | blocker=%d | type=%s | first_t=%g', ...
    result.window_detected, map_display_id(result.window_blocker, display_ids), result.window_type, result.first_conflict_t));

if ~isempty(result.first_priority_snapshot_str)
    emit(sprintf('  priority_first_decision[t=%g]: %s', result.first_decision_t, result.first_priority_snapshot_str));
end
if isfield(result, 'first_priority_pairwise_str') && ~isempty(result.first_priority_pairwise_str)
    emit(sprintf('  pairwise_first_decision[t=%g]: %s', result.first_decision_t, result.first_priority_pairwise_str));
end
if ~isempty(result.priority_snapshot_str)
    emit(sprintf('  priority_latest_decision[t=%g]: %s', result.priority_snapshot_t, result.priority_snapshot_str));
end
if isfield(result, 'priority_pairwise_str') && ~isempty(result.priority_pairwise_str)
    emit(sprintf('  pairwise_latest_decision[t=%g]: %s', result.priority_snapshot_t, result.priority_pairwise_str));
end

emit(sprintf('  winner=AGV-%d | loser=AGV-%d', ...
    map_display_id(result.winner_id, display_ids), map_display_id(result.loser_id, display_ids)));
emit(sprintf('  strategy=%s | %s', result.strategy_name, result.strategy_desc));
if ~isempty(result.yield_goal)
    emit(sprintf('  yield_goal=%s', node_str_for_log(result.yield_goal)));
end

if isfield(result, 'conflict_history') && ~isempty(result.conflict_history)
    emit('  detailed_conflict_history:');
    for i = 1:numel(result.conflict_history)
        entry = result.conflict_history(i);
        emit(sprintf('    conflict #%d', i));
        emit(sprintf('      detected_at_t=%g | predicted_conflict_t=%g | lead_time=%g', ...
            entry.detection_t, entry.predicted_conflict_t, entry.predicted_conflict_t - entry.detection_t));
        emit(sprintf('      self=AGV-%d | blocker=AGV-%d | source=%s | window_type=%s | classified=%s', ...
            map_display_id(entry.self_id, display_ids), map_display_id(entry.blocker_id, display_ids), ...
            entry.conflict_source, entry.window_type, entry.classified_type));
        emit(sprintf('      self_state=%s | self_pos=%s | self_next=%s', ...
            entry.self_status, node_str_for_log(entry.self_pos), node_str_for_log(entry.self_next)));
        emit(sprintf('      blocker_state=%s | blocker_pos=%s | blocker_next=%s', ...
            entry.blocker_status, node_str_for_log(entry.blocker_pos), node_str_for_log(entry.blocker_next)));
        emit(sprintf('      conflict_node=%s', node_str_for_log(entry.conflict_node)));
        emit(sprintf('      priority(self)=%.3f | priority(blocker)=%.3f | winner=AGV-%d | loser=AGV-%d', ...
            entry.priority_a, entry.priority_b, map_display_id(entry.winner_id, display_ids), map_display_id(entry.loser_id, display_ids)));
        emit(sprintf('      reason=%s', entry.reason));
        emit(sprintf('      resolution=%s | %s', entry.strategy_name, entry.strategy_desc));
        if ~isempty(entry.yield_goal)
            emit(sprintf('      yield_goal=%s', node_str_for_log(entry.yield_goal)));
        end
        if ~isempty(entry.replanned_path)
            emit(sprintf('      replanned_path=%s', path_str_for_log(entry.replanned_path)));
        else
            emit('      replanned_path=[]');
        end
    end
else
    emit('  detailed_conflict_history: none');
end

if isfield(result, 'debug_logs') && ~isempty(result.debug_logs)
    emit('  debug_logs:');
    for i = 1:numel(result.debug_logs)
        emit(result.debug_logs{i});
    end
end

print_timeline(result.timeline_rows, case_cfg.name);

    function emit(line)
        fprintf('%s\n', line);
        fprintf(fid, '%s\n', line);
    end

    function print_timeline(case_timeline, case_name)
        emit('  time-node timeline after conflict handling:');
        if isempty(case_timeline)
            emit(sprintf('    %s | <empty>', case_name));
            return;
        end
        agv_ids = unique(cell2mat(case_timeline(:, 2)));
        for ii = 1:numel(agv_ids)
            agv_id = agv_ids(ii);
            rows = case_timeline(cell2mat(case_timeline(:, 2)) == agv_id, :);
            parts = cell(size(rows, 1), 1);
            for kk = 1:size(rows, 1)
                parts{kk} = sprintf('t=%g->%d(%s)', rows{kk, 4}, rows{kk, 5}, rows{kk, 8});
            end
            emit(sprintf('    %s | AGV-%d: %s', case_name, agv_id, strjoin(parts, ' | ')));
        end
    end
end

function display_ids = get_result_display_ids(result)
if isfield(result, 'display_ids') && ~isempty(result.display_ids)
    display_ids = result.display_ids;
elseif isfield(result, 'AGVs') && ~isempty(result.AGVs) && isfield(result.AGVs, 'display_id')
    display_ids = arrayfun(@(agv) agv.display_id, result.AGVs);
else
    display_ids = 1:numel(result.AGVs);
end
end

function display_id = map_display_id(internal_id, display_ids)
if isempty(internal_id) || internal_id <= 0 || internal_id > numel(display_ids)
    display_id = internal_id;
else
    display_id = display_ids(internal_id);
end
end

function s = node_str_for_log(node)
if isempty(node)
    s = '[]';
    return;
end
s = sprintf('[%d,%d]', node(1), node(2));
end

function s = path_str_for_log(path_rc)
if isempty(path_rc)
    s = '[]';
    return;
end
max_show = min(size(path_rc, 1), 8);
parts = cell(1, max_show);
for i = 1:max_show
    parts{i} = node_str_for_log(path_rc(i, 1:2));
end
if size(path_rc, 1) > max_show
    parts{end + 1} = sprintf('... (%d nodes)', size(path_rc, 1)); %#ok<AGROW>
end
s = strjoin(parts, ' -> ');
end
