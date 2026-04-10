function [results, summaryTable, saveDir] = exp_single_agv_path_benchmark(varargin)
% EXP_SINGLE_AGV_PATH_BENCHMARK
% Reproducible benchmark for single-AGV path-planning experiments.
%
% The benchmark uses fixed obstacle maps instead of random maps so that
% different algorithms can be compared fairly and repeated experiments
% remain consistent across runs.

style = agv_plot_theme('paper');
init_agv_plot_defaults(style);

cfg = parse_inputs(varargin{:});
suite = build_benchmark_suite();
algorithms = build_algorithm_suite();

saveDir = create_output_dir();
fprintf('>> [PathBenchmark] Standardized single-AGV benchmark started.\n');
fprintf('   - scenarios: %d\n', numel(suite));
fprintf('   - algorithms: %d\n', numel(algorithms));
fprintf('   - output dir: %s\n', saveDir);

results = run_benchmark_suite(suite, algorithms);
summaryTable = summarize_results(results);

export_results(results, summaryTable, saveDir, cfg);
if cfg.plot_summary
    plot_summary_figures(results, summaryTable, algorithms, style, saveDir);
end

if cfg.generate_case_figures
    plot_focused_heatmap_figures(results, suite, style, saveDir);
end

fprintf('>> [PathBenchmark] Benchmark finished.\n');
if cfg.export_tables
    fprintf('   - detailed results saved to: %s\n', fullfile(saveDir, 'single_agv_path_results.csv'));
    fprintf('   - summary saved to: %s\n', fullfile(saveDir, 'single_agv_path_summary.csv'));
else
    fprintf('   - representative heatmaps saved under: %s\n', saveDir);
end
end

function cfg = parse_inputs(varargin)
cfg = struct();
cfg.generate_case_figures = true;
cfg.plot_summary = false;
cfg.export_tables = false;
if nargin >= 1 && islogical(varargin{1})
    cfg.generate_case_figures = varargin{1};
end
end

function suite = build_benchmark_suite()
suite = {};

workshopMap = double(create_binary_grid_map(70, 50, 0));
workshopCases = [ ...
    make_fixed_case(workshopMap, 'main_aisle_cross', [4, 4], [48, 68]); ...
    make_fixed_case(workshopMap, 'upper_to_lower_shop', [6, 12], [42, 60]); ...
    make_fixed_case(workshopMap, 'left_lane_to_right_lane', [20, 6], [20, 64]) ...
];
suite{end + 1} = struct( ...
    'name', 'workshop_layout', ...
    'map', workshopMap, ...
    'cases', workshopCases ...
);

suite{end + 1} = struct( ...
    'name', 'turn_tradeoff_dual_route', ...
    'map', build_turn_tradeoff_dual_route_map(), ...
    'cases', [ ...
        struct('name', 'short_zigzag_vs_long_straight', 'start', [3, 3], 'goal', [22, 42]); ...
        struct('name', 'reverse_tradeoff', 'start', [22, 42], 'goal', [3, 3]) ...
    ] ...
);

suite{end + 1} = struct( ...
    'name', 'dead_end_maze', ...
    'map', build_dead_end_maze_map(), ...
    'cases', [ ...
        struct('name', 'maze_escape', 'start', [3, 3], 'goal', [28, 38]); ...
        struct('name', 'cross_maze', 'start', [28, 4], 'goal', [4, 36]) ...
    ] ...
);

suite{end + 1} = struct( ...
    'name', 'serpentine_vs_bypass', ...
    'map', build_serpentine_vs_bypass_map(), ...
    'cases', [ ...
        struct('name', 'payload_sensitive_route', 'start', [3, 4], 'goal', [28, 38]); ...
        struct('name', 'bypass_return', 'start', [28, 5], 'goal', [4, 37]) ...
    ] ...
);

for i = 1:numel(suite)
    validate_cases(suite{i});
end
end

