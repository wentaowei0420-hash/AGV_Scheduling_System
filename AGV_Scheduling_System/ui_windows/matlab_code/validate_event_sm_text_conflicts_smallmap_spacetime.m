clear;
clc;
close all;

cfg.source_output_dir = '';
cfg.use_latest_source = true;
cfg.save_figures = true;
cfg.show_figures = true;

base_dir = fileparts(mfilename('fullpath'));
source_output_dir = resolve_validation_source_dir(base_dir, cfg.source_output_dir, cfg.use_latest_source);
result_bundle_path = fullfile(source_output_dir, 'conflict_validation_case_results.mat');
if ~exist(result_bundle_path, 'file')
    error(['Missing ', result_bundle_path, '. Please run validate_event_sm_text_conflicts_smallmap first.']);
end

S = load(result_bundle_path, 'cfg', 'grid_map', 'cell_id_map', 'cases', 'case_results', 'summary_rows', 'timeline_rows');
if ~isfield(S, 'case_results') || isempty(S.case_results)
    error('The loaded validation bundle does not contain case_results. Please rerun validate_event_sm_text_conflicts_smallmap.');
end

timestamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
output_dir = fullfile(base_dir, 'experiment_outputs', ['conflict_validation_spacetime_' timestamp]);
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

source_info = struct('source_output_dir', source_output_dir, 'result_bundle_path', result_bundle_path); %#ok<NASGU>
save(fullfile(output_dir, 'spacetime_plot_source.mat'), 'source_info');

fprintf('>> Spacetime plots from validate_event_sm_text_conflicts_smallmap results\n');
fprintf('>> Source output directory: %s\n', source_output_dir);
fprintf('>> Output directory: %s\n', output_dir);

old_figs = findall(0, 'Type', 'figure', '-regexp', 'Name', '^Spacetime - ');
if ~isempty(old_figs)
    close(old_figs);
end

for case_idx = 1:numel(S.case_results)
    case_entry = S.case_results{case_idx};
    if isempty(case_entry)
        continue;
    end
    case_cfg = case_entry.case_cfg;
    result = case_entry.result;
    case_log_path = fullfile(output_dir, sprintf('case_%02d_%s_log.txt', case_idx, case_cfg.name));
    print_conflict_validation_case_log(case_idx, case_cfg, result, case_log_path);
    case_png = fullfile(output_dir, sprintf('case_%02d_%s_spacetime.png', case_idx, case_cfg.name));
    plot_case_spacetime(S.grid_map, case_cfg, result, case_png, cfg.show_figures, cfg.save_figures);
end

fprintf('\n>> Spacetime plotting finished.\n');

function source_output_dir = resolve_validation_source_dir(base_dir, configured_dir, use_latest)
    if ~isempty(configured_dir)
        source_output_dir = configured_dir;
        return;
    end
    if ~use_latest
        error('cfg.source_output_dir is empty and cfg.use_latest_source is false.');
    end

    exp_dir = fullfile(base_dir, 'experiment_outputs');
    entries = dir(fullfile(exp_dir, 'conflict_validation_*'));
    names = {entries([entries.isdir]).name};
    names = names(~startsWith(names, 'conflict_validation_spacetime_'));
    if isempty(names)
        error('No conflict_validation_* output directory found. Please run validate_event_sm_text_conflicts_smallmap first.');
    end
    names = sort(names);
    source_output_dir = fullfile(exp_dir, names{end});
end

