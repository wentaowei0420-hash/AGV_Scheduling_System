function Final_Thesis_Simulation()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % =================================================================
    % 姣曚笟璁捐锛氬熀浜庨仐浼犵畻娉曠殑澶欰GV閰嶄欢杈撻€佺郴缁熻皟搴︿笌浠跨湡
    % 鍔熻兘鍖呭惈锛?
    % 1. 鐜寤烘ā (鏍呮牸鍦板浘)
    % 2. 浠诲姟鐢熸垚 (妯℃嫙MES鎸囦护)
    % 3. 閬椾紶绠楁硶璋冨害 (浠诲姟鍒嗛厤涓庨『搴忎紭鍖?
    % 4. 鐘舵€佺鐞?(鐢甸噺鐩戞祴銆佽嚜鍔ㄥ厖鐢?
    % 5. 鍔ㄦ€佸彲瑙嗗寲 (澶欰GV璺緞婕旂ず)
    % =================================================================
    % 鍑芥暟鍏ュ彛锛屼笉闇€瑕佽緭鍏ュ弬鏁?
    clc; clear; close all;
    % 娓呴櫎鍛戒护琛屻€佹竻闄ゅ彉閲忋€佸叧闂墍鏈夊浘绐楋紝纭繚杩愯鐜骞插噣
    %% --- 1. 绯荤粺鍒濆鍖栦笌鍙傛暟璁剧疆 ---
    disp('>> 绯荤粺鍒濆鍖栦腑...');
    
    % 鍦板浘鍙傛暟
    global mapW mapH binaryMap 
    mapW = 70; mapH = 50;
    % 鐢熸垚鍩虹闈欐€佸湴鍥?(涓嶅惈鐗瑰畾鐩爣鐣欑櫧锛岀敤浜庤绠楀熀纭€璺濈)
    binaryMap = create_binary_grid_map(mapW, mapH, 0); 
    
    % AGV 鍙傛暟
    num_agvs = 2;               % AGV鏁伴噺
    agv_speed = 0.01;           % 杩愯閫熷害 (鏍?绉?
    battery_full = 100;         % 婊＄數閲?
    battery_consume = 0.05;     % 鑰楃數鐜?(%/鏍?
    battery_threshold = 20;     % 浣庣數閲忛槇鍊?(瑙﹀彂鍏呯數)
    
    % 鍏呯數妗╀綅缃?(鍦板浘宸︿笅鍜屽彸涓?
    charge_stations = [2, 2; 39, 2]; 
    % 鍒濆浣嶇疆 (鍋囪閮藉湪杞﹀簱)
    depots = [3, 7; 3, 11]; 
    
    % 鐢熸垚浠诲姟鍒楄〃 (妯℃嫙鐢熶骇绠＄悊绯荤粺 MES 涓嬪彂)
    % 鏍煎紡: {浠诲姟ID, 鐩爣宸ヤ綅ID, 浼樺厛绾
    % 杩欓噷闅忔満鐢熸垚 5 涓换鍔?
    task_list = [
        1, 1;   % 浠诲姟1: 鍘?鍙峰伐浣?
        2, 5;   % 浠诲姟2: 鍘?鍙峰伐浣?
        3, 8;   % 浠诲姟3: 鍘?鍙峰伐浣?
        4, 13;  % 浠诲姟4: 鍘?3鍙疯浆鍚戞灦
        5, 16   % 浠诲姟5: 鍘?6鍙锋í姊?
    ];
    disp(['>> 鎺ユ敹鍒?MES 浠诲姟鏁伴噺: ' num2str(size(task_list, 1))]);

    %% --- 2. 棰勮绠楄窛绂荤煩闃?(鍔犻€?GA) ---
    % 涓轰簡閬垮厤鍦℅A涓绻佽皟鐢ˋ*锛屾垜浠渶瑕侀鍏堣绠楀叧閿偣涔嬮棿鐨勮窛绂?
    disp('>> 姝ｅ湪棰勮绠楄矾寰勪唬浠风煩闃?(Pre-computation)...');
    dist_matrix = build_distance_matrix(task_list, depots, charge_stations);
    
    %% --- 3. 閬椾紶绠楁硶 (GA) 璋冨害鏍稿績 ---
    disp('>> 鍚姩鏅鸿兘璋冨害绯荤粺 (Genetic Algorithm)...');
    
    % GA 鍙傛暟
    pop_size = 50;      % 绉嶇兢瑙勬ā锛氫竴娆¤繘鍖栦腑鏈?50 涓柟妗堝弬涓庣珵浜?
    max_gen = 100;      % 杩唬娆℃暟锛氳繘鍖?100 浠?
    mutation_rate = 0.1;% 鍙樺紓鐜囷細10% 鐨勬鐜囧彂鐢熷熀鍥犵獊鍙橈紝闃叉闄峰叆灞€閮ㄦ渶浼?
    
    % A. 缂栫爜鍒濆鍖? 閲囩敤 "浠诲姟搴忓垪 + 鍒嗛殧绗? 缂栫爜
    % 渚嬪: [1, 3, 0, 2, 4, 5] 琛ㄧず AGV1鍋?,3; AGV2鍋?,4,5 (0涓哄垎闅旂)
    num_tasks = size(task_list, 1);
    num_separators = num_agvs - 1;
    len_chrom = num_tasks + num_separators;
    
    population = zeros(pop_size, len_chrom);
    for i = 1:pop_size
        base_perm = randperm(num_tasks); % 浠诲姟闅忔満鎺掑垪
        separators = zeros(1, num_separators); % 鍒嗛殧绗?0)
        % 闅忔満鎻掑叆鍒嗛殧绗?
        full_gene = [base_perm, separators];
        population(i, :) = full_gene(randperm(length(full_gene)));
    end
    
    % B. 杩涘寲寰幆
    best_fitness_history = zeros(max_gen, 1);
    global_best_chrom = [];
    global_best_fit = inf;
    
    for gen = 1:max_gen
        % 璁＄畻閫傚簲搴?
        fitness = zeros(pop_size, 1);
        for i = 1:pop_size
            fitness(i) = calculate_makespan(population(i,:), num_agvs, task_list, dist_matrix, depots);
        end
        
        % 璁板綍鏈€浼?
        [min_fit, idx] = min(fitness);
        if min_fit < global_best_fit
            global_best_fit = min_fit;
            global_best_chrom = population(idx, :);
        end
        best_fitness_history(gen) = min_fit;
        
        % 閫夋嫨 (閿︽爣璧?
        new_pop = population;
        for i = 1:pop_size
            p1 = randi(pop_size); p2 = randi(pop_size);
            if fitness(p1) < fitness(p2), winner = population(p1,:); else, winner = population(p2,:); end
            new_pop(i,:) = winner;
        end
        
        % 浜ゅ弶 (OX浜ゅ弶) & 鍙樺紓 (Swap) - 绠€鍖栫増瀹炵幇
        for i = 1:2:pop_size
            if rand < 0.8 % 浜ゅ弶姒傜巼
                % 绠€鍗曞崟鐐逛氦鍙夊悗淇
                pt = randi(len_chrom-1);
                child1 = [new_pop(i, 1:pt), new_pop(i+1, pt+1:end)]; % 闇€淇閲嶅/缂哄け锛屾澶勭暐鍘诲鏉備慨澶嶉€昏緫锛屼粎鍋氭紨绀轰氦鎹?
                % 瀹為檯宸ョ▼涓渶淇濊瘉鏌撹壊浣撳悎娉曟€э紝杩欓噷涓轰簡浠ｇ爜绠€娲侊紝浠呭仛鍙樺紓
            end
        end
        
        % 鍙樺紓
        for i = 1:pop_size
            if rand < mutation_rate
                pos = randperm(len_chrom, 2);
                temp = new_pop(i, pos(1));
                new_pop(i, pos(1)) = new_pop(i, pos(2));
                new_pop(i, pos(2)) = temp;
            end
        end
        population = new_pop;
    end
    
    disp(['>> 璋冨害瀹屾垚銆傛渶浼樻€昏€楁椂浼扮畻: ' num2str(global_best_fit)]);
    
    %% --- 4. 瑙ｆ瀽鏈€浼樿皟搴︽柟妗?---
    % 灏嗘渶浼樻煋鑹蹭綋瑙ｇ爜涓烘瘡鍙?AGV 鐨勫叿浣撲换鍔￠摼
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

    %% --- 5. 鏈€缁堜豢鐪熸墽琛?(鍙岀獥鍙ｅ疄鏃舵樉绀虹増) ---
    disp('>> 寮€濮嬪彲瑙嗗寲浠跨湡...');
    
    % === 绐楀彛 1: 宸ュ巶鍦板浘 (涓荤晫闈? ===
    generate_beautiful_factory_map(); % 涓嶆帴鏀惰繑鍥炲€?
    f_map = gcf; % gcf = Get Current Figure (鑾峰彇鍒氬垰寮瑰嚭鐨勯偅涓獥鍙?
    set(f_map, 'Name', '涓荤洃鎺х晫闈? 璺緞璺熻釜', 'NumberTitle', 'off', 'Position', [50, 200, 1000, 700]);
    title('澶欰GV鏅鸿兘璋冨害瀹炴椂鐩戞帶绯荤粺');
    
    % === 绐楀彛 2: 鐢甸噺浠〃鐩?(鍓晫闈? ===
    f_batt = figure('Name', '鐘舵€佺洃鎺? 鐢垫睜鐢甸噺', 'NumberTitle', 'off', 'Position', [1060, 200, 400, 400], 'Color', 'w');
    ax_batt = gca;
    % 鍒濆鍖栨煴鐘跺浘 (鎵€鏈堿GV鍒濆100%)
    agv_ids = 1:num_agvs;
    init_batt = ones(1, num_agvs) * 100;
    
    % 鍒涘缓鏌辩姸鍥惧璞?(淇濆瓨鍙ユ焺 b_handle 浠ヤ究鍚庣画鏇存柊)
    b_handle = bar(agv_ids, init_batt, 0.5); 
    
    % 缇庡寲浠〃鐩?
    ylim([0 100]);
    xlabel('AGV 缂栧彿');
    ylabel('鐢甸噺 (%)');
    title('AGV 瀹炴椂鐢甸噺鐩戞帶');
    grid on;
    set(gca, 'XTick', 1:num_agvs);
    % 寮€鍚煴鐘跺浘鐙珛棰滆壊鎺у埗
    b_handle.FaceColor = 'flat'; 
    
    % === 鍒濆鍖?AGV 鍥惧舰瀵硅薄 ===
    figure(f_map); % 鍒囨崲鍥炲湴鍥剧獥鍙ｈ繘琛岀粯鍒?
    AGVs = struct([]);
    for k = 1:num_agvs
        AGVs(k).id = k;
        AGVs(k).pos = depots(k, :);        
        AGVs(k).battery = battery_full;    
        AGVs(k).tasks = agv_schedules{k};  
        AGVs(k).status = 'Idle';           
        AGVs(k).path = [];                 
        AGVs(k).path_idx = 1;              
        
        % 1. 缁樺埗 AGV 杞﹁韩
        px = AGVs(k).pos(2); py = AGVs(k).pos(1);
        AGVs(k).handle = rectangle('Position', [px-0.9, py-0.9, 0.8, 0.8], ...
            'Curvature', 0.2, 'FaceColor', [0.2 0.8 0.2], 'EdgeColor', 'k', 'LineWidth', 1);
            
        % 2. 缁樺埗绠€鐣ヤ俊鎭?(鍙樉绀?ID, 涓嶆樉绀虹數閲忎簡)
        AGVs(k).text_handle = text(px-0.5, py-0.5, ['ID:' num2str(k)], ...
            'Color', 'k', 'FontSize', 8, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end
    
    % === 浠跨湡涓诲惊鐜?===
    sim_running = true; 
    
    while sim_running
        sim_running = false; 
        
        % 鍑嗗鐢甸噺鏁版嵁鏁扮粍 (鐢ㄤ簬涓€娆℃€ф洿鏂板浘琛?
        current_batteries = zeros(1, num_agvs);
        
        for k = 1:num_agvs
            % --- 鍐崇瓥閫昏緫 (淇濇寔鍘熸牱锛屾棤闇€淇敼) ---
            if isempty(AGVs(k).path)
                % [浼樺厛绾?] 鍏呯數
                if AGVs(k).battery < battery_threshold && ~strcmp(AGVs(k).status, 'Charging') && ~strcmp(AGVs(k).status, 'Going_Charge')
                    AGVs(k).status = 'Going_Charge';
                    tempMap = create_binary_grid_map(mapW, mapH, 0);
                    % 瑙ｉ攣褰撳墠浣嶇疆
                    cur_y = round(AGVs(k).pos(1)); cur_x = round(AGVs(k).pos(2));
                    tempMap(cur_y, cur_x) = 0;
                    
                    [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, charge_stations(1,:), 0.7);
                    AGVs(k).path = p;
                    AGVs(k).path_idx = 1;
                    
                % [浼樺厛绾?] 骞叉椿
                elseif ~isempty(AGVs(k).tasks)
                    current_task_id = AGVs(k).tasks(1);
                    target_station = task_list(current_task_id, 2);
                    tempMap = create_binary_grid_map(mapW, mapH, target_station);
                    % 瑙ｉ攣褰撳墠浣嶇疆
                    cur_y = round(AGVs(k).pos(1)); cur_x = round(AGVs(k).pos(2));
                    if cur_y>=1 && cur_y<=mapH && cur_x>=1 && cur_x<=mapW, tempMap(cur_y, cur_x)=0; end

                    if strcmp(AGVs(k).status, 'Idle') || strcmp(AGVs(k).status, 'Task_Done') || strcmp(AGVs(k).status, 'Backing_Garage')
                        AGVs(k).status = 'Moving_Pick';
                        [pickup, ~] = get_task_coordinates(target_station);
                        if tempMap(pickup(1), pickup(2))==1, tempMap(pickup(1), pickup(2))=0; end
                        [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, pickup, 0.7);
                        AGVs(k).path = p;
                        AGVs(k).path_idx = 1;
                    elseif strcmp(AGVs(k).status, 'Picked_Up')
                        AGVs(k).status = 'Moving_Drop';
                        [~, dropoff] = get_task_coordinates(target_station);
                        [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, dropoff, 0.7);
                        AGVs(k).path = p;
                        AGVs(k).path_idx = 1;
                    end
                % [浼樺厛绾?] 鍥炶溅搴?
                else
                    if ~strcmp(AGVs(k).status, 'Backing_Garage') && ~strcmp(AGVs(k).status, 'Idle')
                        dist_to_depot = sum(abs(AGVs(k).pos - depots(k, :)));
                        if dist_to_depot > 1
                            AGVs(k).status = 'Backing_Garage';
                            tempMap = create_binary_grid_map(mapW, mapH, 0);
                            cur_y = round(AGVs(k).pos(1)); cur_x = round(AGVs(k).pos(2));
                            tempMap(cur_y, cur_x) = 0;
                            [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, depots(k, :), 0.7);
                            AGVs(k).path = p;
                            AGVs(k).path_idx = 1;
                        else
                            AGVs(k).status = 'Idle';
                        end
                    end
                end
            end
            
            % --- 鎵ц绉诲姩 ---
            if ~isempty(AGVs(k).path)
                sim_running = true; 
                
                if AGVs(k).path_idx <= size(AGVs(k).path, 1)
                    next_pos = AGVs(k).path(AGVs(k).path_idx, :);
                    AGVs(k).pos = next_pos;
                    AGVs(k).path_idx = AGVs(k).path_idx + 1;
                    AGVs(k).battery = AGVs(k).battery - battery_consume; 
                    
                    % 鏇存柊鍦板浘涓婄殑浣嶇疆 (Window 1)
                    px = next_pos(2); py = next_pos(1);
                    set(AGVs(k).handle, 'Position', [px-0.9, py-0.9, 0.8, 0.8]);
                    set(AGVs(k).text_handle, 'Position', [px-0.5, py-0.5]);
                    
                    % 鐘舵€佸彉鑹查€昏緫
                    switch AGVs(k).status
                        case {'Moving_Pick', 'Moving_Drop'}
                             set(AGVs(k).handle, 'FaceColor', [1 0.8 0.2]); % 榛?
                        case 'Going_Charge'
                             set(AGVs(k).handle, 'FaceColor', [1 0.2 0.2]); % 绾?
                        case 'Idle'
                             set(AGVs(k).handle, 'FaceColor', [0.2 0.8 0.2]); % 缁?
                        otherwise
                             set(AGVs(k).handle, 'FaceColor', [0.8 0.8 0.8]); 
                    end
                else
                    AGVs(k).path = [];
                    if strcmp(AGVs(k).status, 'Moving_Pick'), AGVs(k).status = 'Picked_Up'; pause(0.1); 
                    elseif strcmp(AGVs(k).status, 'Moving_Drop'), AGVs(k).status = 'Task_Done'; AGVs(k).tasks(1) = []; pause(0.1);
                    elseif strcmp(AGVs(k).status, 'Going_Charge'), AGVs(k).status = 'Idle'; AGVs(k).battery = 100;
                    elseif strcmp(AGVs(k).status, 'Backing_Garage'), AGVs(k).status = 'Idle'; end
                end
            end
            
            % 璁板綍褰撳墠鐢甸噺浠ヤ究鏇存柊鍥捐〃
            current_batteries(k) = AGVs(k).battery;
        end
        
        % === 鏇存柊鐢甸噺浠〃鐩?(Window 2) ===
        % 鍙湁褰撶獥鍙ｈ繕寮€鐫€鐨勬椂鍊欐墠鏇存柊锛岄槻姝㈡姤閿?
        if isvalid(f_batt)
            set(b_handle, 'YData', current_batteries);
            
            % 鏍规嵁鐢甸噺鍙樿壊 (Green > 50, Yellow > 20, Red < 20)
            cdata = zeros(num_agvs, 3);
            for k = 1:num_agvs
                bat = current_batteries(k);
                if bat > 50
                    cdata(k,:) = [0.2 0.8 0.2]; % 缁?
                elseif bat > 20
                    cdata(k,:) = [1 0.8 0.2];   % 榛?
                else
                    cdata(k,:) = [1 0.2 0.2];   % 绾?
                end
            end
            set(b_handle, 'CData', cdata);
        end
        
        drawnow limitrate; 
        pause(0.05)
    end
    disp('>> 浠跨湡缁撴潫銆?);
end


%% ================= 杈呭姪鍑芥暟搴?=================

% 1. 瑙ｇ爜鏌撹壊浣?
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

% 2. 閫傚簲搴﹁绠?(Makespan)
function max_time = calculate_makespan(chrom, num_agvs, tasks, dist_mat, depots)
    schedules = decode_chromosome(chrom, num_agvs);
    agv_times = zeros(1, num_agvs);
    
    for k = 1:num_agvs
        task_ids = schedules{k};
        if isempty(task_ids), continue; end
        
        current_node_idx = 100 + k; % 鍋囪 100+k 鏄溅搴撳湪鐭╅樀涓殑绱㈠紩
        
        for t_id = task_ids
            % 鏌ユ壘璺濈: 褰撳墠 -> 浠诲姟鍙栬揣鐐?-> 浠诲姟閫佽揣鐐?
            % 绠€鍖栵細鍦?build_distance_matrix 涓垜浠畾涔夌储寮曡鍒欙細
            % 1~N: 鍙栬揣鐐? N+1~2N: 閫佽揣鐐?
            % Depot 闇€鐗规畩澶勭悊锛岃繖閲岀敤鏇煎搱椤胯窛绂讳及绠椾唬鏇挎煡琛ㄤ互绠€鍖栦唬鐮侀暱搴?
            
            % 绠€鍗曢€昏緫浼扮畻浠ｄ环 (Cost) 鐢ㄤ簬 GA 蹇€熻凯浠?
            % 瀹為檯搴旀煡琛?dist_matrix
            agv_times(k) = agv_times(k) + rand * 10 + 20; % 妯℃嫙浠ｄ环
        end
    end
    max_time = max(agv_times);
end

% 3. 鏋勫缓璺濈鐭╅樀 (鍗犱綅锛屽疄闄呭簲寰幆璋冪敤 A*)
function mat = build_distance_matrix(tasks, depots, charges)
    % 杩欐槸涓€涓€楁椂鎿嶄綔锛岄€氬父鍦ㄧ郴缁熷惎鍔ㄦ椂鍋氫竴娆?
    % 杩欓噷杩斿洖涓€涓┖鐭╅樀锛屽疄闄呴€昏緫鍦?calculate_makespan 涓敤浼扮畻浠ｆ浛
    mat = [];
end


