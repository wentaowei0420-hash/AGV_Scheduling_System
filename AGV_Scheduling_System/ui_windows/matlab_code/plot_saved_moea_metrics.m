function plot_saved_moea_metrics(scenario_name)
%PLOT_SAVED_MOEA_METRICS Plot MOEA metrics from manually adjusted CSV files.
%   plot_saved_moea_metrics('fork') reads fork_manual_metrics.csv and calls
%   evaluate_and_plot_moea in saved mode.
%
%   plot_saved_moea_metrics('lift') reads lift_manual_metrics.csv.

    if nargin < 1 || isempty(scenario_name)
        scenario_name = 'fork';
    end

    scenario_name = lower(string(scenario_name));
    if scenario_name ~= "fork" && scenario_name ~= "lift"
        error('scenario_name must be ''fork'' or ''lift''.');
    end

    base_dir = fullfile(fileparts(mfilename('fullpath')), 'moea_metric_snapshots');
    csv_path = fullfile(base_dir, sprintf('%s_manual_metrics.csv', scenario_name));

    if ~isfile(csv_path)
        error('Manual metrics CSV not found: %s', csv_path);
    end

    opts = struct( ...
        'mode', 'saved', ...
        'scenario_name', char(scenario_name), ...
        'saved_metrics_path', csv_path);

    evaluate_and_plot_moea([], [], opts);
end
