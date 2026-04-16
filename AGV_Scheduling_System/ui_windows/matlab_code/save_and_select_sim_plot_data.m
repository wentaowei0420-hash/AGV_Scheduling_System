function plot_tbl = save_and_select_sim_plot_data(scenario_name, live_tbl, opts)
%SAVE_AND_SELECT_SIM_PLOT_DATA Save simulation plot data and optionally load manual CSV.
%   plot_tbl = save_and_select_sim_plot_data('fork', live_tbl, opts)
%   saves latest/snapshot/manual CSV+MAT files for dist/time/energy curves and
%   optionally loads a saved manual CSV for plotting.

    if nargin < 3 || isempty(opts)
        opts = struct();
    end

    base_dir = fileparts(mfilename('fullpath'));
    snapshot_dir = fullfile(base_dir, 'sim_plot_snapshots');
    if ~exist(snapshot_dir, 'dir')
        mkdir(snapshot_dir);
    end

    mode = lower(string(get_option_local(opts, 'mode', 'live')));
    prefer_saved_for_plot = logical(get_option_local(opts, 'prefer_saved_for_plot', false));
    saved_metrics_path = get_option_local(opts, 'saved_metrics_path', ...
        fullfile(snapshot_dir, sprintf('%s_manual_plot_data.csv', scenario_name)));

    latest_mat_path = fullfile(snapshot_dir, sprintf('%s_latest_plot_data.mat', scenario_name));
    latest_csv_path = fullfile(snapshot_dir, sprintf('%s_latest_plot_data.csv', scenario_name));
    manual_csv_path = fullfile(snapshot_dir, sprintf('%s_manual_plot_data.csv', scenario_name));
    timestamp = datestr(now, 'yyyymmdd_HHMMSS');
    snapshot_mat_path = fullfile(snapshot_dir, sprintf('%s_%s_plot_data.mat', scenario_name, timestamp));
    snapshot_csv_path = fullfile(snapshot_dir, sprintf('%s_%s_plot_data.csv', scenario_name, timestamp));

    save(latest_mat_path, 'live_tbl');
    save(snapshot_mat_path, 'live_tbl');
    writetable(live_tbl, latest_csv_path);
    writetable(live_tbl, snapshot_csv_path);

    if ~exist(manual_csv_path, 'file')
        writetable(live_tbl, manual_csv_path);
    end

    fprintf('>> [SIM-PLOT] Curve data saved to:\n');
    fprintf('   - MAT : %s\n', latest_mat_path);
    fprintf('   - CSV : %s\n', latest_csv_path);
    fprintf('   - Manual CSV template: %s\n', manual_csv_path);

    if mode == "saved"
        plot_tbl = load_plot_table(saved_metrics_path);
    elseif prefer_saved_for_plot && exist(saved_metrics_path, 'file')
        plot_tbl = load_plot_table(saved_metrics_path);
    else
        plot_tbl = live_tbl;
    end
end

function tbl = load_plot_table(csv_path)
    if ~exist(csv_path, 'file')
        error('save_and_select_sim_plot_data:MissingSavedPlotData', ...
            'Saved plot data file not found: %s', csv_path);
    end

    tbl = readtable(csv_path);
    required_cols = { ...
        'Generation', ...
        'dist_exp', 'dist_base', ...
        'time_exp', 'time_base', ...
        'energy_exp', 'energy_base'};
    for i = 1:numel(required_cols)
        if ~ismember(required_cols{i}, tbl.Properties.VariableNames)
            error('save_and_select_sim_plot_data:InvalidSavedPlotData', ...
                'Saved plot data is missing required column: %s', required_cols{i});
        end
    end
end

function value = get_option_local(opts, field_name, default_value)
    if isstruct(opts) && isfield(opts, field_name) && ~isempty(opts.(field_name))
        value = opts.(field_name);
    else
        value = default_value;
    end
end