function algorithms = build_algorithm_suite()
algorithms = { ...
    struct('name', 'AStar', 'runner', @(map, start, goal) run_astar_wrapper(map, start, goal)), ...
    struct('name', 'Dijkstra', 'runner', @(map, start, goal) run_dijkstra_wrapper(map, start, goal)), ...
    struct('name', 'ImprovedAStar_P0', 'runner', @(map, start, goal) run_astar_turn3_wrapper(map, start, goal, 0)), ...
    struct('name', 'ImprovedAStar_P80', 'runner', @(map, start, goal) run_astar_turn3_wrapper(map, start, goal, 80)), ...
    struct('name', 'ImprovedAStar_P150', 'runner', @(map, start, goal) run_astar_turn3_wrapper(map, start, goal, 150)) ...
};
end

function results = run_benchmark_suite(suite, algorithms)
results = struct('scenario', {}, 'case_name', {}, 'algorithm', {}, ...
    'feasible', {}, 'plan_time_ms', {}, 'path_length', {}, 'turn_count', {}, ...
    'expanded_nodes', {}, 'cost', {}, 'start_row', {}, 'start_col', {}, ...
    'goal_row', {}, 'goal_col', {}, 'map_rows', {}, 'map_cols', {}, 'path', {}, 'gscore_matrix', {});

idx = 0;
for s = 1:numel(suite)
    scenario = suite{s};
    fprintf('>> [Scenario] %s\n', scenario.name);
    for c = 1:numel(scenario.cases)
        caseDef = scenario.cases(c);
        fprintf('   - case: %s [%d,%d] -> [%d,%d]\n', caseDef.name, ...
            caseDef.start(1), caseDef.start(2), caseDef.goal(1), caseDef.goal(2));
        for a = 1:numel(algorithms)
            idx = idx + 1;
            algo = algorithms{a};
            metrics = algo.runner(scenario.map, caseDef.start, caseDef.goal);
            results(idx).scenario = scenario.name;
            results(idx).case_name = caseDef.name;
            results(idx).algorithm = algo.name;
            results(idx).feasible = metrics.feasible;
            results(idx).plan_time_ms = metrics.plan_time_ms;
            results(idx).path_length = metrics.path_length;
            results(idx).turn_count = metrics.turn_count;
            results(idx).expanded_nodes = metrics.expanded_nodes;
            results(idx).cost = metrics.cost;
            results(idx).start_row = caseDef.start(1);
            results(idx).start_col = caseDef.start(2);
            results(idx).goal_row = caseDef.goal(1);
            results(idx).goal_col = caseDef.goal(2);
            results(idx).map_rows = size(scenario.map, 1);
            results(idx).map_cols = size(scenario.map, 2);
            results(idx).path = metrics.path;
            results(idx).gscore_matrix = metrics.gscore_matrix;
        end
    end
end
end

function summaryTable = summarize_results(results)
algorithms = unique({results.algorithm}, 'stable');
summaryRows = struct('algorithm', {}, 'cases_total', {}, 'cases_feasible', {}, ...
    'feasible_rate', {}, 'avg_time_ms', {}, 'avg_path_length', {}, ...
    'avg_turn_count', {}, 'avg_expanded_nodes', {}, 'avg_cost', {});

for a = 1:numel(algorithms)
    name = algorithms{a};
    mask = strcmp({results.algorithm}, name);
    subset = results(mask);
    feasibleMask = [subset.feasible];
    feasibleCount = sum(feasibleMask);
    totalCount = numel(subset);

    summaryRows = [summaryRows; struct( ...
        'algorithm', string(name), ...
        'cases_total', totalCount, ...
        'cases_feasible', feasibleCount, ...
        'feasible_rate', feasibleCount / max(totalCount, 1), ...
        'avg_time_ms', safe_mean([subset.plan_time_ms]), ...
        'avg_path_length', safe_mean([subset(feasibleMask).path_length]), ...
        'avg_turn_count', safe_mean([subset(feasibleMask).turn_count]), ...
        'avg_expanded_nodes', safe_mean([subset(feasibleMask).expanded_nodes]), ...
        'avg_cost', safe_mean([subset(feasibleMask).cost]))]; %#ok<AGROW>
end

