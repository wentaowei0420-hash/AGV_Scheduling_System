function plot_xyt_trajectories(json_file_path)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % =========================================================
    % 瑙ｆ瀽 task_paths.json 骞剁粯鍒?X-Y-T 涓夌淮鏃剁┖杞ㄨ抗鍥?
    % =========================================================
    
    if nargin < 1
        json_file_path = 'task_paths.json'; % 榛樿璇诲彇褰撳墠鐩綍涓嬬殑鏂囦欢
    end

    % 1. 璇诲彇骞惰В鏋?JSON 鏂囦欢
    try
        json_str = fileread(json_file_path);
        data = jsondecode(json_str);
    catch ME
        error('鏃犳硶璇诲彇鎴栬В鏋?%s銆傝纭浠跨湡宸茬粡杩愯骞剁敓鎴愪簡璇ユ枃浠讹紒\n閿欒淇℃伅: %s', json_file_path, ME.message);
    end

    % 鑾峰彇鎵€鏈夋湁杞ㄨ抗鐨勪换鍔″瓧娈靛悕 (濡?'task_1', 'task_2')
    task_names = fieldnames(data);
    if isempty(task_names)
        disp('JSON 鏂囦欢涓病鏈夋壘鍒版湁鏁堢殑杞ㄨ抗鏁版嵁锛?);
        return;
    end

    % 2. 鍒濆鍖?3D 鍥惧舰绐楀彛
    figure('Name', 'X-Y-T 涓夌淮鏃剁┖杞ㄨ抗鎶曞奖', 'Position', [150, 150, 1000, 800], 'Color', 'w');
    hold on; grid on;
    view(-35, 35); % 璁剧疆鍒濆 3D 瑙嗚锛屾渶浣宠娴嬭搴?
    
    % 璁剧疆楂樼骇鐨勯鑹叉槧灏?(鍖哄垎涓嶅悓浠诲姟/AGV)
    colors = lines(length(task_names));

    % 3. 寰幆瑙ｆ瀽姣忎竴涓换鍔＄殑杞ㄨ抗骞剁粯鍒?
    for i = 1:length(task_names)
        t_name = task_names{i};
        path_data = data.(t_name);

        if isempty(path_data)
            continue;
        end

        % 鍒ゆ柇鏁版嵁缁村害锛歂x2 (浠呭潗鏍? 杩樻槸 Nx3 (鍖呭惈浜嗘椂闂存埑)
        if size(path_data, 2) == 2
            % 濡傛灉搴曞眰鏈慨鏀癸紝鐢ㄥ簭鍒楃储寮曟ā鎷熺浉瀵规椂闂存
            Y_row = path_data(:, 1);
            X_col = path_data(:, 2);
            T_time = (1:length(X_col))'; 
            z_label_str = '鐩稿鏃堕棿姝?(Relative Step)';
        elseif size(path_data, 2) >= 3
            % 濡傛灉鍖呭惈浜嗙湡瀹炰豢鐪熸椂闂存埑 t (寮虹儓鎺ㄨ崘)
            Y_row = path_data(:, 1);
            X_col = path_data(:, 2);
            T_time = path_data(:, 3);
            z_label_str = '缁濆浠跨湡鏃堕棿 T (Absolute Time)';
        end

        % 鏍煎紡鍖栧浘渚嬪悕绉?(灏?'task_1' 鍙樹负 'Task 1')
        legend_name = strrep(t_name, 'task_', 'Task ');

        % --- 缁樺埗鏃剁┖涓绘洸绾?---
        plot3(X_col, Y_row, T_time, '-', ...
            'Color', [colors(i, :), 0.8], ... % 鍔犲叆灏戣閫忔槑搴?
            'LineWidth', 1, ...
            'DisplayName', legend_name);

        % --- 缁樺埗鏁版嵁鐐规暎鐐?---
        scatter3(X_col, Y_row, T_time, 20, colors(i, :), 'filled', ...
            'HandleVisibility', 'off');

        % --- 鏍囪璧风偣 (缁胯壊鏂瑰潡) 涓庣粓鐐?(绾㈣壊涓夎) ---
        plot3(X_col(1), Y_row(1), T_time(1), 's', ...
            'MarkerSize', 8, 'MarkerFaceColor', '#77AC30', 'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
        plot3(X_col(end), Y_row(end), T_time(end), '^', ...
            'MarkerSize', 8, 'MarkerFaceColor', '#D95319', 'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
            
        % --- 缁樺埗鍦?X-Y 骞抽潰涓婄殑浜岀淮鎶曞奖 (鍙€夛紝鏋佸ぇ鍦板寮虹┖闂寸珛浣撴劅) ---
        plot3(X_col, Y_row, zeros(size(T_time)), '--', ...
            'Color', [colors(i, :), 0.3], 'LineWidth', 1, 'HandleVisibility', 'off');
    end

    % 4. 缇庡寲鍧愭爣杞翠笌瑙嗚鏁堟灉
    xlabel('绌洪棿 X 杞?(鏍呮牸鍒楀潗鏍?', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel('绌洪棿 Y 杞?(鏍呮牸琛屽潗鏍?', 'FontWeight', 'bold', 'FontSize', 11);
    zlabel(z_label_str, 'FontWeight', 'bold', 'FontSize', 11);
    title('澶?AGV 浠诲姟鎵ц X-Y-T 涓夌淮鏃剁┖杞ㄨ抗鎶曞奖鍥?, 'FontSize', 14, 'FontWeight', 'bold');

    % MATLAB鐭╅樀涓鍧愭爣寰€涓嬫槸閫掑鐨勶紝闇€瑕佺炕杞?Y 杞翠互鍖归厤鐗╃悊鐩磋
    set(gca, 'YDir', 'reverse');
    
    % 璁剧疆 Z 杞翠笅鐣屼负 0 (浠ヤ究瀹圭撼鎶曞奖)
    zlim([0, max(T_time) + 10]);

    % 娣诲姞鍥句緥骞剁編鍖栬儗鏅?
    legend('Location', 'northeastoutside', 'FontSize', 10);
    set(gca, 'Box', 'on', 'LineWidth', 1, 'GridAlpha', 0.2);
    
    % 寮€鍚笁缁存棆杞氦浜?
    rotate3d on;
    disp('>> [缁樺浘瀹屾瘯] 鎷栧姩榧犳爣鍙棆杞?3D 瑙嗚浠ヨ瀵熸椂绌洪伩闅滅粏鑺傘€?);
    apply_agv_plot_theme(gcf, style);
    hold off;
end