function plot_case_spacetime(grid_map, case_cfg, result, output_png, show_figure, save_figure)
    if nargin < 5
        show_figure = true;
    end
    if nargin < 6
        save_figure = true;
    end

    style = agv_plot_theme();
    fig = figure('Color', 'w', 'Position', [120, 80, 1120, 860], ...
        'Name', sprintf('Spacetime - %s', case_cfg.name), 'NumberTitle', 'off');
    ax = axes(fig);
    hold(ax, 'on');
    view(ax, 42, 24);
    grid(ax, 'on');
    box(ax, 'on');
    set(ax, 'FontName', style.en_font, 'FontSize', 10, 'LineWidth', 1.0);

    runtime_traces = reconstruct_traces_from_rows(result.timeline_rows);
    palette = lines(max(2, numel(runtime_traces)));
    min_t = inf;
    max_t = -inf;
    all_rows = [];
    all_cols = [];
    for agv_id = 1:numel(runtime_traces)
        tr = runtime_traces(agv_id);
        if isempty(tr.times)
            continue;
        end
        min_t = min(min_t, min(tr.times));
        max_t = max(max_t, max(tr.times));
        all_rows = [all_rows; tr.cells(:, 1)]; %#ok<AGROW>
        all_cols = [all_cols; tr.cells(:, 2)]; %#ok<AGROW>
    end
    if ~isfinite(min_t)
        min_t = 0;
        max_t = 1;
    end
    [x_limits, y_limits] = compute_local_spacetime_bounds(grid_map, all_rows, all_cols);

    [obs_r, obs_c] = find(grid_map > 0);
    in_view = obs_c >= x_limits(1) & obs_c <= x_limits(2) & obs_r >= y_limits(1) & obs_r <= y_limits(2);
    obs_r = obs_r(in_view);
    obs_c = obs_c(in_view);
    if ~isempty(obs_r)
        scatter3(ax, obs_c, obs_r, min_t * ones(size(obs_r)), 16, [0.15 0.15 0.15], 'filled', ...
            'MarkerFaceAlpha', 0.15, 'MarkerEdgeAlpha', 0.15, 'HandleVisibility', 'off');
    end

    legend_handles = gobjects(0);
    legend_labels = {};
    for agv_id = 1:numel(runtime_traces)
        tr = runtime_traces(agv_id);
        if isempty(tr.cells)
            continue;
        end

        [plot_x, plot_y, plot_t] = build_spacetime_polyline(tr.cells, tr.times);
        h = plot3(ax, plot_x, plot_y, plot_t, '-', 'Color', palette(agv_id, :), 'LineWidth', 2.6);
        legend_handles(end + 1, 1) = h; %#ok<AGROW>
        legend_labels{end + 1, 1} = sprintf('AGV%d', tr.display_id); %#ok<AGROW>

        scatter3(ax, tr.cells(:, 2), tr.cells(:, 1), tr.times, 24, 'filled', ...
            'MarkerFaceColor', palette(agv_id, :), 'MarkerEdgeColor', 'none', 'HandleVisibility', 'off');
        scatter3(ax, tr.cells(1, 2), tr.cells(1, 1), tr.times(1), 110, 'o', 'filled', ...
            'MarkerFaceColor', palette(agv_id, :), 'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
        scatter3(ax, tr.cells(end, 2), tr.cells(end, 1), tr.times(end), 120, '^', 'filled', ...
            'MarkerFaceColor', palette(agv_id, :), 'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
        text(ax, tr.cells(1, 2) + 0.15, tr.cells(1, 1) - 0.15, tr.times(1), sprintf('AGV-%d', tr.display_id), ...
            'Color', palette(agv_id, :), 'FontWeight', 'bold', 'FontName', style.en_font);
    end

    xlabel(ax, 'x (Column)', 'FontName', style.en_font);
    ylabel(ax, 'y (Row)', 'FontName', style.en_font);
    zlabel(ax, 't', 'FontName', style.en_font);
    xlim(ax, [x_limits(1) - 0.5, x_limits(2) + 0.5]);
    ylim(ax, [y_limits(1) - 0.5, y_limits(2) + 0.5]);
    zlim(ax, [min_t, max_t + 1]);
    set(ax, 'YDir', 'reverse');
    if ~isempty(legend_handles)
        legend(ax, legend_handles, legend_labels, 'Location', 'northeast', 'FontName', style.en_font);
    end
    drawnow;
    if save_figure
        exportgraphics(fig, output_png, 'Resolution', 220);
    end
    if show_figure
        figure(fig);
        shg;
    end
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

function [plot_x, plot_y, plot_t] = build_spacetime_polyline(cells, times)
    plot_x = [];
    plot_y = [];
    plot_t = [];
    if isempty(cells)
        return;
    end

    plot_x(end + 1, 1) = cells(1, 2); %#ok<AGROW>
    plot_y(end + 1, 1) = cells(1, 1); %#ok<AGROW>
    plot_t(end + 1, 1) = times(1); %#ok<AGROW>
    for i = 2:size(cells, 1)
        prev = cells(i - 1, :);
        curr = cells(i, :);
        manhattan_step = abs(curr(1) - prev(1)) + abs(curr(2) - prev(2));

        if manhattan_step <= 1
            plot_x(end + 1, 1) = curr(2); %#ok<AGROW>
            plot_y(end + 1, 1) = curr(1); %#ok<AGROW>
            plot_t(end + 1, 1) = times(i); %#ok<AGROW>
        else
            plot_x(end + 1, 1) = NaN; %#ok<AGROW>
            plot_y(end + 1, 1) = NaN; %#ok<AGROW>
            plot_t(end + 1, 1) = NaN; %#ok<AGROW>
            plot_x(end + 1, 1) = curr(2); %#ok<AGROW>
            plot_y(end + 1, 1) = curr(1); %#ok<AGROW>
            plot_t(end + 1, 1) = times(i); %#ok<AGROW>
        end
    end
end

function [x_limits, y_limits] = compute_local_spacetime_bounds(grid_map, rows, cols)
    if isempty(rows) || isempty(cols)
        x_limits = [1, size(grid_map, 2)];
        y_limits = [1, size(grid_map, 1)];
        return;
    end

    margin = 2;
    min_window = 10;

    min_r = max(1, min(rows) - margin);
    max_r = min(size(grid_map, 1), max(rows) + margin);
    min_c = max(1, min(cols) - margin);
    max_c = min(size(grid_map, 2), max(cols) + margin);

    row_span = max_r - min_r + 1;
    col_span = max_c - min_c + 1;
    target_span = max([row_span, col_span, min_window]);

    row_extra = target_span - row_span;
    col_extra = target_span - col_span;

    min_r = max(1, min_r - floor(row_extra / 2));
    max_r = min(size(grid_map, 1), max_r + ceil(row_extra / 2));
    min_c = max(1, min_c - floor(col_extra / 2));
    max_c = min(size(grid_map, 2), max_c + ceil(col_extra / 2));

    final_row_span = max_r - min_r + 1;
    final_col_span = max_c - min_c + 1;
    if final_row_span < target_span
        deficit = target_span - final_row_span;
        grow_up = min(min_r - 1, floor(deficit / 2));
        grow_down = min(size(grid_map, 1) - max_r, ceil(deficit / 2));
        min_r = min_r - grow_up;
        max_r = max_r + grow_down;
    end
    if final_col_span < target_span
        deficit = target_span - final_col_span;
        grow_left = min(min_c - 1, floor(deficit / 2));
        grow_right = min(size(grid_map, 2) - max_c, ceil(deficit / 2));
        min_c = min_c - grow_left;
        max_c = max_c + grow_right;
    end

    x_limits = [min_c, max_c];
    y_limits = [min_r, max_r];
end