summaryTable = struct2table(summaryRows);
end

function export_results(results, summaryTable, saveDir, cfg)
resultRows = repmat(struct(), numel(results), 1);
for i = 1:numel(results)
    resultRows(i).scenario = string(results(i).scenario);
    resultRows(i).case_name = string(results(i).case_name);
    resultRows(i).algorithm = string(results(i).algorithm);
    resultRows(i).feasible = results(i).feasible;
    resultRows(i).plan_time_ms = results(i).plan_time_ms;
    resultRows(i).path_length = results(i).path_length;
    resultRows(i).turn_count = results(i).turn_count;
    resultRows(i).expanded_nodes = results(i).expanded_nodes;
    resultRows(i).cost = results(i).cost;
    resultRows(i).start_row = results(i).start_row;
    resultRows(i).start_col = results(i).start_col;
    resultRows(i).goal_row = results(i).goal_row;
    resultRows(i).goal_col = results(i).goal_col;
    resultRows(i).map_rows = results(i).map_rows;
    resultRows(i).map_cols = results(i).map_cols;
    resultRows(i).path_nodes = size(results(i).path, 1);
end

    if cfg.export_tables
        resultTable = struct2table(resultRows);
        writetable(resultTable, fullfile(saveDir, 'single_agv_path_results.csv'));
        writetable(summaryTable, fullfile(saveDir, 'single_agv_path_summary.csv'));
    end
    save(fullfile(saveDir, 'single_agv_path_results.mat'), 'results', 'summaryTable');
end

function plot_summary_figures(results, summaryTable, algorithms, style, saveDir)
algorithmNames = string(summaryTable.algorithm);
colors = build_algorithm_colors(numel(algorithms));

make_summary_bar(summaryTable.avg_time_ms, algorithmNames, colors, ...
    'Average Planning Time', 'Planning time (ms)', ...
    fullfile(saveDir, 'summary_time.png'), style);
make_summary_bar(summaryTable.avg_path_length, algorithmNames, colors, ...
    'Average Path Length', 'Path length (cells)', ...
    fullfile(saveDir, 'summary_path_length.png'), style);
make_summary_bar(summaryTable.avg_turn_count, algorithmNames, colors, ...
    'Average Turn Count', 'Turn count', ...
    fullfile(saveDir, 'summary_turn_count.png'), style);
make_summary_bar(summaryTable.avg_expanded_nodes, algorithmNames, colors, ...
    'Average Expanded Nodes', 'Expanded nodes', ...
    fullfile(saveDir, 'summary_expanded_nodes.png'), style);

scenarioNames = unique({results.scenario}, 'stable');
fig = figure('Name', 'Feasible Rate by Scenario', 'Color', 'w', 'Position', [180, 160, 900, 500]);
hold on;
for a = 1:numel(algorithms)
    algoName = algorithms{a}.name;
    vals = zeros(1, numel(scenarioNames));
    for s = 1:numel(scenarioNames)
        mask = strcmp({results.algorithm}, algoName) & strcmp({results.scenario}, scenarioNames{s});
        vals(s) = mean([results(mask).feasible]);
    end
    plot(1:numel(scenarioNames), vals, '-o', 'Color', colors(a, :), ...
        'LineWidth', style.line_width, 'DisplayName', algoName);
end
grid on;
set(gca, 'XTick', 1:numel(scenarioNames), 'XTickLabel', scenarioNames, ...
    'FontName', style.en_font, 'FontSize', style.axis_font, 'GridAlpha', style.grid_alpha, 'LineWidth', 1);
title('Feasible Rate by Scenario', 'FontSize', style.title_font, 'FontWeight', 'bold');
xlabel('Scenario', 'FontSize', style.label_font);
ylabel('Feasible rate', 'FontSize', style.label_font);
ylim([0, 1.05]);
legend('Location', 'southoutside', 'NumColumns', 3, 'Interpreter', 'none');
apply_agv_plot_theme(gcf, style);
exportgraphics(fig, fullfile(saveDir, 'summary_feasible_rate.png'), 'Resolution', 200);
end

