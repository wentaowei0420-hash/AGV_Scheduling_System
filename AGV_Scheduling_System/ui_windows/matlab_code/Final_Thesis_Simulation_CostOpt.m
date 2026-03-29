function Final_Thesis_Simulation_CostOpt()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % =================================================================
    % 姣曚笟璁捐锛氬熀浜庢€绘垚鏈渶灏忓寲鐨勫AGV璋冨害涓庝豢鐪?
    % 浼樺寲鐩爣锛歁in(璺緞鎴愭湰 + 鑳借€楁垚鏈?+ 寤舵湡鎯╃綒)
    % =================================================================
    
    clc; clear; close all;
    
    %% --- 1. 绯荤粺鍒濆鍖栦笌鍙傛暟璁剧疆 ---
    disp('>> 绯荤粺鍒濆鍖栦腑...');
    
    global mapW mapH binaryMap
    mapW = 70; mapH = 50;
    binaryMap = create_binary_grid_map(mapW, mapH, 0); 
    
    % --- AGV 鐗╃悊鍙傛暟 ---
    num_agvs = 2;               
    agv_speed = 1.5;            % 閫熷害 (鏍?绉?
    battery_full = 100;         
    
    % --- 鑳借€楀弬鏁?(鍏抽敭妯″瀷) ---
    base_energy_rate = 0.02;    % 绌鸿浇鑰楃數 (%/鏍?
    load_energy_factor = 0.01;  % 璐熻浇绯绘暟: 姣忓鍔?kg閲嶉噺锛岃€楃數澧炲姞澶氬皯
    
    % --- 鎴愭湰鏉冮噸绯绘暟 ---
    w_dist = 1.0;               % 璺濈鎴愭湰鏉冮噸 (鍏?鏍?
    w_energy = 5.0;             % 鑳借€楁垚鏈潈閲?(鍏?%)
    w_penalty = 10.0;           % 寤舵湡鎯╃綒鏉冮噸 (鍏?绉?
    
    % 浣嶇疆瀹氫箟
    charge_stations = [2, 2; 39, 2]; 
    depots = [3, 7; 3, 11]; 
    
    % --- 浠诲姟鍒楄〃 (鏂板涓ゅ垪锛氶噸閲忋€佹埅姝㈡椂闂? ---
    % 鏍煎紡: {ID, 鐩爣宸ヤ綅ID, 璐х墿閲嶉噺(kg), 鎴鏃堕棿(绉?}
    task_list = [
        1, 1,  10, 200;   % 浠诲姟1: 鍘?鍙? 閲?0kg, 200绉掑唴閫佸埌
        2, 5,  5,  150;   % 浠诲姟2: 鍘?鍙? 杞昏揣, 鎴鏃堕棿绱?
        3, 8,  20, 300;   % 浠诲姟3: 鍘?鍙? 閲嶈揣
        4, 13, 15, 250;   % 浠诲姟4: 杞悜鏋?
        5, 16, 8,  180    % 浠诲姟5: 妯
    ];
    disp(['>> 鎺ユ敹鍒颁换鍔? ' num2str(size(task_list, 1)) ' 涓?(鍚噸閲忎笌鎴鏃堕棿)']);

    %% --- 2. 閬椾紶绠楁硶 (GA) 鎴愭湰浼樺寲 ---
    disp('>> 鍚姩鍩轰簬鎴愭湰浼樺寲鐨勮皟搴︾郴缁?..');
    
    pop_size = 50; max_gen = 80; mutation_rate = 0.15;
    
    % 缂栫爜鍒濆鍖?
    num_tasks = size(task_list, 1);
    len_chrom = num_tasks + num_agvs - 1;
    population = zeros(pop_size, len_chrom);
    for i = 1:pop_size
        base_perm = randperm(num_tasks);
        full_gene = [base_perm, zeros(1, num_agvs-1)];
        population(i, :) = full_gene(randperm(length(full_gene)));
    end
    
    % 杩涘寲寰幆
    best_cost_history = zeros(max_gen, 1);
    global_best_chrom = [];
    global_min_cost = inf;
    
    for gen = 1:max_gen
        costs = zeros(pop_size, 1);
        for i = 1:pop_size
            % 銆愭牳蹇冧慨鏀广€戣绠楁€绘垚鏈紝鑰岄潪鍗曠函鐨勬椂闂?
            costs(i) = calculate_total_cost(population(i,:), num_agvs, task_list, depots, ...
                                            agv_speed, base_energy_rate, load_energy_factor, ...
                                            w_dist, w_energy, w_penalty);
        end
        
        [min_cost, idx] = min(costs);
        if min_cost < global_min_cost
            global_min_cost = min_cost;
            global_best_chrom = population(idx, :);
        end
        best_cost_history(gen) = global_min_cost;
        
        % 绠€鍗曠殑閿︽爣璧涢€夋嫨涓庡彉寮?
        new_pop = population;
        for i = 1:pop_size
            if rand < mutation_rate
                pos = randperm(len_chrom, 2);
                new_pop(i, [pos(1), pos(2)]) = new_pop(i, [pos(2), pos(1)]);
            end
        end
        population = new_pop;
    end
    
    disp(['>> 浼樺寲瀹屾垚銆傛渶浣庣患鍚堟垚鏈? ' num2str(global_min_cost)]);
    
    %% --- 3. 瑙ｆ瀽鏈€浼樿皟搴?---
    agv_schedules = decode_chromosome(global_best_chrom, num_agvs);
        % 鎵撳嵃璋冨害缁撴灉
    for k = 1:num_agvs
        task_ids = agv_schedules{k};
        str = sprintf('AGV-%d 浠诲姟闃熷垪: ', k);
        if isempty(task_ids)
            str = [str '绌洪棽'];
        else
            for t = task_ids
                str = [str, sprintf('Task-%d(宸ヤ綅%d) -> ', t, task_list(t, 2))];
            end
        end
        disp(str);
    end
    
    %% --- 4. 鍙鍖栦豢鐪?---
    % === 绐楀彛 1: 宸ュ巶鍦板浘 (涓荤晫闈? ===
    generate_beautiful_factory_map(); % 涓嶆帴鏀惰繑鍥炲€?
    f_map = gcf; % gcf = Get Current Figure (鑾峰彇鍒氬垰寮瑰嚭鐨勯偅涓獥鍙?
    set(f_map, 'Name', '涓荤洃鎺х晫闈? 璺緞璺熻釜', 'NumberTitle', 'off', 'Position', [50, 200, 1000, 700]);
    title('澶欰GV鏅鸿兘璋冨害瀹炴椂鐩戞帶绯荤粺');
    
    f_batt = figure('Name', '鐢甸噺鐩戞帶', 'NumberTitle', 'off', 'Position', [1060, 200, 400, 300], 'Color', 'w');
    b_handle = bar(1:num_agvs, ones(1,num_agvs)*100, 0.5); 
    title('AGV 瀹炴椂鐢甸噺'); ylim([0 100]); b_handle.FaceColor = 'flat';
    
    figure(f_map);
    AGVs = struct([]);
    for k = 1:num_agvs
        AGVs(k).id = k;
        AGVs(k).pos = depots(k, :);        
        AGVs(k).battery = battery_full;    
        AGVs(k).tasks = agv_schedules{k};  
        AGVs(k).status = 'Idle';           
        AGVs(k).path = [];                 
        AGVs(k).path_idx = 1;
        AGVs(k).current_load = 0; % 褰撳墠璐熻浇閲嶉噺
        
        px = AGVs(k).pos(2); py = AGVs(k).pos(1);
        AGVs(k).handle = rectangle('Position', [px-0.9, py-0.9, 0.8, 0.8], ...
            'Curvature', 0.2, 'FaceColor', [0.2 0.8 0.2], 'EdgeColor', 'k', 'LineWidth', 1);
        AGVs(k).text_handle = text(px-0.5, py-0.5, ['ID:' num2str(k)], ...
            'Color', 'k', 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end
    
    sim_running = true; 
    
    while sim_running
        sim_running = false; 
        current_batteries = zeros(1, num_agvs);
        
        for k = 1:num_agvs
            if isempty(AGVs(k).path)
                % [鍐崇瓥閫昏緫]
                if ~isempty(AGVs(k).tasks)
                    task_idx = AGVs(k).tasks(1);
                    target_id = task_list(task_idx, 2);
                    task_weight = task_list(task_idx, 3); % 鑾峰彇閲嶉噺
                    
                    tempMap = create_binary_grid_map(mapW, mapH, target_id);
                    % 瑙ｉ攣璧风偣
                    cy = round(AGVs(k).pos(1)); cx = round(AGVs(k).pos(2));
                    if cy>=1 && cy<=mapH && cx>=1 && cx<=mapW, tempMap(cy, cx)=0; end

                    if strcmp(AGVs(k).status, 'Idle') || strcmp(AGVs(k).status, 'Task_Done') || strcmp(AGVs(k).status, 'Backing_Garage')
                        AGVs(k).status = 'Moving_Pick';
                        AGVs(k).current_load = 0; % 鍘诲彇璐ф椂鏄┖杞?
                        [pickup, ~] = get_task_coordinates(target_id);
                        if tempMap(pickup(1), pickup(2))==1, tempMap(pickup(1), pickup(2))=0; end
                        [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, pickup, 0.7);
                        AGVs(k).path = p;
                        AGVs(k).path_idx = 1;
                        
                    elseif strcmp(AGVs(k).status, 'Picked_Up')
                        AGVs(k).status = 'Moving_Drop';
                        AGVs(k).current_load = task_weight; % 瑁呰揣锛岃礋杞藉鍔?
                        [~, dropoff] = get_task_coordinates(target_id);
                        [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, dropoff, 0.7);
                        AGVs(k).path = p;
                        AGVs(k).path_idx = 1;
                    end
                elseif AGVs(k).battery < 20
                     % ... (鍏呯數閫昏緫鍚屽墠) ...
                    AGVs(k).status = 'Going_Charge';
                    tempMap = create_binary_grid_map(mapW, mapH, 0);
                    % 瑙ｉ攣褰撳墠浣嶇疆
                    cur_y = round(AGVs(k).pos(1)); cur_x = round(AGVs(k).pos(2));
                    tempMap(cur_y, cur_x) = 0;
                    [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, charge_stations(1,:), 0.7);
                    AGVs(k).path = p;
                    AGVs(k).path_idx = 1;
                else
                     % ... (鍥炶溅搴撻€昏緫鍚屽墠) ...
                     if ~strcmp(AGVs(k).status, 'Backing_Garage') && ~strcmp(AGVs(k).status, 'Idle')
                        dist = sum(abs(AGVs(k).pos - depots(k,:)));
                        if dist > 1
                             AGVs(k).status = 'Backing_Garage';
                             AGVs(k).current_load = 0; % 绌鸿浇鍥炲
                             tempMap = create_binary_grid_map(mapW, mapH, 0);
                             cy = round(AGVs(k).pos(1)); cx = round(AGVs(k).pos(2)); tempMap(cy, cx)=0;
                             [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, depots(k,:), 0.7);
                             AGVs(k).path = p; AGVs(k).path_idx = 1;
                        else
                             AGVs(k).status = 'Idle';
                        end
                     end
                end
            end
            
            % [绉诲姩鎵ц]
            if ~isempty(AGVs(k).path)
                sim_running = true; 
                if AGVs(k).path_idx <= size(AGVs(k).path, 1)
                    next_pos = AGVs(k).path(AGVs(k).path_idx, :);
                    AGVs(k).pos = next_pos;
                    AGVs(k).path_idx = AGVs(k).path_idx + 1;
                    
                    % === 銆愬叧閿€戝姩鎬佽兘鑰楄绠?===
                    % 鑰楃數閲?= 鍩虹鑰楃數 + 璐熻浇绯绘暟 * 閲嶉噺
                    current_consume = base_energy_rate + load_energy_factor * AGVs(k).current_load;
                    AGVs(k).battery = AGVs(k).battery - current_consume;
                    
                    % 鏇存柊鍥惧舰
                    px = next_pos(2); py = next_pos(1);
                    set(AGVs(k).handle, 'Position', [px-0.9, py-0.9, 0.8, 0.8]);
                    set(AGVs(k).text_handle, 'Position', [px-0.5, py-0.5]);
                    
                    % 鐘舵€侀鑹?
                    if AGVs(k).current_load > 0
                        set(AGVs(k).handle, 'FaceColor', [1 0.6 0]); % 杞介噸鏃舵繁姗欒壊
                    else
                        set(AGVs(k).handle, 'FaceColor', [0.2 0.8 0.2]); % 绌鸿浇缁胯壊
                    end
                else
                     % 鍒拌揪閫昏緫
                    AGVs(k).path = [];
                    if strcmp(AGVs(k).status, 'Moving_Pick'), AGVs(k).status = 'Picked_Up'; pause(0.05); 
                    elseif strcmp(AGVs(k).status, 'Moving_Drop'), AGVs(k).status = 'Task_Done'; AGVs(k).tasks(1)=[]; pause(0.05);
                    elseif strcmp(AGVs(k).status, 'Backing_Garage'), AGVs(k).status = 'Idle'; end
                end
            end
            current_batteries(k) = AGVs(k).battery;
        end
        
        if isvalid(f_batt)
             set(b_handle, 'YData', current_batteries);
             % 鍙樿壊閫昏緫鐣?
        end
        drawnow limitrate;
        pause(0.05)
    end
end

%% ================= 鏍稿績绠楁硶鍑芥暟搴?=================

% --- 瑙ｇ爜 ---
function schedules = decode_chromosome(chrom, num_agvs)
    schedules = cell(1, num_agvs);
    current_agv = 1;
    for gene = chrom
        if gene == 0
            current_agv = current_agv + 1;
        else
            schedules{current_agv} = [schedules{current_agv}, gene];
        end
    end
end

% --- 銆愭牳蹇冦€戞€绘垚鏈绠楀嚱鏁?---
function total_cost = calculate_total_cost(chrom, num_agvs, tasks, depots, speed, e_base, e_load, w1, w2, w3)
    schedules = decode_chromosome(chrom, num_agvs);
    
    total_dist = 0;
    total_energy = 0;
    total_penalty = 0;
    
    for k = 1:num_agvs
        task_ids = schedules{k};
        if isempty(task_ids), continue; end
        
        current_pos = depots(k, :); % 閫昏緫鍧愭爣
        current_time = 0;
        
        for t_id = task_ids
            target_id = tasks(t_id, 2);
            weight = tasks(t_id, 3);
            deadline = tasks(t_id, 4);
            
            [pickup, dropoff] = get_task_coordinates(target_id);
            
            % 1. 绌鸿浇琛岄┒ (鍘诲彇璐?
            % 杩欓噷涓轰簡閫熷害锛岀敤鏇煎搱椤胯窛绂讳唬鏇?A* (GA杩唬涓繀椤诲揩)
            dist_empty = sum(abs(current_pos - pickup)); 
            time_empty = dist_empty / speed;
            energy_empty = dist_empty * e_base;
            
            % 2. 璐熻浇琛岄┒ (鍘婚€佽揣)
            dist_loaded = sum(abs(pickup - dropoff));
            time_loaded = dist_loaded / speed;
            % 銆愯兘鑰楁ā鍨嬨€戯細璐熻浇瓒婇噸锛岃€楃數瓒婂
            energy_loaded = dist_loaded * (e_base + e_load * weight);
            
            % 鏇存柊鐘舵€?
            current_pos = dropoff;
            current_time = current_time + time_empty + time_loaded + 5; % +5s 瑁呭嵏鏃堕棿
            
            % 3. 璁＄畻鎯╃綒
            if current_time > deadline
                penalty = (current_time - deadline) * w3; % 瓒呮椂缃氭
            else
                penalty = 0;
            end
            
            % 绱姞鍚勯」鎴愭湰
            total_dist = total_dist + dist_empty + dist_loaded;
            total_energy = total_energy + energy_empty + energy_loaded;
            total_penalty = total_penalty + penalty;
        end
    end
    
    % 鎬绘垚鏈叕寮?
    total_cost = (w1 * total_dist) + (w2 * total_energy) + total_penalty;
end

% --- 闇€瑕佺矘璐寸殑鍏朵粬鍑芥暟 ---
% 璇峰姟蹇呭湪涓嬫柟绮樿创: 
% 1. get_task_coordinates
% 2. create_binary_grid_map
% 3. astar_planner_turn (浼樺寲鐗?
% 4. generate_beautiful_factory_map
% 5. 杈呭姪缁樺浘鍑芥暟


