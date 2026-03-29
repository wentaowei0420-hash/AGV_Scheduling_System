%% === 妯″潡 3: 瀹炴椂瑙勫垝涓庝豢鐪熷惊鐜?(浠ｇ爜娣卞害閲嶆瀯鐗?- 澶氳浇閲嶅垪闃熺増) ===
function run_visualization_loop(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % 瀹炴椂浠跨湡涓诲惊鐜嚱鏁帮紝璐熻矗鍙鍖栨墍鏈堿GV鐨勮繍鍔ㄣ€佷换鍔℃墽琛屻€佸厖鐢点€佸啿绐佹秷瑙ｇ瓑銆?
    
    global mapW mapH binaryMap; 
    
    % --- 1. 鍒濆鍖栧浘褰㈢晫闈?---
    generate_beautiful_factory_map();   
    f_map = gcf;                        
    ax = findobj(f_map, 'Type', 'Axes'); 
    hold(ax, 'on');                      
    set(f_map, 'Name', '瀹炴椂鍔ㄦ€佽皟搴︿豢鐪?, 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', 'Position', [50, 200, 1000, 700]);
    
    [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs);
    
    % --- 2. 鍒濆鍖?AGV 瀵硅薄 ---
    [AGVs, props, ~] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax);
    
    % --- 3. 瀹炴椂浠跨湡涓诲惊鐜?---
    disp('>> [绯荤粺] 瀹炴椂浠跨湡鍚姩...'); 
    
    % ========================================================
    % 銆愭柊澧?1銆戯細鍒濆鍖栧杞借嵎闃熷垪涓庣姸鎬佽蹇?
    for k = 1:num_agvs
        AGVs(k).total_turns = 0;           % 杩愯杞集鎬绘暟
        AGVs(k).last_dir = [0, 0];         % 涓婁竴姝ユ柟鍚戠煝閲?
        
        AGVs(k).pick_queue = [];           % 鍙栬揣浠诲姟闃熷垪
        AGVs(k).drop_queue = [];           % 鍗歌揣浠诲姟闃熷垪
        AGVs(k).active_task_id = 0;        % 褰撳墠姝ｅ湪瀵艰埅鐨勫叿浣撳瓙浠诲姟ID
        AGVs(k).interrupted_status = '';   % 璁板繂鍥犳病鐢靛幓鍏呯數鍓嶈涓柇鐨勭姸鎬?
    end
    % ========================================================
    
    OccupancyGrid = zeros(mapH, mapW);  
    for k = 1:num_agvs
        OccupancyGrid(AGVs(k).pos(1), AGVs(k).pos(2)) = k; 
    end
    
    sim_running = true;      
    MAX_STEPS = 500000;      
    t = 0;                   
    frames_per_step = 2;
    max_task_id = max(task_list(:,1));
    task_times = zeros(max_task_id, 2); 
    task_executor = zeros(max_task_id, 1);     
    task_start_dist = zeros(max_task_id, 1);   
    task_dist_record = zeros(max_task_id, 1);  
    for k = 1:num_agvs, AGVs(k).total_dist = 0; end
    task_trajectories = cell(max_task_id, 1);
    while sim_running && t < MAX_STEPS   
        t = t + 1;                       
        all_finished = true;              
        % --- A. 閫昏緫鏇存柊 ---
        for k = 1:num_agvs                
            if AGVs(k).move_timer > 0      
                AGVs(k).move_timer = AGVs(k).move_timer - 1; 
                all_finished = false;       
                continue;                    
            end
            
            % 鍔ㄦ€佽缃笓灞炶溅浣?鍏呯數妗╁昂瀵?
            if AGVs(k).type == 2
                agv_area_sz = [3, 3]; % 鍙夎溅澶у昂瀵?
            else
                agv_area_sz = [2, 2]; % 鎵樹妇灏忓昂瀵?
            end
            
            % 鏍规嵁褰撳墠鐘舵€佹墽琛岀浉搴旇涓?
            switch AGVs(k).status
                case 'Idle'   % 绌洪棽鐘舵€?
                    if AGVs(k).battery < 20   
                        plan_to_charge(k);     
                        all_finished = false;
                        
                    elseif AGVs(k).active_task_id > 0
                        tid = AGVs(k).active_task_id;
                        row_idx = find(task_list(:,1) == tid);
                        target_id = task_list(row_idx, 2);
                        
                        if strcmp(AGVs(k).interrupted_status, 'Moving_Drop')
                            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id);
                            if plan_path(k, drop_anchor, drop_size) 
                                AGVs(k).status = 'Moving_Drop';
                                AGVs(k).interrupted_status = ''; 
                            end
                        elseif strcmp(AGVs(k).interrupted_status, 'Moving_Pick')
                            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id);
                            if plan_path(k, pick_anchor, pick_size)
                                AGVs(k).status = 'Moving_Pick';
                                AGVs(k).interrupted_status = '';
                            end     
                        else
                            AGVs(k).active_task_id = 0; % 闈炴硶璁板繂鍒欓噸缃?
                        end
                        all_finished = false;
                        
                    elseif ~isempty(AGVs(k).tasks)  
                        % ======================================================
                        % 銆愭柊澧炴牳蹇冦€戯細鎵归噺缁勮璁㈠崟閫昏緫 (Type 1 澶氫欢锛孴ype 2 鍗曚欢)
                        max_load_capacity = 80; % 鎵樹妇杞︽渶澶ц浇閲嶄笂闄?(鍙皟)
                        batch_tasks = [];
                        current_batch_weight = 0;
                        
                        for i = 1:length(AGVs(k).tasks)
                            tid = AGVs(k).tasks(i);
                            row_idx = find(task_list(:,1) == tid);
                            w = task_list(row_idx, 3);
                            
                            % 銆愮墿鐞嗙害鏉熴€戯細鍙夎溅(Type 2) 涓€娆′弗鏍煎彧鎷変竴涓紒
                            if AGVs(k).type == 2 && i > 1
                                break; 
                            end
                            
                            % 銆愮墿鐞嗙害鏉熴€戯細鎵樹妇杞?Type 1) 鏍规嵁杞介噸涓€鐩村線閲屽
                            if i == 1 || (current_batch_weight + w <= max_load_capacity)
                                batch_tasks = [batch_tasks, tid];
                                current_batch_weight = current_batch_weight + w;
                            else
                                break; % 瓒呴噸锛屾埅鏂綋鍓嶆壒娆?
                            end
                        end
                        
                        AGVs(k).pick_queue = batch_tasks;
                        AGVs(k).drop_queue = batch_tasks;
                        
                        % 寮瑰嚭绗竴涓换鍔★紝鍓嶅線鍙栬揣鐐?
                        first_tid = AGVs(k).pick_queue(1);
                        AGVs(k).pick_queue(1) = [];
                        AGVs(k).active_task_id = first_tid;
                        
                        row_idx = find(task_list(:,1) == first_tid);
                        target_id = task_list(row_idx, 2);
                        [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); 
                        
                        if plan_path(k, pick_anchor, pick_size)
                            AGVs(k).status = 'Moving_Pick';      
                        else
                            % 琚牭姝昏鍒掑け璐ワ紝閫€鍥為槻涓㈠け
                            AGVs(k).pick_queue = [];
                            AGVs(k).drop_queue = [];
                            AGVs(k).active_task_id = 0;
                        end
                        all_finished = false;
                        % ======================================================
                        
                    else   
                        charge_pos = props(AGVs(k).type).charge; 
                        home_pos = AGVs(k).home_pos;              
                        if AGVs(k).battery < 95                    
                            if check_in_area(AGVs(k).pos, charge_pos, agv_area_sz)      
                                AGVs(k).status = 'Charging';          
                                AGVs(k).wait_timer = 5;                
                            else
                                plan_to_charge(k);                     
                            end
                            all_finished = false;
                        elseif ~check_in_area(AGVs(k).pos, home_pos, agv_area_sz)        
                            if plan_path(k, home_pos, agv_area_sz)
                                AGVs(k).status = 'Go_Home';           
                            end
                            all_finished = false;
                        end
                    end
                    
                case {'Moving_Pick', 'Moving_Drop', 'Go_Home', 'Going_Charge'}  
                    all_finished = false;
                    % 銆愭柊澧炶蹇嗗姛鑳姐€戯細娌＄數鍘诲厖鐢垫椂锛岀簿鍑嗚浣忔鍦ㄤ簡鍝釜鐘舵€侊紒
                    if AGVs(k).battery < 20 && ~strcmp(AGVs(k).status, 'Going_Charge') && ~strcmp(AGVs(k).status, 'Charging')
                        disp(['AGV-', num2str(k), ' 鐢甸噺鑰楀敖锛屼繚鐣欓槦鍒楃幇鍦猴紝鍓嶅線鍏呯數锛?]);
                        AGVs(k).interrupted_status = AGVs(k).status; 
                        plan_to_charge(k);   
                        continue;              
                    end
                    
                    move_status = execute_move(k);  
                    if move_status == 1               
                        handle_arrival(k, task_list); 
                    elseif move_status < 0            
                        blocker_id = -move_status;     
                        resolve_conflict(k, blocker_id, task_list, t); 
                    end
                    
                case {'Loading', 'Unloading', 'Charging'}  
                    all_finished = false;
                    AGVs(k).wait_timer = AGVs(k).wait_timer - 1;  
                    
                    if strcmp(AGVs(k).status, 'Charging')        
                        AGVs(k).battery = min(100, AGVs(k).battery + 2.0); 
                        if AGVs(k).battery >= 100 && AGVs(k).wait_timer <= 0  
                            % 鍏呮弧鐢靛悗鐩存帴鎵撳洖 'Idle'锛屼笅涓懆鏈熶細璁╁畠鍒╃敤璁板繂鑷姩鎺ョ画浠诲姟锛?
                            AGVs(k).status = 'Idle'; 
                        end
                    end
                    
                    if AGVs(k).wait_timer <= 0 && ~strcmp(AGVs(k).status, 'Charging') && ~strcmp(AGVs(k).status, 'Go_Home')
                        finish_waiting(k, task_list);   
                    end
            end
        end
        if all_finished, break; end   
        
        % --- B. 鍔ㄧ敾鏄剧ず ---
        for f = 1:frames_per_step   
            curr_bat_list = zeros(1, num_agvs);  
            for k = 1:num_agvs
                target_r = AGVs(k).pos(1); target_c = AGVs(k).pos(2); 
                curr_r = AGVs(k).vis_pos(1); curr_c = AGVs(k).vis_pos(2); 
                
                AGVs(k).vis_pos(1) = curr_r + (target_r - curr_r) * 0.3;
                AGVs(k).vis_pos(2) = curr_c + (target_c - curr_c) * 0.3;
                
                update_agv_plot(AGVs(k));   
                curr_bat_list(k) = AGVs(k).battery;      
                
                if ~isempty(AGVs(k).path) && AGVs(k).path_idx <= size(AGVs(k).path, 1)
                    rem_path = AGVs(k).path(AGVs(k).path_idx:end, :); 
                    set(AGVs(k).path_line, 'XData', rem_path(:,2) - 0.5, 'YData', rem_path(:,1) - 0.5); 
                else
                    set(AGVs(k).path_line, 'XData', NaN, 'YData', NaN); 
                end
            end
            update_battery_monitor(f_batt, b_handle, t_handles, curr_bat_list); 
            drawnow limitrate;                           
            pause(0.01);                                  
        end
    end
    save_dir = fileparts(mfilename('fullpath'));
    try
        csv_file_path = fullfile(save_dir, 'task_metrics.csv'); % 鎷兼帴缁濆璺緞
        fid = fopen(csv_file_path, 'w', 'n', 'utf-8');
        fprintf(fid, 'task_id,agv_id,time_sec,distance\n');
        for i = 1:size(task_list, 1)
            tid = task_list(i, 1);
            if task_times(tid, 2) > 0
                t_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
                dist = task_dist_record(tid);
                agv_str = sprintf('AGV-%02d', task_executor(tid));
                fprintf(fid, '%d,%s,%.1f,%d\n', tid, agv_str, t_sec, dist);
            end
        end
        fclose(fid);
        try
            path_struct = struct();
            for i = 1:size(task_list, 1)
                tid = task_list(i, 1);
                % 鍙湁褰撲换鍔＄湡姝ｆ墽琛屽苟浜х敓杞ㄨ抗鏃舵墠璁板綍
                if ~isempty(task_trajectories{tid})
                    % 浠?task_ID 涓?Key 瀛樺偍鍧愭爣鐭╅樀
                    fname = sprintf('task_%d', tid);
                    path_struct.(fname) = task_trajectories{tid};
                end
            end
            
            % 杞崲涓?JSON 鏍煎紡瀛楃涓插苟鍐欏叆鏂囦欢
            json_str = jsonencode(path_struct);
            json_file_path = fullfile(save_dir, 'task_paths.json'); % 鎷兼帴缁濆璺緞
            fid_json = fopen(json_file_path, 'w');
            if fid_json ~= -1
                fprintf(fid_json, '%s', json_str);
                fclose(fid_json);
                disp('>> 宸茬敓鎴愯建杩硅缁嗘暟鎹細task_paths.json');
            else
                disp('>> 閿欒锛氭棤娉曞垱寤?task_paths.json 鏂囦欢锛?);
            end
        catch ME
            fprintf('>> 杞ㄨ抗瀵煎嚭寮傚父: %s\n', ME.message);
        end
        disp('>> 宸茬敓鎴愪换鍔℃寚鏍囨姤鍛婏細task_metrics.csv');
    catch
        disp('>> 璀﹀憡锛氱敓鎴?task_metrics.csv 澶辫触锛?);
    end
    try
        agv_file_path = fullfile(save_dir, 'agv_metrics.csv'); % 鎷兼帴缁濆璺緞
        fid_agv = fopen(agv_file_path, 'w', 'n', 'utf-8');
        fprintf(fid_agv, 'agv_id,agv_type,battery,total_distance,total_turns\n');
        for k = 1:num_agvs
            fprintf(fid_agv, '%d,%d,%.2f,%d,%d\n', ...
                k, AGVs(k).type, AGVs(k).battery, AGVs(k).total_dist, AGVs(k).total_turns);
        end
        fclose(fid_agv);
        disp('>> 宸茬敓鎴愯澶囩姸鎬佹姤鍛婏細agv_metrics.csv');
    catch
        disp('>> 璀﹀憡锛氱敓鎴?agv_metrics.csv 澶辫触锛?);
    end
    % ========================================================
    disp('>> 浠跨湡缁撴潫銆?);                              
    
    disp('========================================');
    disp('         AGV 杩愯鎬昏浆寮鏁扮粺璁?      ');
    disp('========================================');
    for k = 1:num_agvs
        agv_type_str = '鏈煡';
        if AGVs(k).type == 1, agv_type_str = '鎵樹妇寮?; end
        if AGVs(k).type == 2, agv_type_str = '鍙夎溅寮?; end
        fprintf('  AGV-%02d (%s)  |  鍏辫浆寮? %d 娆n', k, agv_type_str, AGVs(k).total_turns);
    end
    disp('========================================');
    
    
    % ==============================================================
    % ============== 宓屽杈呭姪鍑芥暟鍖哄煙 ===============================
    % ==============================================================
    function resolve_conflict(id_self, id_blocker, tasks_info, current_t)
        c_type = identify_conflict(id_self, id_blocker, AGVs); 
        conflict_name = '鏈煡鍐茬獊';
        if c_type == 1, conflict_name = '鐩稿悜鍐茬獊'; end
        if c_type == 2, conflict_name = '鑺傜偣鍐茬獊'; end
        if c_type == 3, conflict_name = '鍗犱綅鍐茬獊'; end
        if c_type == 4, conflict_name = '杩借刀鍐茬獊'; end
        
        P_self = calculate_ahp_priority(AGVs(id_self), tasks_info, current_t);
        P_blocker = calculate_ahp_priority(AGVs(id_blocker), tasks_info, current_t);
        
        disp(['[鎺у埗鍙癩 妫€娴嬪埌 ', conflict_name, ' (AGV-', num2str(id_self), ' 涓?AGV-', num2str(id_blocker), ')']);
        
        blocker_status = AGVs(id_blocker).status;
        is_blocker_stuck = strcmp(blocker_status, 'Idle') || strcmp(blocker_status, 'Loading') || ...
                           strcmp(blocker_status, 'Unloading') || strcmp(blocker_status, 'Charging');
        if P_self < P_blocker
            if ~isempty(AGVs(id_self).target_node) 
                success = plan_path(id_self, AGVs(id_self).target_node, [1, 1]); 
                if ~success, AGVs(id_self).move_timer = 5; end
            end
        elseif P_self > P_blocker
            if is_blocker_stuck
                disp(['[AHP璋冨害] 瀵规柟 AGV-', num2str(id_blocker), ' 鐗╃悊鍋滄粸(', blocker_status, ')銆侫GV-', num2str(id_self), ' 缁曡銆?]);
                if ~isempty(AGVs(id_self).target_node) 
                    success = plan_path(id_self, AGVs(id_self).target_node, [1, 1]); 
                    if ~success
                        disp(['[璀﹀憡] 缁曡姝昏儭鍚岋紒AGV-', num2str(id_self), ' 鍘熷湴浼戠湢...']);
                        AGVs(id_self).move_timer = 5; 
                    end
                end
            else
                disp(['[AHP璋冨害] AGV-', num2str(id_self), ' 楦ｇ瑳瑕佹眰瀵规柟璁╄矾...']);
            end
        else
            if id_self > id_blocker 
                if ~isempty(AGVs(id_self).target_node) 
                    success = plan_path(id_self, AGVs(id_self).target_node, [1, 1]); 
                    if ~success, AGVs(id_self).move_timer = 5; end
                end
            end
        end
    end

    function plan_to_charge(id)
        charge_pos = props(AGVs(id).type).charge; 
        if AGVs(id).type == 2, charge_area_sz = [3, 3]; 
        else 
            charge_area_sz = [2, 2]; 
        end
        if plan_path(id, charge_pos, charge_area_sz)       
            AGVs(id).status = 'Going_Charge';      
        end
    end

    function success = plan_path(id, target_anchor, area_size)
        if nargin < 3 || isempty(area_size), area_size = [2, 2]; end
        
        % ==========================================================
        % 銆愭牳蹇冧慨澶嶃€戯細鍔ㄦ€佹帹瀵艰櫄鎷?Target ID锛屾縺娲诲簳灞傚尯鍩熶簰閿佹満鍒讹紒
        virtual_target_id = 0;
        
        if strcmp(AGVs(id).status, 'Going_Charge') || strcmp(AGVs(id).status, 'Charging')
            % 鍘诲厖鐢垫椂锛屼紶鍏ヤ笓灞炲厖鐢?ID
            if AGVs(id).type == 1, virtual_target_id = 17; end % 鎵樹妇杞﹀厖鐢?
            if AGVs(id).type == 2, virtual_target_id = 18; end % 鍙夎溅鍏呯數
        else
            % 姝ｅ父鎵ц浠诲姟鎴栧洖杞﹀簱鏃讹紝鍊熺敤鍚岀被鐨?ID 鏉ヨЕ鍙戜簰閿侀€昏緫
            if AGVs(id).type == 1, virtual_target_id = 1; end  % 鎵樹妇杞﹀€熺敤 ID 1
            if AGVs(id).type == 2, virtual_target_id = 13; end % 鍙夎溅鍊熺敤 ID 13
        end
        
        % 銆愬叧閿姩浣溿€戯細搴熷純闈欐€佸叏灞€鍦板浘锛屾瘡娆″璺兘鐢熸垚甯︽湁閽堝鎬т簰閿佺殑鍔ㄦ€佸湴鍥撅紒
        tempMap = create_binary_grid_map(mapW, mapH, virtual_target_id);
        % ==========================================================
        
        area_h = area_size(1); area_w = area_size(2);
        
        % 1. 鍦ㄤ簰閿佸湴鍥句笂锛屽己琛屾妸鐩爣闈跺尯鈥滄寲绌衡€濓紝淇濊瘉 AGV 鑳藉紑杩涘幓
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr; c = target_anchor(2) + dc;
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    tempMap(r, c) = 0; 
                end
            end
        end
        
        valid_targets = [];
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr; c = target_anchor(2) + dc;
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    occupied = false;
                    for other = 1:num_agvs
                        if other ~= id && AGVs(other).pos(1) == r && AGVs(other).pos(2) == c
                            occupied = true; break; 
                        end
                    end
                    if ~occupied, valid_targets = [valid_targets; r, c]; %#ok<AGROW> 
                    end
                end
            end
        end
        if isempty(valid_targets), success = false; return; end
        
        curr_pos = AGVs(id).pos;
        distances = abs(valid_targets(:,1) - curr_pos(1)) + abs(valid_targets(:,2) - curr_pos(2));
        [~, best_idx] = min(distances);
        actual_target = valid_targets(best_idx, :); 
        
        tempMap(AGVs(id).pos(1), AGVs(id).pos(2)) = 0;
        for other = 1:num_agvs
            if other ~= id
                pos_r = AGVs(other).pos(1); pos_c = AGVs(other).pos(2);
                if ~(pos_r == actual_target(1) && pos_c == actual_target(2))
                    tempMap(pos_r, pos_c) = 1; 
                end
            end
        end
        
        current_weight = 0;
        if isfield(AGVs(id), 'payload_weight') && AGVs(id).load == 1
            current_weight = AGVs(id).payload_weight;
        end
        [path, ~, ~, ~, ~, ~] = astar_planner_turn3(tempMap, curr_pos, actual_target, current_weight);
        if ~isempty(path)
            AGVs(id).path = path;                
            AGVs(id).path_idx = 2;                
            AGVs(id).target_node = actual_target; 
            success = true;
        else
            success = false; 
        end
    end

    function status = execute_move(id)
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            status = 1; return; 
        end
        
        next_node = AGVs(id).path(AGVs(id).path_idx, :); 
        nr = next_node(1); nc = next_node(2);
        
        % 鍐茬獊妫€鏌ラ€昏緫涓嶅彉
        if OccupancyGrid(nr, nc) ~= 0 && OccupancyGrid(nr, nc) ~= id
            status = -OccupancyGrid(nr, nc); 
            return; 
        end
        
        % 杞集缁熻閫昏緫涓嶅彉
        curr_dir = [nr - AGVs(id).pos(1), nc - AGVs(id).pos(2)]; 
        if ~isequal(AGVs(id).last_dir, [0, 0]) && ~isequal(AGVs(id).last_dir, curr_dir)
            AGVs(id).total_turns = AGVs(id).total_turns + 1; 
        end
        AGVs(id).last_dir = curr_dir; 
        
        % --- 鍏抽敭淇敼浣嶇疆锛氭洿鏂板潗鏍囧苟璁板綍杞ㄨ抗 ---
        OccupancyGrid(AGVs(id).pos(1), AGVs(id).pos(2)) = 0; 
        AGVs(id).pos = next_node;                       % 鏇存柊浣嶇疆
        OccupancyGrid(nr, nc) = id; 
        
        tid = AGVs(id).active_task_id;
        if tid > 0
            task_trajectories{tid} = [task_trajectories{tid}; AGVs(id).pos];
        end
        % ---------------------------------------
        if ~isempty(AGVs(id).tasks)
            for i = 1:length(AGVs(id).tasks)
                q_tid = AGVs(id).tasks(i);
                % 婊¤冻鏉′欢锛氫笉鏄富鍔ㄤ换鍔★紝涓?task_times(q_tid, 1) > 0 (琛ㄧず宸插畬鎴?Loading)
                if q_tid ~= tid && task_times(q_tid, 1) > 0
                    task_trajectories{q_tid} = [task_trajectories{q_tid}; AGVs(id).pos];
                end
            end
        end
        AGVs(id).total_dist = AGVs(id).total_dist + 1;
        AGVs(id).path_idx = AGVs(id).path_idx + 1;      
        AGVs(id).move_timer = AGVs(id).step_dur;         
        % 鍔ㄦ€佽幏鍙栬杞﹀瀷鐨勬渶澶ц浇閲嶏紙涓?GA 淇濇寔缁濆涓€鑷达級
        if AGVs(id).type == 1
            cap = 80.0;  % 鎵樹妇杞︽渶澶ц浇閲?
        elseif AGVs(id).type == 2
            cap = 500.0; % 鍙夎溅鏈€澶ц浇閲?
        else
            cap = 100.0; % 鍏滃簳榛樿鍊?
        end
        
        cost = (e_b + e_l * (AGVs(id).payload_weight / cap)); 
        AGVs(id).battery = max(0, AGVs(id).battery - cost);
        
        AGVs(id).battery = max(0, AGVs(id).battery - cost);
        
        if AGVs(id).path_idx > size(AGVs(id).path, 1)
            AGVs(id).last_dir = [0, 0]; 
            status = 1; 
        else
            status = 0; 
        end
    end

    function handle_arrival(id, ~)
        st = AGVs(id).status;
        if strcmp(st, 'Moving_Pick')
            AGVs(id).status = 'Loading'; AGVs(id).wait_timer = 20; 
        elseif strcmp(st, 'Moving_Drop')
            AGVs(id).status = 'Unloading'; AGVs(id).wait_timer = 20; 
        elseif strcmp(st, 'Going_Charge')
            AGVs(id).status = 'Charging'; AGVs(id).wait_timer = 30; 
        elseif strcmp(st, 'Go_Home')
            AGVs(id).status = 'Idle'; 
        end
    end
    
    function finish_waiting(id, tasks_info)
        st = AGVs(id).status;
        
        if strcmp(st, 'Loading')
            tid = AGVs(id).active_task_id;                 
            row_idx = find(tasks_info(:,1) == tid);  
            task_weight = tasks_info(row_idx, 3);
            
            % 1. 銆愭牳蹇冿細浠呰褰曡捣鐐广€戣褰曞紑濮嬫椂闂村拰閲岀▼锛屼笉杩涜缁撶畻
            if task_times(tid, 1) == 0, task_times(tid, 1) = t; end
            task_start_dist(tid) = AGVs(id).total_dist;
            task_executor(tid) = id;
            
            % 2. 瑁呰浇璐х墿
            AGVs(id).payload_weight = AGVs(id).payload_weight + task_weight; 
            AGVs(id).load = 1;                     
            
            fprintf('馃摝 [AGV-%02d] 鎴愬姛瑁呰浇璁㈠崟 #%d | 閲嶉噺: %d | 杞︿笂鎬婚噸: %d\n', ...
                id, tid, task_weight, AGVs(id).payload_weight);
                
            % 3. 闃熷垪娴佽浆閫昏緫
            if ~isempty(AGVs(id).pick_queue)
                next_tid = AGVs(id).pick_queue(1);
                AGVs(id).pick_queue(1) = [];
                AGVs(id).active_task_id = next_tid;
                next_row = tasks_info(:,1) == next_tid;
                next_target_id = tasks_info(next_row, 2);
                [pick_anchor, ~, pick_size, ~] = get_task_coordinates(next_target_id); 
                if plan_path(id, pick_anchor, pick_size) 
                    AGVs(id).status = 'Moving_Pick';      
                else 
                    AGVs(id).wait_timer = 2;               
                    AGVs(id).pick_queue = [next_tid, AGVs(id).pick_queue]; 
                end
            else
                % 鍙栧畬璐т簡锛屽嚭鍙戝幓閫佽揣
                first_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = []; 
                AGVs(id).active_task_id = first_drop_tid;
                drop_row = tasks_info(:,1) == first_drop_tid;
                drop_target_id = tasks_info(drop_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(drop_target_id); 
                if plan_path(id, drop_anchor, drop_size) 
                    AGVs(id).status = 'Moving_Drop';      
                else 
                    AGVs(id).wait_timer = 2;               
                    AGVs(id).drop_queue = [first_drop_tid, AGVs(id).drop_queue]; 
                end
            end
            
        elseif strcmp(st, 'Unloading')
            tid = AGVs(id).active_task_id;                 
            row_idx = find(tasks_info(:,1) == tid);  
            task_weight = tasks_info(row_idx, 3);
            
            % 鈽呫€愭牳蹇冿細缁撶畻缁堢偣鎸囨爣銆戝彧鏈夊湪鍗歌揣瀹屾垚鏃舵墠璁板綍缁撴潫鏃堕棿鍜屾€昏矾绋?
            task_times(tid, 2) = t; 
            time_spent_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
            task_dist_record(tid) = AGVs(id).total_dist - task_start_dist(tid);
            
            fprintf('鉁?[AGV-%02d] 浠诲姟瀹屾垚锛佽鍗?#%d | 鑰楁椂: %.1f绉?| 杩愰€侀噷绋? %d鏍糪n', ...
                    id, tid, time_spent_sec, task_dist_record(tid));
            
            % 鎵ｉ櫎杞介噸骞朵粠璇ヨ溅浠诲姟閾句腑绉婚櫎
            AGVs(id).payload_weight = max(0, AGVs(id).payload_weight - task_weight); 
            AGVs(id).tasks(AGVs(id).tasks == tid) = [];                
                
            if ~isempty(AGVs(id).drop_queue)
                % 缁х画閫佷笅涓€浠?
                next_drop_tid = AGVs(id).drop_queue(1);
                AGVs(id).drop_queue(1) = []; 
                AGVs(id).active_task_id = next_drop_tid;
                next_row = tasks_info(:,1) == next_drop_tid;
                next_target_id = tasks_info(next_row, 2);
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(next_target_id); 
                if plan_path(id, drop_anchor, drop_size)
                    AGVs(id).status = 'Moving_Drop';      
                else 
                    AGVs(id).wait_timer = 2;               
                    AGVs(id).drop_queue = [next_drop_tid, AGVs(id).drop_queue]; 
                end
            else
                % 鍏ㄩ儴閫佸畬锛屽洖褰掔┖闂?
                fprintf('   -> 馃帀 AGV-%02d 鎵规閰嶉€佸叏閮ㄦ敹瀹樸€俓n', id);
                AGVs(id).status = 'Idle';                   
                AGVs(id).load = 0;                           
                AGVs(id).active_task_id = 0;
            end
        end
    end  
end