function plot_focused_heatmap_figures(results, suite, style, saveDir)
searchCase = select_global_case(results, suite, 'search');
payloadCase = select_global_case(results, suite, 'payload');

plot_case_for_algorithms(results, searchCase, {'AStar', 'Dijkstra', 'ImprovedAStar_P150'}, ...
    'Search Heatmap Comparison', fullfile(saveDir, 'focus_search_heatmap.png'), style);
plot_case_for_algorithms(results, payloadCase, {'ImprovedAStar_P0', 'ImprovedAStar_P80', 'ImprovedAStar_P150'}, ...
    'Payload Heatmap Comparison', fullfile(saveDir, 'focus_payload_heatmap.png'), style);
end

function plot_case_for_algorithms(results, caseInfo, algorithmNames, figureTitle, outPath, style)
fig = figure('Name', figureTitle, 'Color', 'w', 'Position', [120, 120, 1500, 520]);
tl = tiledlayout(1, numel(algorithmNames), 'Padding', 'compact', 'TileSpacing', 'compact');
title(tl, sprintf('%s - %s / %s', figureTitle, caseInfo.scenario.name, caseInfo.case_def.name), ...
    'FontSize', style.sgtitle_font, 'FontWeight', 'bold', 'Interpreter', 'none');

for a = 1:numel(algorithmNames)
    nexttile;
    algoName = algorithmNames{a};
    mask = strcmp({results.scenario}, caseInfo.scenario.name) & ...
           strcmp({results.case_name}, caseInfo.case_def.name) & ...
           strcmp({results.algorithm}, algoName);
    caseResult = results(mask);
    if isempty(caseResult)
        axis off;
        text(0.5, 0.5, 'No result', 'HorizontalAlignment', 'center');
        continue;
    end

    map = caseInfo.scenario.map;
    if caseResult.feasible
        plot_path_result(map, caseResult.path, caseInfo.case_def.start, caseInfo.case_def.goal, ...
            caseResult.path_length, caseResult.turn_count, caseResult.expanded_nodes, ...
            algoName, gca, caseResult.gscore_matrix);
    else
        imagesc(map);
        colormap(gray);
        axis equal tight;
        set(gca, 'YDir', 'normal');
        hold on;
        plot(caseInfo.case_def.start(2), caseInfo.case_def.start(1), 'go', 'MarkerSize', 8, 'MarkerFaceColor', 'g');
        plot(caseInfo.case_def.goal(2), caseInfo.case_def.goal(1), 'ro', 'MarkerSize', 8, 'MarkerFaceColor', 'r');
        title([algoName ' (infeasible)'], 'Interpreter', 'none');
        hold off;
    end
end

apply_agv_plot_theme(fig, style);
exportgraphics(fig, outPath, 'Resolution', 220);
end

function caseInfo = select_global_case(results, suite, mode)
bestScore = -inf;
caseInfo = struct('scenario', suite{1}, 'case_def', suite{1}.cases(1));
for s = 1:numel(suite)
    scenario = suite{s};
    for i = 1:numel(scenario.cases)
        oneCase = scenario.cases(i);
        mask = strcmp({results.scenario}, scenario.name) & strcmp({results.case_name}, oneCase.name);
        subset = results(mask);
        if isempty(subset)
            continue;
        end
        feasibleSubset = subset([subset.feasible]);
        if isempty(feasibleSubset)
            continue;
        end

        switch mode
            case 'search'
                targetNames = {'AStar', 'Dijkstra', 'ImprovedAStar_P150'};
                score = score_case_by_algorithms(feasibleSubset, targetNames, true);
            case 'payload'
                targetNames = {'ImprovedAStar_P0', 'ImprovedAStar_P80', 'ImprovedAStar_P150'};
                score = score_case_by_algorithms(feasibleSubset, targetNames, false);
            otherwise
                score = -inf;
        end

        if score > bestScore
            bestScore = score;
            caseInfo = struct('scenario', scenario, 'case_def', oneCase);
        end
    end
end
end

