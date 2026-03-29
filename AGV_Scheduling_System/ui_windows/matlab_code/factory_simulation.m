function factory_simulation()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    clc; 
    clear; 
    close all;

    % 1. 瀹氫箟鍦板浘灏哄
    mapW = 60; 
    mapH = 50;
    target_station_id = 15;  % <--- 淇敼杩欓噷璇曡瘯锛屾瘮濡傛敼鎴?1, 8, 12
    % 2. 鐢熸垚浜屽€煎寲鍦板浘 (鏈哄櫒鐪间腑鐨勪笘鐣?
    % 0 = 璺?(瀹夊叏), 1 = 澧?(鎾炶溅)
    binaryMap = create_binary_grid_map(mapW, mapH, target_station_id);
    % 3. 瀹氫箟鍏抽敭鑸偣 (棰勮澶ф浣嶇疆)
    % 鏍煎紡: [y, x]
    % 銆愮敤鎴疯緭鍏ャ€戜綘鎯冲幓鍑犲彿宸ヤ綅锛?(1-12)
    start_pos = [3, 11];    % 璧风偣锛氬彸涓嬭绌哄湴
    [pickup_pos, dropoff_pos] = get_task_coordinates(target_station_id);

    % 5. 杩愯 A* 绠楁硶
    disp('姝ｅ湪瑙勫垝璺緞 1: 杞﹀簱 -> 浠撳簱...');
    [path1, ~, ~, ~] = astar_planner_turn(binaryMap, start_pos, pickup_pos, 0.7);
    disp('姝ｅ湪瑙勫垝璺緞 2: 浠撳簱 -> 宸ヤ綅...');
    [path2, ~, ~, ~] = astar_planner_turn(binaryMap, pickup_pos, dropoff_pos, 0.7);
    disp('姝ｅ湪瑙勫垝璺緞 3: 宸ヤ綅 -> 杞﹀簱...');
    [path3, ~, ~, ~] = astar_planner_turn(binaryMap, dropoff_pos, start_pos, 0.7);
    % 6. 缁樺埗绮剧編鍙鍖栧湴鍥?
    generate_beautiful_factory_map();
    % 7. 缁樺埗骞跺姩鐢绘紨绀鸿矾寰?
    if ~isempty(path1) && ~isempty(path2) && ~isempty(path3)
        % --- A. 缁樺埗鍏抽敭鐐?(淇敼涓烘爡鏍兼柟鍧? ---
        % 娉ㄦ剰锛歳ectangle 鐨?Position 鏍煎紡鏄?[x, y, w, h]
        % 鍥犱负鍧愭爣鏄互1涓鸿捣鐐圭殑缃戞牸绱㈠紩锛岃浆涓虹瑳鍗″皵鍧愭爣鐢诲浘鏃讹紝宸︿笅瑙掕鏄?x-1, y-1
        
        % 1. 璧风偣 (缁胯壊鏂瑰潡)
        rectangle('Position', [start_pos(2)-1, start_pos(1)-1, 1, 1], ...
                  'FaceColor', [0 0.8 0], 'EdgeColor', 'k', 'LineWidth', 1);
        text(start_pos(2)-0.5, start_pos(1)-0.5, '璧?, ...
             'Color', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        
        % 2. 鍙栬揣鐐?(钃濊壊鏂瑰潡)
        rectangle('Position', [pickup_pos(2)-1, pickup_pos(1)-1, 1, 1], ...
                  'FaceColor', [0 0.4 1], 'EdgeColor', 'k', 'LineWidth', 1);
        text(pickup_pos(2)-0.5, pickup_pos(1)-0.5, '鍙?, ...
             'Color', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        
        % 3. 閫佽揣鐐?(绾㈣壊鏂瑰潡)
        rectangle('Position', [dropoff_pos(2)-1, dropoff_pos(1)-1, 1, 1], ...
                  'FaceColor', [1 0.2 0.2], 'EdgeColor', 'k', 'LineWidth', 1);
        text(dropoff_pos(2)-0.5, dropoff_pos(1)-0.5, '閫?, ...
             'Color', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        
        % --- B. 缁樺埗璺緞绾?(淇濇寔涓嶅彉) ---
        % 涓轰簡濂界湅锛岃矾寰勭嚎绋嶅井鎶珮0.5锛岃瀹冪┛杩囨柟鏍肩殑涓績
        plot(path1(:,2)-0.5, path1(:,1)-0.5, 'Color', [0.2 0.8 0.2], 'LineWidth', 1, 'LineStyle', '--');
        plot(path2(:,2)-0.5, path2(:,1)-0.5, 'Color', [1 0.6 0], 'LineWidth', 1, 'LineStyle', '--');
        plot(path3(:,2)-0.5, path3(:,1)-0.5, 'Color', [1 0.6 0], 'LineWidth', 1, 'LineStyle', '--');
        % --- C. 鍔ㄧ敾婕旂ず ---
        animate_agv([path1; path2;path3]);
    else
        msgbox('渚濈劧鏃犳硶鎵惧埌璺緞锛屽彲鑳芥槸鍥犱负璧风偣琚殰纰嶇墿瀹屽叏鍖呭洿浜嗐€?, '閿欒');
    end
end