function score = score_case_by_algorithms(subset, targetNames, emphasize_search)
mask = ismember({subset.algorithm}, targetNames);
subset = subset(mask);
if numel(subset) < 2
    score = -inf;
    return;
end
nodeSpread = range([subset.expanded_nodes]);
turnSpread = range([subset.turn_count]);
costSpread = range([subset.cost]);
pathSpread = range([subset.path_length]);
ratio = max([subset.expanded_nodes]) / max(min([subset.expanded_nodes]), 1);
if emphasize_search
    score = nodeSpread / 20 + 2 * ratio + turnSpread + costSpread / 15 + pathSpread;
else
    score = 3 * turnSpread + costSpread / 10 + pathSpread + nodeSpread / 80;
end
end

function caseDef = select_most_discriminative_case(results, scenario)
bestScore = -inf;
caseDef = scenario.cases(1);
for i = 1:numel(scenario.cases)
    oneCase = scenario.cases(i);
    mask = strcmp({results.scenario}, scenario.name) & strcmp({results.case_name}, oneCase.name);
    subset = results(mask);
    if isempty(subset)
        continue;
    end

    feasibleMask = [subset.feasible];
    feasibleSubset = subset(feasibleMask);
    if numel(feasibleSubset) < 2
        score = -1;
    else
        pathSpread = range([feasibleSubset.path_length]);
        turnSpread = range([feasibleSubset.turn_count]);
        nodeSpread = range([feasibleSubset.expanded_nodes]);
        costSpread = range([feasibleSubset.cost]);
        searchContrast = max([feasibleSubset.expanded_nodes]) / max(min([feasibleSubset.expanded_nodes]), 1);
        score = 4 * turnSpread + 2 * pathSpread + nodeSpread / 30 + costSpread / 20 + searchContrast;
    end

    if score > bestScore
        bestScore = score;
        caseDef = oneCase;
    end
end
end

function make_summary_bar(values, labels, colors, figTitle, yLabel, outPath, style)
fig = figure('Name', figTitle, 'Color', 'w', 'Position', [150, 150, 820, 500]);
bh = bar(values, 'FaceColor', 'flat');
for i = 1:numel(values)
    bh.CData(i, :) = colors(i, :);
end
grid on;
set(gca, 'XTick', 1:numel(labels), 'XTickLabel', labels, ...
    'FontName', style.en_font, 'FontSize', style.axis_font, 'GridAlpha', style.grid_alpha, 'LineWidth', 1);
xtickangle(20);
title(figTitle, 'FontSize', style.title_font, 'FontWeight', 'bold', 'Interpreter', 'none');
xlabel('Algorithm', 'FontSize', style.label_font);
ylabel(yLabel, 'FontSize', style.label_font);
apply_agv_plot_theme(gcf, style);
exportgraphics(fig, outPath, 'Resolution', 200);
end

function colors = build_algorithm_colors(n)
base = [
    0.11, 0.47, 0.82;
    0.89, 0.42, 0.13;
    0.20, 0.63, 0.17;
    0.60, 0.31, 0.64;
    0.77, 0.19, 0.23
];
if n <= size(base, 1)
    colors = base(1:n, :);
else
    colors = lines(n);
end
end

function metrics = run_astar_wrapper(map, start, goal)
tStart = tic;
[path, cost, turnCount, expandedNodes, pathLength, gScoreMatrix] = astar_planner(map, start, goal, 1);
metrics = package_metrics(path, cost, turnCount, expandedNodes, pathLength, toc(tStart), gScoreMatrix);
end

function metrics = run_dijkstra_wrapper(map, start, goal)
tStart = tic;
[path, cost, turnCount, expandedNodes, pathLength, gScoreMatrix] = dijkstra_planner(map, start, goal);
metrics = package_metrics(path, cost, turnCount, expandedNodes, pathLength, toc(tStart), gScoreMatrix);
end

function metrics = run_astar_turn3_wrapper(map, start, goal, payloadWeight)
tStart = tic;
[path, cost, turnCount, expandedNodes, pathLength, gScoreMatrix] = astar_planner_turn3(map, start, goal, payloadWeight);
metrics = package_metrics(path, cost, turnCount, expandedNodes, pathLength, toc(tStart), gScoreMatrix);
end

function metrics = package_metrics(path, cost, turnCount, expandedNodes, pathLength, elapsedSec, gScoreMatrix)
metrics = struct();
metrics.path = path;
metrics.feasible = ~isempty(path) && isfinite(cost);
metrics.plan_time_ms = elapsedSec * 1000;
metrics.path_length = pathLength;
metrics.turn_count = turnCount;
metrics.expanded_nodes = expandedNodes;
metrics.cost = cost;
metrics.gscore_matrix = gScoreMatrix;
end

function validate_cases(scenario)
map = scenario.map;
for i = 1:numel(scenario.cases)
    caseDef = scenario.cases(i);
    assert(is_free_cell(map, caseDef.start), 'Blocked start cell in %s / %s', scenario.name, caseDef.name);
    assert(is_free_cell(map, caseDef.goal), 'Blocked goal cell in %s / %s', scenario.name, caseDef.name);
end
end

function caseDef = make_fixed_case(map, name, preferredStart, preferredGoal)
caseDef = struct();
caseDef.name = name;
caseDef.start = snap_to_free_cell(map, preferredStart);
caseDef.goal = snap_to_free_cell(map, preferredGoal);
end

function rc = snap_to_free_cell(map, preferredRC)
if is_free_cell(map, preferredRC)
    rc = preferredRC;
    return;
end

[rows, cols] = size(map);
[rr, cc] = ndgrid(1:rows, 1:cols);
freeMask = (map == 0);
assert(any(freeMask(:)), 'No free cell exists in the supplied benchmark map.');

dist2 = (rr - preferredRC(1)).^2 + (cc - preferredRC(2)).^2;
dist2(~freeMask) = inf;
[~, idx] = min(dist2(:));
[rBest, cBest] = ind2sub(size(map), idx);
rc = [rBest, cBest];
end

function tf = is_free_cell(map, rc)
tf = rc(1) >= 1 && rc(1) <= size(map, 1) && ...
     rc(2) >= 1 && rc(2) <= size(map, 2) && ...
     map(rc(1), rc(2)) == 0;
end

function value = safe_mean(x)
if isempty(x)
    value = NaN;
else
    value = mean(x);
end
end

function saveDir = create_output_dir()
baseDir = fileparts(mfilename('fullpath'));
outRoot = fullfile(baseDir, 'experiment_outputs');
if ~exist(outRoot, 'dir')
    mkdir(outRoot);
end
saveDir = fullfile(outRoot, ['single_agv_path_' datestr(now, 'yyyymmdd_HHMMSS')]);
mkdir(saveDir);
end

function map = build_corridor_bottleneck_map()
map = zeros(30, 40);
map(1, :) = 1; map(end, :) = 1;
map(:, 1) = 1; map(:, end) = 1;
map(6:25, 10) = 1;
map(6:25, 30) = 1;
map(10, 10:25) = 1;
map(20, 15:30) = 1;
map(14:16, 10) = 0;
map(18:20, 30) = 0;
map(10, 18:20) = 0;
map(20, 22:24) = 0;
end

function map = build_turn_tradeoff_dual_route_map()
map = ones(26, 46);
map = carve_polyline(map, [3, 3; 3, 10; 6, 10; 6, 16; 4, 16; 4, 22; 8, 22; 8, 28; 5, 28; 5, 35; 9, 35; 9, 42; 22, 42]);
map = carve_polyline(map, [3, 3; 22, 3; 22, 42]);
map = carve_polyline(map, [3, 3; 3, 42; 22, 42]);
map = carve_polyline(map, [12, 10; 12, 18; 18, 18; 18, 28; 14, 28; 14, 36]);
map = dilate_free_cells(map, 1);
end

function map = build_u_shape_detour_map()
map = zeros(30, 40);
map(1, :) = 1; map(end, :) = 1;
map(:, 1) = 1; map(:, end) = 1;
map(6:24, 12) = 1;
map(24, 12:30) = 1;
map(6:24, 30) = 1;
map(10:20, 20) = 1;
map(10, 20:34) = 1;
map(18, 6:20) = 1;
map(24, 20:22) = 0;
map(14:16, 30) = 0;
map(18, 12:14) = 0;
end

function map = build_dead_end_maze_map()
map = ones(32, 42);
map = carve_polyline(map, [3, 3; 3, 38; 28, 38]);
map = carve_polyline(map, [3, 3; 28, 3; 28, 38]);
map = carve_polyline(map, [8, 3; 8, 14; 5, 14]);
map = carve_polyline(map, [13, 3; 13, 18; 9, 18]);
map = carve_polyline(map, [18, 3; 18, 24; 14, 24]);
map = carve_polyline(map, [23, 3; 23, 30; 19, 30]);
map = carve_polyline(map, [28, 8; 22, 8; 22, 14; 26, 14]);
map = carve_polyline(map, [6, 20; 16, 20; 16, 26; 10, 26]);
map = carve_polyline(map, [10, 32; 20, 32; 20, 36; 14, 36]);
map = carve_polyline(map, [24, 20; 24, 34; 27, 34]);
map = dilate_free_cells(map, 1);
end

function map = build_dense_crossing_map()
map = zeros(32, 40);
map(1, :) = 1; map(end, :) = 1;
map(:, 1) = 1; map(:, end) = 1;
for c = 7:6:34
    map(4:28, c) = 1;
end
for r = 7:6:25
    map(r, 4:36) = 1;
end
map(7, 7) = 0; map(7, 13) = 0; map(7, 19) = 0; map(7, 25) = 0; map(7, 31) = 0;
map(13, 13) = 0; map(13, 19) = 0; map(13, 25) = 0;
map(19, 7) = 0; map(19, 19) = 0; map(19, 31) = 0;
map(25, 13) = 0; map(25, 25) = 0;
map(10:12, 7) = 0;
map(20:22, 31) = 0;
map(25, 30:34) = 0;
end

function map = build_serpentine_vs_bypass_map()
map = ones(32, 42);
map = carve_polyline(map, [3, 4; 3, 10; 8, 10; 8, 16; 5, 16; 5, 22; 10, 22; 10, 28; 6, 28; 6, 34; 12, 34; 12, 38; 28, 38]);
map = carve_polyline(map, [3, 4; 28, 4; 28, 38]);
map = carve_polyline(map, [3, 4; 3, 38; 28, 38]);
map = carve_polyline(map, [16, 8; 16, 18; 22, 18; 22, 30; 18, 30]);
map = carve_polyline(map, [11, 12; 20, 12]);
map = dilate_free_cells(map, 1);
end

function map = carve_polyline(map, points)
for i = 1:size(points, 1) - 1
    p1 = points(i, :);
    p2 = points(i + 1, :);
    if p1(1) == p2(1)
        c1 = min(p1(2), p2(2));
        c2 = max(p1(2), p2(2));
        map(p1(1), c1:c2) = 0;
    elseif p1(2) == p2(2)
        r1 = min(p1(1), p2(1));
        r2 = max(p1(1), p2(1));
        map(r1:r2, p1(2)) = 0;
    else
        error('Only orthogonal polyline segments are supported.');
    end
end
end

function map = dilate_free_cells(map, radius)
if radius <= 0
    return;
end
freeMask = (map == 0);
for dr = -radius:radius
    for dc = -radius:radius
        shifted = false(size(freeMask));
        srcR = max(1, 1 - dr):min(size(map, 1), size(map, 1) - dr);
        srcC = max(1, 1 - dc):min(size(map, 2), size(map, 2) - dc);
        dstR = srcR + dr;
        dstC = srcC + dc;
        shifted(dstR, dstC) = freeMask(srcR, srcC);
        freeMask = freeMask | shifted;
    end
end
map = ones(size(map));
map(freeMask) = 0;
map(1, :) = 1; map(end, :) = 1;
map(:, 1) = 1; map(:, end) = 1;
end
