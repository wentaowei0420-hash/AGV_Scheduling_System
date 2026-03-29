function run_visualization_loop_time(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    
    global mapW mapH; 
    
    % --- 1. 鍒濆鍖栧浘褰㈢晫闈?---
    generate_beautiful_factory_map();   
    % 銆愭柊澧炪€戯細澹版槑鍏ㄥ眬浠ｄ环鍦板浘骞舵墽琛屼竴娆￠璁＄畻
    global costmap_type1 costmap_type2;
    init_global_costmaps();
    f_map = gcf;                        
    ax = findobj(f_map, 'Type', 'Axes'); 
    hold(ax, 'on');                      
    set(f_map, 'Name', '瀹炴椂鍔ㄦ€佽皟搴︿豢鐪?, 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', 'Position', [50, 200, 1000, 700]);
    [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs);
    
    % --- 2. 鍒濆鍖?AGV 瀵硅薄 ---
    [AGVs, props, ~] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax);
    
    % --- 3. 瀹炴椂浠跨湡涓诲惊鐜?---
    disp('>> [绯荤粺] 瀹炴椂浠跨湡鍚姩...'); 

    for k = 1:num_agvs
        AGVs(k).total_turns = 0;           % 杩愯杞集鎬绘暟
        AGVs(k).last_dir = [0, 0];         % 涓婁竴姝ユ柟鍚戠煝閲?
        
        AGVs(k).pick_queue = [];           % 鍙栬揣浠诲姟闃熷垪
        AGVs(k).drop_queue = [];           % 鍗歌揣浠诲姟闃熷垪
        AGVs(k).active_task_id = 0;        % 褰撳墠姝ｅ湪瀵艰埅鐨勫叿浣撳瓙浠诲姟ID
        AGVs(k).interrupted_status = '';   % 璁板繂鍥犳病鐢靛幓鍏呯數鍓嶈涓柇鐨勭姸鎬?
    end 
    sim_running = true;      
    MAX_STEPS = 500000;      
    t = 0;                   
    frames_per_step = 2;
    max_task_id = max(task_list(:,1));
    task_row_map = zeros(max_task_id, 1);
    for row_idx = 1:size(task_list, 1)
        task_id = task_list(row_idx, 1);
        if task_id >= 1 && task_id <= max_task_id
            task_row_map(task_id) = row_idx;
        end
    end
    task_times = zeros(max_task_id, 2); 
    task_executor = zeros(max_task_id, 1);     
    task_start_dist = zeros(max_task_id, 1);   
    task_dist_record = zeros(max_task_id, 1);  
    for k = 1:num_agvs, AGVs(k).total_dist = 0; end
    task_trajectories = cell(max_task_id, 1);
    reported_conflict_keys = containers.Map('KeyType', 'char', 'ValueType', 'logical');
    % 涓讳豢鐪熷惊鐜細褰撲豢鐪熻繍琛屾爣蹇椾负鐪熶笖褰撳墠姝ユ暟鏈秴杩囨渶澶ф鏁版椂寰幆
    while sim_running && t < MAX_STEPS   
        t = t + 1;                       % 鏃堕棿姝ラ€掑锛堢鏁ｆ椂闂村崟浣嶏級
        all_finished = true;              % 鍋囪鎵€鏈堿GV閮藉凡瀹屾垚浠诲姟锛屽悗缁鏋滀换涓€AGV鏈畬鎴愬垯缃甪alse
    
        % --- A. 閫昏緫鏇存柊锛氶亶鍘嗘瘡涓狝GV锛屾牴鎹叾鐘舵€佹墽琛岀浉搴斿姩浣?---
        for k = 1:num_agvs   
            % 濡傛灉AGV姝ｅ湪绉诲姩涓紙move_timer > 0锛夛紝鍒欏噺灏戣鏃跺櫒锛岃烦杩囪AGV鐨勮缁嗛€昏緫
            if AGVs(k).move_timer > 0      
                AGVs(k).move_timer = AGVs(k).move_timer - 1; 
                all_finished = false;      % 浠嶆湁AGV鍦ㄧЩ鍔紝鏈叏閮ㄥ畬鎴?
                continue;                   % 璺宠繃璇GV鍚庣画澶勭悊锛岀洿鎺ュ鐞嗕笅涓€涓狝GV
            end
    
            % 鍔ㄦ€佽缃笓灞炶溅浣?鍏呯數妗╃殑灏哄锛岀敤浜庡尯鍩熸娴嬶紙濡傛槸鍚﹀仠鍦ㄥ厖鐢电珯鍐咃級
            if AGVs(k).type == 2
                agv_area_sz = [3, 3];      % 鍙夎溅锛堢被鍨?锛夊昂瀵歌緝澶?
            else
                agv_area_sz = [1, 1];      % 鎵樹妇寮忥紙绫诲瀷1锛夊昂瀵歌緝灏?
            end
    
            % 鏍规嵁AGV褰撳墠鐘舵€佽繘琛屽鍒嗘敮澶勭悊锛堢姸鎬佹満锛?
            switch AGVs(k).status
                case 'Idle'   % 绌洪棽鐘舵€?
                    % 鐢甸噺浣庝簬20%锛岄渶瑕佸厖鐢?
                    if AGVs(k).battery < 20   
                        plan_to_charge(k, t);     % 璋冪敤瑙勫垝鍏呯數鍑芥暟
                        all_finished = false;
                        
                    % 濡傛灉瀛樺湪鏈畬鎴愮殑娲昏穬浠诲姟锛堝彲鑳芥槸涔嬪墠涓柇鐨勶級锛屽垯灏濊瘯缁х画
                    elseif AGVs(k).active_task_id > 0
                        tid = AGVs(k).active_task_id;
                        row_idx = get_task_row(tid);   % 鑾峰彇浠诲姟鍦╰ask_list涓殑琛岀储寮?
                        if row_idx == 0                 % 浠诲姟涓嶅瓨鍦紙鍙兘宸茶绉婚櫎锛夛紝娓呯┖娲昏穬浠诲姟
                            AGVs(k).active_task_id = 0;
                            all_finished = false;
                            continue;
                        end
                        target_id = task_list(row_idx, 2);  % 鑾峰彇鐩爣绔欑偣ID
    
                        % 鏍规嵁涓柇鏃惰褰曠殑鐘舵€侊紝鎭㈠瀵瑰簲鐨勭Щ鍔ㄧ被鍨?
                        if strcmp(AGVs(k).interrupted_status, 'Moving_Drop')
                            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id); % 鑾峰彇閫佽揣鐐瑰尯鍩?
                            if plan_path(k, drop_anchor, drop_size, t)    % 瑙勫垝鍒伴€佽揣鐐圭殑璺緞
                                AGVs(k).status = 'Moving_Drop';           % 鍒囨崲鐘舵€佷负閫佽揣绉诲姩
                                AGVs(k).interrupted_status = '';          % 娓呴櫎涓柇璁板綍
                            end
                        elseif strcmp(AGVs(k).interrupted_status, 'Moving_Pick')
                            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); % 鑾峰彇鍙栬揣鐐瑰尯鍩?
                            if plan_path(k, pick_anchor, pick_size, t)
                                AGVs(k).status = 'Moving_Pick';
                                AGVs(k).interrupted_status = '';
                            end     
                        else
                            AGVs(k).active_task_id = 0;    % 鏃犳湁鏁堜腑鏂姸鎬侊紝娓呴櫎娲昏穬浠诲姟
                        end
                        all_finished = false;
                        
                    % 鏈夌┖闂蹭笖鏈夋湭寮€濮嬬殑浠诲姟锛屽噯澶囧彇璐э紙鍒嗘壒澶勭悊锛?
                    elseif ~isempty(AGVs(k).tasks)  
                        max_load_capacity = 80;            % 鏈€澶ц浇閲嶏紙纭紪鐮侊紝鍙粠鍙傛暟浼犲叆锛?
                        batch_tasks = [];                   % 褰撳墠鎵规鐨勫彇璐т换鍔D鍒楄〃
                        current_batch_weight = 0;            % 褰撳墠鎵规绱閲嶉噺
    
                        % 閬嶅巻璇GV鍓╀綑浠诲姟锛屾寜椤哄簭鏀惧叆鎵规锛岀洿鍒板閲忔弧鎴栫被鍨嬮檺鍒?
                        for i = 1:length(AGVs(k).tasks)
                            tid = AGVs(k).tasks(i);
                            row_idx = get_task_row(tid);
                            if row_idx == 0                  % 浠诲姟涓嶅瓨鍦紙鍙兘宸茶鍒犻櫎锛夛紝璺宠繃
                                continue;
                            end
                            w = task_list(row_idx, 3);       % 浠诲姟閲嶉噺
    
                            % 鍙夎溅锛坱ype 2锛夊彧鑳戒竴娆℃惡甯︿竴涓换鍔★紙鍙兘鐢变簬鐗╃悊闄愬埗锛?
                            if AGVs(k).type == 2 && i > 1
                                break; 
                            end
    
                            % 濡傛灉鏄涓€涓换鍔★紝鎴栬€呭綋鍓嶆壒娆￠噸閲忓姞涓婅浠诲姟涓嶈秴杩囧閲忥紝鍒欏姞鍏ユ壒娆?
                            if i == 1 || (current_batch_weight + w <= max_load_capacity)
                                batch_tasks = [batch_tasks, tid];
                                current_batch_weight = current_batch_weight + w;
                            else
                                break;   % 瓒呰繃瀹归噺锛屽仠姝㈢户缁坊鍔狅紙鍓╀綑浠诲姟鐣欏湪tasks涓笅娆″鐞嗭級
                            end
                        end
    
                        AGVs(k).pick_queue = batch_tasks;    % 璁剧疆鍙栬揣闃熷垪
                        AGVs(k).drop_queue = batch_tasks;    % 鍗歌揣闃熷垪锛堜笌鍙栬揣闃熷垪鐩稿悓锛?
    
                        % 寮€濮嬬涓€涓彇璐т换鍔?
                        first_tid = AGVs(k).pick_queue(1);
                        AGVs(k).pick_queue(1) = [];           % 浠庡彇璐ч槦鍒椾腑绉婚櫎绗竴涓?
                        AGVs(k).active_task_id = first_tid;   % 璁剧疆娲昏穬浠诲姟ID
    
                        row_idx = get_task_row(first_tid);
                        if row_idx == 0                        % 浠诲姟鏃犳晥锛屽洖閫€
                            AGVs(k).pick_queue = [];
                            AGVs(k).drop_queue = [];
                            AGVs(k).active_task_id = 0;
                            all_finished = false;
                            continue;
                        end
                        target_id = task_list(row_idx, 2);
                        [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); % 鑾峰彇鍙栬揣鐐瑰尯鍩?
    
                        if plan_path(k, pick_anchor, pick_size, t)   % 瑙勫垝鍒板彇璐х偣鐨勮矾寰?
                            AGVs(k).status = 'Moving_Pick';           % 鍒囨崲涓哄彇璐хЩ鍔ㄧ姸鎬?
                        else
                            % 璺緞瑙勫垝澶辫触锛屽洖閫€闃熷垪锛岀◢鍚庨噸璇曪紙鏈涓嶅仛澶勭悊锛屼笅娆″惊鐜彲鑳介噸鏂板皾璇曪級
                            AGVs(k).pick_queue = [];
                            AGVs(k).drop_queue = [];
                            AGVs(k).active_task_id = 0;
                        end
                        all_finished = false;
                        
                    else   % 娌℃湁浠诲姟涓旂┖闂诧紝鑰冭檻鍥炲鎴栧厖鐢?
                        home_pos = AGVs(k).home_pos;                   % 鑾峰彇AGV鐨勫浣嶇疆锛坉epot锛?
                        if AGVs(k).battery < 95                        % 鐢甸噺涓嶆弧95%锛岃€冭檻鍏呯數
                            % 鑾峰彇璇ョ被鍨婣GV鐨勫厖鐢电珯鍒楄〃
                            if isfield(props(AGVs(k).type), 'charge_stations') && ~isempty(props(AGVs(k).type).charge_stations)
                                candidate_stations = props(AGVs(k).type).charge_stations;
                            else
                                candidate_stations = props(AGVs(k).type).charge; % 鍏滃簳瀛楁
                            end
    
                            % 妫€鏌ュ綋鍓嶆槸鍚﹀凡缁忓湪鍏呯數绔欏尯鍩熷唴
                            is_at_charger = false;
                            for s = 1:size(candidate_stations, 1)
                                if check_in_area(AGVs(k).pos, candidate_stations(s, :), agv_area_sz)      
                                    is_at_charger = true;
                                    break; 
                                end
                            end
    
                            if is_at_charger      
                                AGVs(k).status = 'Charging';           % 宸插湪鍏呯數绔欙紝寮€濮嬪厖鐢?
                                AGVs(k).wait_timer = 5;                % 璁剧疆鍏呯數绛夊緟鏃堕棿锛堟鏁帮級
                            else
                                plan_to_charge(k, t);                  % 涓嶅湪鍏呯數绔欙紝瑙勫垝鍘诲厖鐢?
                            end
                            all_finished = false;
    
                        elseif ~check_in_area(AGVs(k).pos, home_pos, agv_area_sz)        
                            % 鐢甸噺鍏呰冻浣嗕笉鍦ㄥ锛岃鍒掑洖瀹?
                            if plan_path(k, home_pos, agv_area_sz, t)
                                AGVs(k).status = 'Go_Home';            % 杞负鍥炲鐘舵€?
                            end
                            all_finished = false;
                        end
                        % 濡傛灉鍦ㄥ涓旂數閲忓厖瓒筹紝鍒欎繚鎸佺┖闂诧紝涓嶅仛浠讳綍浜嬶紙all_finished宸蹭负true锛屼絾涓嬮潰浼氫繚鎸侊級
                    end
    
                % 绉诲姩鐩稿叧鐘舵€侊細鍙栬揣涓€侀€佽揣涓€佸洖瀹朵腑銆佸幓鍏呯數涓€佽琛屼腑
                case {'Moving_Pick', 'Moving_Drop', 'Go_Home', 'Going_Charge', 'Yielding'}  
                    all_finished = false;      % 鏈堿GV鍦ㄧЩ鍔紝鑲畾鏈畬鎴?
    
                    % 鐢甸噺妫€鏌ワ細濡傛灉鐢甸噺浣庝簬20%涓斿綋鍓嶇姸鎬佷笉鏄幓鍏呯數鎴栧厖鐢典腑锛屽垯涓柇褰撳墠浠诲姟鍘诲厖鐢?
                    if AGVs(k).battery < 20 && ~strcmp(AGVs(k).status, 'Going_Charge') && ~strcmp(AGVs(k).status, 'Charging')
                        disp(['AGV-', num2str(k), ' 鐢甸噺鑰楀敖锛屼繚鐣欓槦鍒楃幇鍦猴紝鍓嶅線鍏呯數锛?]);
                        AGVs(k).interrupted_status = AGVs(k).status;   % 璁板綍琚腑鏂殑鐘舵€?
                        plan_to_charge(k, t);                           % 瑙勫垝鍘诲厖鐢?
                        continue;                                       % 璺宠繃璇GV鏈鐨勭Щ鍔ㄦ墽琛?
                    end
    
                    move_status = execute_move(k);                      % 鎵ц绉诲姩涓€姝?
                    if move_status == 1                                  % 杩斿洖鍊?琛ㄧず鍒拌揪鐩爣鐐?
                        handle_arrival(k, task_list);                   % 澶勭悊鍒拌揪浜嬩欢锛堝瑁呰浇銆佸嵏璐х瓑锛?
                    elseif move_status < 0                               % 璐熸暟琛ㄧず绉诲姩琚樆濉烇紝杩斿洖闃诲鑰呯殑ID
                        blocker_id = -move_status;                      % 鑾峰彇闃诲AGV缂栧彿
                        resolve_conflict(k, blocker_id, task_list, t);  % 瑙ｅ喅鍐茬獊
                    end
    
                % 绛夊緟鐘舵€侊細瑁呰浇銆佸嵏璐с€佸厖鐢?
                case {'Loading', 'Unloading', 'Charging'}  
                    all_finished = false;
                    AGVs(k).wait_timer = AGVs(k).wait_timer - 1;        % 绛夊緟璁℃椂鍣ㄩ€掑噺
    
                    if strcmp(AGVs(k).status, 'Charging')               % 鍏呯數鐘舵€?
                        AGVs(k).battery = min(100, AGVs(k).battery + 2.0); % 姣忔澧炲姞鐢甸噺锛堜笂闄?00锛?
                        if AGVs(k).battery >= 100 && AGVs(k).wait_timer <= 0  % 鍏呮弧涓旂瓑寰呯粨鏉?
                            AGVs(k).status = 'Idle';                     % 杞负绌洪棽
                        end
                    end
    
                    % 闈炲厖鐢电姸鎬佷笖绛夊緟缁撴潫锛屼笖涓嶆槸鍥炲鐘舵€侊紝鍒欏畬鎴愮瓑寰呭苟鎵ц鍚庣画鍔ㄤ綔
                    if AGVs(k).wait_timer <= 0 && ~strcmp(AGVs(k).status, 'Charging') && ~strcmp(AGVs(k).status, 'Go_Home')
                        finish_waiting(k, task_list);                   % 瀹屾垚绛夊緟锛堝瑁呰浇鍚庡彇涓嬩竴涓揣鎴栧紑濮嬮€佽揣锛?
                    end
            end
        end

        % 濡傛灉鎵€鏈堿GV閮藉凡瀹屾垚浠诲姟锛坅ll_finished涓簍rue锛夛紝鍒欐彁鍓嶉€€鍑轰富寰幆
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
            pause(0.02);                                  
        end
    end
    export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories);
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
    
    function resolve_conflict(id_self, id_blocker, tasks_info, current_t)
        % 鍑芥暟鍔熻兘锛氳В鍐充袱涓狝GV涔嬮棿鐨勮矾寰勫啿绐?
        % 杈撳叆鍙傛暟锛?
        %   id_self     - 褰撳墠妫€娴嬪埌鍐茬獊鐨凙GV缂栧彿
        %   id_blocker  - 闃诲褰撳墠AGV鐨勫彟涓€涓狝GV缂栧彿
        %   tasks_info  - 浠诲姟鍒楄〃鐭╅樀锛岀敤浜庝紭鍏堢骇璁＄畻
        %   current_t   - 褰撳墠浠跨湡鏃堕棿姝?
    
        % 鑾峰彇褰撳墠AGV锛坕d_self锛夌殑褰撳墠浣嶇疆
        pos_self = AGVs(id_self).pos;
        % 鑾峰彇褰撳墠AGV璁″垝鐨勪笅涓€涓洰鏍囩偣锛堜粠璺緞涓彇鍑猴紝鍓嶄袱鍒楁槸鍧愭爣锛?
        target_self = AGVs(id_self).path(AGVs(id_self).path_idx, 1:2);
        % 璁＄畻褰撳墠AGV鐨勮繍鍔ㄦ柟鍚戠煝閲忥紙鐩爣鐐瑰噺褰撳墠浣嶇疆锛?
        dir_self = target_self - pos_self;
    
        % 鑾峰彇闃诲AGV锛坕d_blocker锛夌殑褰撳墠浣嶇疆
        pos_blocker = AGVs(id_blocker).pos;
    
        % 瀹氫箟鈥滄鍦ㄧЩ鍔ㄢ€濈殑鐘舵€佸垪琛紙杩欎簺鐘舵€佷笅鐨凙GV鏈夊姩鎬佽矾寰勶級
        moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home'};
        % 鍒ゆ柇闃诲AGV鏄惁澶勪簬绉诲姩鐘舵€佷箣涓€
        is_blocker_in_moving_state = ismember(AGVs(id_blocker).status, moving_states);
        % 鍒ゆ柇闃诲AGV鏄惁鏈夋湁鏁堣矾寰勪笖灏氭湭璧板畬
        has_path = ~isempty(AGVs(id_blocker).path) && AGVs(id_blocker).path_idx <= size(AGVs(id_blocker).path, 1);
    
        if is_blocker_in_moving_state && has_path
            % 濡傛灉闃诲AGV姝ｅ湪绉诲姩涓旀湁璺緞锛屽垯鑾峰彇瀹冪殑涓嬩竴涓洰鏍囩偣
            true_target_blocker = AGVs(id_blocker).path(AGVs(id_blocker).path_idx, 1:2);
            % 璁＄畻闃诲AGV鐨勮繍鍔ㄦ柟鍚?
            dir_blocker = true_target_blocker - pos_blocker;
    
            % 鏍规嵁闃诲AGV鐨勭Щ鍔ㄨ鏃跺櫒璁＄畻鍏垛€滈€熷害鈥濓紙姣忔绉诲姩鎵€闇€鏃堕棿鐨勫€掓暟锛?
            if AGVs(id_blocker).move_timer > 0
                v_blocker = 0.001;   % 濡傛灉杩樺湪绛夊緟涓紝瑙嗕负鏋佹參锛堝嚑涔庨潤姝級
            else
                v_blocker = 1.0 / AGVs(id_blocker).step_dur;   % 閫熷害 = 1鏍?/ step_dur 鏃堕棿姝?
            end
            target_blocker = true_target_blocker;   % 闃诲AGV鐨勭洰鏍囩偣
        else
            % 濡傛灉闃诲AGV涓嶅湪绉诲姩鐘舵€佹垨鏃犺矾寰勶紝鍒欏皢鍏跺綋鍓嶄綅缃涓虹洰鏍囩偣
            true_target_blocker = pos_blocker;
            target_blocker = pos_blocker;
            dir_blocker = [0, 0];   % 鏂瑰悜涓洪浂鐭㈤噺
            v_blocker = 0;           % 閫熷害涓洪浂
        end
    
        % 璁＄畻涓や釜AGV杩愬姩鏂瑰悜鐨勭偣绉紙鐢ㄤ簬鍒ゆ柇鏄浉鍚戙€佸悓鍚戣繕鏄瀭鐩达級
        dot_product = dir_self(1)*dir_blocker(1) + dir_self(2)*dir_blocker(2);
    
        % 璁＄畻褰撳墠AGV鐨勨€滈€熷害鈥?
        if AGVs(id_self).move_timer > 0
            v_self = 0.001;   % 绛夊緟涓涓烘參
        else
            v_self = 1.0 / AGVs(id_self).step_dur;
        end
    
        % 鍒濆鍖栧啿绐佺被鍨嬪拰鍚嶇О
        c_type = 0;
        conflict_name = '鏈煡鍐茬獊';
    
        % 瀹氫箟鐗规畩鐘舵€佹爣蹇?
        % 浜ゆ崲浣嶇疆锛氭垜鐨勭洰鏍囩偣鏄樆濉炶€呯殑褰撳墠浣嶇疆锛屼笖闃诲鑰呯殑鐩爣鐐规槸鎴戠殑褰撳墠浣嶇疆
        is_swapping = isequal(target_self, pos_blocker) && isequal(true_target_blocker, pos_self);
        % 鐩爣鐐圭浉鍚岋細鎴戠殑鐩爣鐐瑰拰闃诲鑰呯殑鐩爣鐐圭浉鍚?
        is_same_target = isequal(target_self, target_blocker);
    
        % 寮€濮嬪啿绐佺被鍨嬪垽鏂紙澶氭潯浠跺垎鏀級
        if is_swapping
            c_type = 1; conflict_name = '鐩稿悜鍐茬獊(浜ゆ崲)';
    
        elseif isequal(target_self, pos_blocker)
            % 鎴戠殑鐩爣鐐规槸闃诲鑰呯殑褰撳墠浣嶇疆
            if v_blocker == 0
                c_type = 3; conflict_name = '鍗犱綅鍐茬獊';   % 闃诲鑰呴潤姝笉鍔紝鍗犵潃鎴戣鍘荤殑浣嶇疆
            elseif dot_product > 0 && v_self > v_blocker
                c_type = 4; conflict_name = '杩借刀鍐茬獊';   % 鍚屽悜涓旀垜鏇村揩锛屽彲鑳借拷灏?
            else
                c_type = 1; conflict_name = '鐩稿悜鍐茬獊(浜ゆ崲)';   % 鍏朵粬鎯呭喌褰掍负鐩稿悜浜ゆ崲
            end
    
        elseif is_same_target
            % 鐩爣鐐圭浉鍚?
            if dot_product < 0
                c_type = 1; conflict_name = '鐩稿悜鍐茬獊(鐩搁亣)';   % 鐩稿悜鑰岃锛屼細鍦ㄧ洰鏍囩偣鐩搁亣
            else
                c_type = 2; conflict_name = '鑺傜偣鍐茬獊';         % 鍚屽悜鎴栧瀭鐩达紝鍚屾椂绔炰簤鍚屼竴涓妭鐐?
            end
        end
    
        % 杈撳嚭鍐茬獊鍙屾柟鐨勫綋鍓嶅潗鏍囧拰鐩爣鍧愭爣锛堢敤浜庤皟璇曪級
        fprintf('   [鍧愭爣] AGV-%d: 褰撳墠(%d,%d) 鐩爣(%d,%d) | AGV-%d: 褰撳墠(%d,%d) 鐩爣(%d,%d)\n', ...
            id_self, pos_self(1), pos_self(2), target_self(1), target_self(2), ...
            id_blocker, pos_blocker(1), pos_blocker(2), true_target_blocker(1), true_target_blocker(2));
    
        % 鐢熸垚鍐茬獊鐨勫敮涓€閿紝閬垮厤鍚屼竴鏃堕棿姝ラ噸澶嶅鐞嗙浉鍚屽啿绐佸
        conflict_pair = sort([id_self, id_blocker]);
        conflict_key = sprintf('%d_%d_%d', current_t, conflict_pair(1), conflict_pair(2));
        should_handle_conflict = ~isKey(reported_conflict_keys, conflict_key);
        if ~should_handle_conflict
            return;   % 濡傛灉宸插鐞嗚繃锛岀洿鎺ヨ繑鍥?
        end
        reported_conflict_keys(conflict_key) = true;   % 鏍囪宸插鐞?
    
        % 鍦ㄦ帶鍒跺彴鏄剧ず鍐茬獊淇℃伅
        disp(['[Conflict] T=', num2str(current_t), ' ', conflict_name, ' (AGV-', num2str(id_self), ' -> AGV-', num2str(id_blocker), ')']);
    
        % 灏濊瘯鍙戦€佸啿绐佷簨浠跺埌澶栭儴 webhook锛堢敤浜庣洃鎺ф垨璁板綍锛?
        if ~send_conflict_webhook(current_t, id_self, pos_self, id_blocker, pos_blocker, conflict_name)
            fprintf('[Webhook] Conflict event send failed and was written to local log: T=%d, AGV-%d vs AGV-%d\n', current_t, id_self, id_blocker);
        end
    
        % 璁＄畻涓や釜AGV鐨勪紭鍏堢骇锛堝熀浜嶢HP澶氬噯鍒欏喅绛栵級
        P_self = calculate_ahp_priority(AGVs(id_self), tasks_info, current_t);
        P_blocker = calculate_ahp_priority(AGVs(id_blocker), tasks_info, current_t);
    
        % 鍐冲畾鍝竴鏂瑰簲璇ヨ琛岋細浼樺厛绾т綆鐨勮琛岋紝濡傛灉鐩哥瓑鍒橧D澶х殑璁╄锛堥伩鍏嶆閿侊級
        should_self_yield = (P_self < P_blocker) || (P_self == P_blocker && id_self > id_blocker);
        if should_self_yield
            loser_id = id_self;      % 闇€瑕佽琛岀殑AGV
            winner_id = id_blocker;  % 鍙互浼樺厛閫氳鐨凙GV
        else
            loser_id = id_blocker;
            winner_id = id_self;
        end
    
        % 杈撳嚭浼樺厛绾ф瘮杈冪粨鏋滃拰璁╄鏂?
        fprintf('鍐茬獊娑堣В: AGV-%d 浼樺厛绾?= %.2f, AGV-%d 浼樺厛绾?= %.2f | loser = AGV-%d, winner = AGV-%d\n', ...
            id_self, P_self, id_blocker, P_blocker, loser_id, winner_id);
    
        % 鏍规嵁鍐茬獊绫诲瀷閲囧彇涓嶅悓鐨勮琛岀瓥鐣?
        if c_type == 1
            % 鐩稿悜鍐茬獊锛氳浣庝紭鍏堢骇鐨凙GV閫€璁╁埌涓存椂璁╄鐐?
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' retreats to a temporary yield node.']);
            success = plan_yield_path(loser_id, winner_id, current_t);   % 瑙勫垝璁╄璺緞
            if ~success && ~isempty(AGVs(loser_id).target_node)
                % 濡傛灉璁╄澶辫触锛屽皾璇曢噸鏂拌鍒掑埌鍘熺洰鏍囩偣锛堝彲鑳界粫璺級
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t);
            end
            if ~success
                % 濡傛灉浠嶇劧澶辫触锛屽垯璁╀綆浼樺厛绾GV绛夊緟涓€娈垫椂闂?
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
            end
    
        elseif c_type == 2
            % 鑺傜偣鍐茬獊锛氫綆浼樺厛绾GV鍘熷湴绛夊緟
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' waits before retrying.']);
            AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
    
        elseif c_type == 3
            % 鍗犱綅鍐茬獊锛氬皾璇曠粫琛?
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' attempts a detour around the occupied node.']);
            if ~isempty(AGVs(loser_id).target_node)
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t);
                if ~success
                    AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
                end
            else
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
            end
    
        elseif c_type == 4
            % 杩借刀鍐茬獊锛氶噸鏂拌鍒掓垨鍑忛€?
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' replans or slows down.']);
            if ~isempty(AGVs(loser_id).target_node)
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t);
                if ~success
                    AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
                end
            else
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
            end
        end
    end
    function plan_to_charge(id, current_t)
        % 鍑芥暟鍔熻兘锛氫负鎸囧畾鐨凙GV瑙勫垝鍓嶅線鍏呯數绔欑殑璺緞锛屽苟鍒囨崲鍒板厖鐢电姸鎬?
        % 杈撳叆鍙傛暟锛?
        %   id        - AGV鐨勭储寮曠紪鍙?
        %   current_t - 褰撳墠浠跨湡鏃堕棿姝ワ紙鐢ㄤ簬璺緞鏃堕棿鎴筹級
        
        % 鑾峰彇璇ョ被鍨婣GV鐨勫厖鐢电珯鍒楄〃
        % 棣栧厛灏濊瘯浠巔rops缁撴瀯浣撲腑璇诲彇 'charge_stations' 瀛楁锛堝彲鑳藉寘鍚涓厖鐢电珯锛?
        if isfield(props(AGVs(id).type), 'charge_stations') && ~isempty(props(AGVs(id).type).charge_stations)
            candidate_stations = props(AGVs(id).type).charge_stations;   % 浣跨敤涓撶敤鐨勫厖鐢电珯鍒楄〃
        else
            candidate_stations = props(AGVs(id).type).charge;            % 鍚﹀垯浣跨敤鍚庡瀛楁 'charge'
        end
    
        % 鏍规嵁AGV绫诲瀷纭畾鍏呯數鍖哄煙鐨勫昂瀵革紙鐢ㄤ簬璺緞瑙勫垝鐨勭洰鏍囧尯鍩燂級
        if AGVs(id).type == 2
            charge_area_sz = [3, 3];   % 鍙夎溅锛堢被鍨?锛変綋绉ぇ锛屽厖鐢靛尯鍩熶篃澶?
        else
            charge_area_sz = [1, 1];   % 鎵樹妇寮忥紙绫诲瀷1锛変綋绉皬锛屽厖鐢靛尯鍩熶负涓€涓綉鏍?
        end
    
        best_cost = inf;               % 鍒濆鍖栨渶浣宠矾寰勪唬浠蜂负鏃犵┓澶?
        best_station = [];             % 璁板綍鏈€浼樺厖鐢电珯鐨勯敋鐐逛綅缃?
        best_station_target = [];      % 璁板綍鏈€浼樺厖鐢电珯鍖哄煙鍐呭疄闄呯洰鏍囩偣锛堢綉鏍煎潗鏍囷級
        best_station_path = [];        % 璁板綍鏈€浼樿矾寰勭偣搴忓垪
    
        % 閬嶅巻鎵€鏈夊€欓€夊厖鐢电珯锛岄€夋嫨浠ｄ环鏈€灏忕殑鍙敤鍏呯數绔?
        for s = 1:size(candidate_stations, 1)
            station_pos = candidate_stations(s, :);   % 鍏呯數绔欑殑閿氱偣鍧愭爣锛堥€氬父鏄尯鍩熺殑宸︿笂瑙掞級
            
            % 妫€鏌ヨ鍏呯數绔欐槸鍚﹁鍏朵粬AGV鍗犵敤
            is_occupied = false;
            for other = 1:num_agvs
                if other == id, continue; end   % 璺宠繃鑷韩
                % 濡傛灉鍏朵粬AGV鐨勪綅缃垨鐩爣鑺傜偣姝ｅソ浣嶄簬璇ュ厖鐢电珯鐨勯敋鐐逛綅缃?
                if isequal(AGVs(other).pos, station_pos) || isequal(AGVs(other).target_node, station_pos)
                    % 骞朵笖璇GV澶勪簬鍏呯數涓垨姝ｅ湪鍘诲厖鐢电殑鐘舵€侊紝鎵嶈涓鸿鍗犵敤
                    if ismember(AGVs(other).status, {'Charging', 'Going_Charge'})
                        is_occupied = true;
                        break;
                    end
                end
            end
    
            if ~is_occupied
                % 濡傛灉鍏呯數绔欑┖闂诧紝鍒欒皟鐢ㄨ矾寰勮鍒掑嚱鏁板鎵句粠褰撳墠浣嶇疆鍒拌鍏呯數绔欏尯鍩熺殑鏈€浣宠矾寰?
                % 鍙傛暟璇存槑锛?
                %   id              - AGV缂栧彿
                %   station_pos     - 鍏呯數绔欓敋鐐?
                %   charge_area_sz  - 鍏呯數鍖哄煙灏哄
                %   'charge'        - 闄勫姞鏍囪瘑锛屽彲鑳界敤浜庢寚瀹氱洰鏍囩被鍨嬶紙濡傚厖鐢电珯锛夛紝褰卞搷浠ｄ环鍦板浘鎴栭殰纰嶅鐞?
                [candidate_path, candidate_target, candidate_cost] = find_best_target_path(id, station_pos, charge_area_sz, 'charge');
                
                % 濡傛灉鎵惧埌鍙璺緞涓斾唬浠峰皬浜庡綋鍓嶆渶浼橈紝鍒欐洿鏂版渶浼樿褰?
                if ~isempty(candidate_path) && candidate_cost < best_cost
                    best_cost = candidate_cost;
                    best_station = station_pos;
                    best_station_target = candidate_target;
                    best_station_path = candidate_path;
                end
            end
        end
    
        % 濡傛灉鎵惧埌浜嗗彲鐢ㄧ殑鍏呯數绔?
        if ~isempty(best_station)
            % 灏嗚鍒掑ソ鐨勮矾寰勫垎閰嶇粰璇GV锛堟坊鍔犳椂闂存埑锛?
            assign_planned_path(id, best_station_path, best_station_target, current_t);
            % 灏咥GV鐘舵€佽缃负鈥滃幓鍏呯數鈥?
            AGVs(id).status = 'Going_Charge';
            % 鎺у埗鍙拌緭鍑哄垎閰嶄俊鎭?
            disp(['[Charge Dispatch] AGV-', num2str(id), ' assigned to charger (', num2str(best_station(1)), ',', num2str(best_station(2)), ')']);
        else
            % 濡傛灉娌℃湁鎵惧埌浠讳綍鍙敤鍏呯數绔欙紙鍙兘鎵€鏈夊厖鐢电珯閮借鍗犵敤鎴栦笉鍙揪锛?
            disp(['[Charge Warning] AGV-', num2str(id), ' found no reachable idle charger and will wait.']);
            % 璁剧疆涓€涓Щ鍔ㄨ鏃跺櫒锛岃AGV绛夊緟涓€娈垫椂闂村悗鍐嶅皾璇?
            AGVs(id).move_timer = 5;
        end
    end
    
    function [best_path, best_target, best_cost] = find_best_target_path(id, target_anchor, area_size, planning_mode)
        % 鍑芥暟鍔熻兘锛氫负鎸囧畾鐨凙GV瀵绘壘浠庡綋鍓嶄綅缃埌鐩爣閿氱偣鍖哄煙鍐呮渶浣崇洰鏍囩偣鐨勮矾寰?
        % 杈撳叆鍙傛暟锛?
        %   id            - AGV鐨勭储寮曠紪鍙?
        %   target_anchor - 鐩爣鍖哄煙鐨勯敋鐐瑰潗鏍囷紙閫氬父鏄乏涓婅缃戞牸鍧愭爣锛夛紝[琛? 鍒梋
        %   area_size     - 鐩爣鍖哄煙鐨勫昂瀵?[楂樺害, 瀹藉害]锛堜互缃戞牸涓哄崟浣嶏級
        %   planning_mode - 瑙勫垝妯″紡锛?task' 鎴?'charge'锛屽奖鍝嶈櫄鎷熺洰鏍嘔D鐨勯€夋嫨锛堢敤浜庢瀯寤轰复鏃堕殰纰嶅湴鍥撅級
        % 杈撳嚭鍙傛暟锛?
        %   best_path   - 鏈€浼樿矾寰勭偣搴忓垪锛屾瘡涓€琛?[琛? 鍒梋
        %   best_target - 鏈€浼樼洰鏍囩偣锛堝尯鍩熷唴鐨勫叿浣撶綉鏍煎潗鏍囷級
        %   best_cost   - 鏈€浼樿矾寰勭殑浠ｄ环鍊硷紙瓒婂皬瓒婂ソ锛?
    
        % 璁剧疆榛樿鍙傛暟锛氬鏋?area_size 鏈彁渚涙垨涓虹┖锛屽垯榛樿涓?[2,2]
        if nargin < 3 || isempty(area_size), area_size = [2, 2]; end
        % 璁剧疆榛樿鍙傛暟锛氬鏋?planning_mode 鏈彁渚涙垨涓虹┖锛屽垯榛樿涓?'task'
        if nargin < 4 || isempty(planning_mode), planning_mode = 'task'; end
    
        % 鏍规嵁瑙勫垝妯″紡纭畾铏氭嫙鐩爣ID锛堢敤浜庢瀯寤轰簩鍊肩綉鏍煎湴鍥炬椂鎺掗櫎鏌愪簺鍖哄煙锛?
        virtual_target_id = 0;
        if strcmp(planning_mode, 'charge')
            % 鍏呯數妯″紡锛氭墭涓捐溅浣跨敤ID 17锛屽弶杞︿娇鐢↖D 18
            if AGVs(id).type == 1, virtual_target_id = 17; end
            if AGVs(id).type == 2, virtual_target_id = 18; end
        else
            % 浠诲姟妯″紡锛氭墭涓捐溅浣跨敤ID 1锛屽弶杞︿娇鐢↖D 13
            if AGVs(id).type == 1, virtual_target_id = 1; end
            if AGVs(id).type == 2, virtual_target_id = 13; end
        end
    
        % 鍒涘缓浜屽€肩綉鏍煎湴鍥撅紙1涓洪殰纰嶏紝0涓哄彲琛岋級锛屽苟浼犲叆铏氭嫙鐩爣ID浠ユ帓闄ょ壒瀹氬尯鍩?
        tempMap = create_binary_grid_map(mapW, mapH, virtual_target_id);
        area_h = area_size(1);   % 鍖哄煙楂樺害
        area_w = area_size(2);   % 鍖哄煙瀹藉害
    
        % 灏嗙洰鏍囬敋鐐瑰懆鍥寸殑鍖哄煙鍦ㄤ复鏃跺湴鍥句腑璁句负鍙锛堟竻闄ら殰纰嶏級
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr;  % 褰撳墠缃戞牸琛屽潗鏍?
                c = target_anchor(2) + dc;  % 褰撳墠缃戞牸鍒楀潗鏍?
                % 纭繚鍧愭爣鍦ㄥ湴鍥捐寖鍥村唴
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    tempMap(r, c) = 0;       % 璁句负鍙
                end
            end
        end
    
        % 鏀堕泦鍖哄煙鍐呮墍鏈夋湭琚叾浠朅GV鍗犳嵁鎴栦綔涓虹洰鏍囩偣鐨勭綉鏍间綔涓哄€欓€夌洰鏍囩偣
        valid_targets = [];
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr;
                c = target_anchor(2) + dc;
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    occupied = false;   % 鍒濆鍖栧崰鐢ㄦ爣蹇?
                    % 閬嶅巻鎵€鏈夊叾浠朅GV锛屾鏌ヨ缃戞牸鏄惁琚崰鐢?
                    for other = 1:num_agvs
                        if other == id, continue; end   % 璺宠繃鑷韩
                        % 妫€鏌ュ叾浠朅GV鐨勫綋鍓嶄綅缃槸鍚︾瓑浜庤缃戞牸
                        is_pos_occupied = (AGVs(other).pos(1) == r && AGVs(other).pos(2) == c);
                        % 妫€鏌ュ叾浠朅GV鐨勭洰鏍囪妭鐐规槸鍚︾瓑浜庤缃戞牸
                        is_target_occupied = ~isempty(AGVs(other).target_node) && ...
                                             (AGVs(other).target_node(1) == r && AGVs(other).target_node(2) == c);
                        if is_pos_occupied || is_target_occupied
                            occupied = true;
                            break;   % 涓€鏃﹀彂鐜板崰鐢紝鎻愬墠閫€鍑哄唴灞傚惊鐜?
                        end
                    end
                    if ~occupied
                        % 濡傛灉鏈鍗犵敤锛屽垯灏嗚缃戞牸鍔犲叆鍊欓€夊垪琛?
                        valid_targets = [valid_targets; r, c]; %#ok<AGROW>
                    end
                end
            end
        end
    
        % 鍒濆鍖栨渶浼樼粨鏋?
        best_path = [];
        best_target = [];
        best_cost = inf;   % 鍒濆浠ｄ环璁句负鏃犵┓澶?
    
        % 濡傛灉娌℃湁鍊欓€夌洰鏍囩偣锛岀洿鎺ヨ繑鍥炵┖缁撴灉
        if isempty(valid_targets)
            return;
        end
    
        % 鑾峰彇AGV褰撳墠杞介噸锛堢敤浜庝唬浠峰湴鍥句腑鐨勮礋杞戒唬浠疯绠楋級
        current_weight = 0;
        if isfield(AGVs(id), 'payload_weight') && AGVs(id).load == 1
            current_weight = AGVs(id).payload_weight;
        end
    
        % 鏍规嵁AGV绫诲瀷閫夋嫨瀵瑰簲鐨勪唬浠峰湴鍥撅紙涓嶅悓绫诲瀷瀵逛笉鍚屽尯鍩熺殑閫氳浠ｄ环涓嶅悓锛?
        if AGVs(id).type == 2
            current_costmap = costmap_type2;
        else
            current_costmap = costmap_type1;
        end
    
        curr_pos = AGVs(id).pos;   % AGV褰撳墠浣嶇疆
    
        % 閬嶅巻鎵€鏈夊€欓€夌洰鏍囩偣锛屼娇鐢ˋ*绠楁硶瑙勫垝璺緞锛岄€夋嫨浠ｄ环鏈€灏忕殑
        for idx = 1:size(valid_targets, 1)
            candidate_target = valid_targets(idx, :);   % 褰撳墠鍊欓€夌洰鏍囩偣
            evalMap = tempMap;                           % 澶嶅埗涓存椂鍦板浘鐢ㄤ簬璇勪及
            evalMap(curr_pos(1), curr_pos(2)) = 0;       % 纭繚璧风偣鍙锛堝彲鑳戒箣鍓嶈鏍囪涓洪殰纰嶏紵浣嗕竴鑸捣鐐规槸鍙锛?
    
            % 灏嗗叾浠朅GV鐨勫綋鍓嶄綅缃涓洪殰纰嶏紙闄ら潪璇ヤ綅缃伆濂芥槸褰撳墠鍊欓€夌洰鏍囩偣锛岃繖鏍风洰鏍囩偣鏈韩浠嶇劧鍙锛?
            for other = 1:num_agvs
                if other ~= id
                    pos_r = AGVs(other).pos(1);
                    pos_c = AGVs(other).pos(2);
                    % 鍙湁褰撳叾浠朅GV鐨勪綅缃笉绛変簬鍊欓€夌洰鏍囩偣鏃讹紝鎵嶅皢鍏惰涓洪殰纰?
                    if ~(pos_r == candidate_target(1) && pos_c == candidate_target(2))
                        evalMap(pos_r, pos_c) = 1;   % 璁句负闅滅
                    end
                end
            end
    
            % 璋冪敤A*璺緞瑙勫垝鍣紙鑰冭檻杞集浠ｄ环鍜岃礋杞戒唬浠凤級
            [candidate_path, candidate_cost, ~, ~, ~, ~] = astar_planner_turn3(evalMap, curr_pos, candidate_target, current_weight, current_costmap);
            % 濡傛灉鎵惧埌鍙璺緞涓斾唬浠峰皬浜庡綋鍓嶆渶浼橈紝鍒欐洿鏂版渶浼樿褰?
            if ~isempty(candidate_path) && candidate_cost < best_cost
                best_cost = candidate_cost;
                best_target = candidate_target;
                best_path = candidate_path;
            end
        end
    end
    
    function assign_planned_path(id, path, actual_target, current_t)
        % 鍑芥暟鍔熻兘锛氬皢瑙勫垝濂界殑璺緞鍒嗛厤缁欐寚瀹氱殑AGV锛屽苟娣诲姞鏃堕棿鎴?
        % 杈撳叆鍙傛暟锛?
        %   id            - AGV鐨勭储寮曠紪鍙?
        %   path          - 璺緞鐐圭煩闃碉紝姣忎竴琛屾槸涓€涓綉鏍煎潗鏍?[琛? 鍒梋锛屾寜浠庤捣鐐瑰埌缁堢偣鐨勯『搴忔帓鍒?
        %   actual_target - 瀹為檯鐨勭洰鏍囩偣锛堝尯鍩熷唴鐨勫叿浣撶綉鏍煎潗鏍囷級锛岀敤浜庤褰旳GV褰撳墠鍓嶅線鐨勭洰鏍囪妭鐐?
        %   current_t     - 褰撳墠浠跨湡鏃堕棿姝ワ紝鐢ㄤ簬璁＄畻姣忎釜璺緞鐐圭殑鏃堕棿鎴?
    
        path_length = size(path, 1);          % 鑾峰彇璺緞鐐圭殑鎬绘暟锛堣矾寰勯暱搴︼級
        time_stamps = zeros(path_length, 1);  % 鍒濆鍖栨椂闂存埑鏁扮粍锛屼笌璺緞鐐逛竴涓€瀵瑰簲
        step_time = AGVs(id).step_dur;        % 鑾峰彇璇GV绉诲姩涓€鏍兼墍闇€鐨勪豢鐪熸椂闂存鏁帮紙閫熷害鍙傛暟锛?
    
        % 涓烘瘡涓矾寰勭偣璁＄畻棰勮鍒拌揪鐨勬椂闂存
        for p_idx = 1:path_length
            % 褰撳墠璺緞鐐圭殑棰勮鍒拌揪鏃堕棿 = 褰撳墠鏃堕棿 + (绱㈠紩-1) * step_time
            % 璧风偣锛堢储寮?锛夌殑鏃堕棿鎴充负 current_t锛屾剰鍛崇潃AGV灏嗗湪褰撳墠鏃堕棿姝ュ紑濮嬬Щ鍔紵
            % 娉ㄦ剰锛氳捣鐐归€氬父鏄疉GV褰撳墠浣嶇疆锛屾墍浠ュ埌杈捐捣鐐圭殑鏃堕棿涓?current_t锛堝凡缁忓湪璇ョ偣锛?
            time_stamps(p_idx) = current_t + (p_idx - 1) * step_time;
        end
    
        % 灏嗚矾寰勭偣涓庢椂闂存埑鍚堝苟锛屽瓨鍌ㄥ埌AGV鐨刾ath瀛楁
        % 鏂扮煩闃垫瘡涓€琛屼负 [琛? 鍒? 鏃堕棿鎴砞
        AGVs(id).path = [path, time_stamps];
    
        % 璁剧疆璺緞绱㈠紩涓?锛岃〃绀轰笅涓€涓绉诲姩鍒扮殑鐐规槸璺緞涓殑绗簩涓偣
        % 鍥犱负绗竴涓偣鏄綋鍓嶆墍鍦ㄤ綅缃紝涓嶉渶瑕佺Щ鍔?
        AGVs(id).path_idx = 2;
    
        % 璁板綍AGV褰撳墠鐨勭洰鏍囪妭鐐癸紙鍖哄煙鍐呯殑鍏蜂綋缃戞牸鍧愭爣锛?
        % 杩欎釜鐩爣鑺傜偣鐢ㄤ簬鍐茬獊妫€娴嬪拰瀵艰埅
        AGVs(id).target_node = actual_target;
    end
    
    function row_idx = get_task_row(task_id)
        row_idx = 0;
        if isempty(task_id) || task_id < 1 || task_id > numel(task_row_map)
            return;
        end
        row_idx = task_row_map(task_id);
    end

    function success = plan_path(id, target_anchor, area_size, current_t, planning_mode)
        % 鍑芥暟鍔熻兘锛氫负鎸囧畾AGV瑙勫垝涓€鏉″埌鐩爣閿氱偣鍖哄煙鍐呮煇鍙揪鐐圭殑璺緞锛屽苟鍒嗛厤璺緞
        % 杈撳叆鍙傛暟锛?
        %   id            - AGV鐨勭储寮曠紪鍙?
        %   target_anchor - 鐩爣鍖哄煙鐨勯敋鐐瑰潗鏍囷紙閫氬父鏄乏涓婅缃戞牸鍧愭爣锛夛紝[琛? 鍒梋
        %   area_size     - 鐩爣鍖哄煙鐨勫昂瀵?[楂樺害, 瀹藉害]锛堜互缃戞牸涓哄崟浣嶏級
        %   current_t     - 褰撳墠浠跨湡鏃堕棿姝?
        %   planning_mode - 瑙勫垝妯″紡锛?task' 鎴?'charge'锛屽奖鍝嶈矾寰勮鍒掍腑鐨勪唬浠峰湴鍥惧拰铏氭嫙鐩爣ID
        % 杈撳嚭鍙傛暟锛?
        %   success       - 甯冨皵鍊硷紝true 琛ㄧず鎴愬姛鎵惧埌璺緞骞跺垎閰嶏紝false 琛ㄧず瑙勫垝澶辫触
    
        % 濡傛灉 area_size 鏈彁渚涙垨涓虹┖锛屽垯浣跨敤榛樿鍊?[2, 2]
        if nargin < 3 || isempty(area_size), area_size = [2, 2]; end
    
        % 濡傛灉 planning_mode 鏈彁渚涙垨涓虹┖锛屽垯浣跨敤榛樿鍊?'task'
        if nargin < 5 || isempty(planning_mode), planning_mode = 'task'; end
    
        % 璋冪敤 find_best_target_path 鍑芥暟锛屽鎵句粠AGV褰撳墠浣嶇疆鍒扮洰鏍囬敋鐐瑰尯鍩熷唴鏈€浣崇洰鏍囩偣鐨勮矾寰?
        % 璇ュ嚱鏁拌繑鍥烇細
        %   path          - 鏈€浼樿矾寰勭偣搴忓垪锛堟瘡涓€琛?[琛? 鍒梋锛?
        %   actual_target - 鍖哄煙鍐呭疄闄呴€変腑鐨勫叿浣撶洰鏍囩偣锛堢綉鏍煎潗鏍囷級
        %   ~             - 绗笁涓繑鍥炲€硷紙浠ｄ环锛夎蹇界暐锛屽洜涓烘澶勫彧鍏冲績璺緞鏄惁瀛樺湪
        [path, actual_target, ~] = find_best_target_path(id, target_anchor, area_size, planning_mode);
    
        % 鍒ゆ柇鏄惁鎵惧埌鍙璺緞
        if ~isempty(path)
            % 濡傛灉璺緞闈炵┖锛岃皟鐢?assign_planned_path 鍑芥暟灏嗚矾寰勫垎閰嶇粰AGV
            % 璇ュ嚱鏁颁細涓鸿矾寰勬坊鍔犳椂闂存埑锛屽苟璁剧疆 AGV 鐨?path銆乸ath_idx銆乼arget_node 绛夊瓧娈?
            assign_planned_path(id, path, actual_target, current_t);
            success = true;   % 璁剧疆鎴愬姛鏍囧織
        else
            success = false;  % 鏈壘鍒拌矾寰勶紝璁剧疆澶辫触鏍囧織
        end
    end

    function success = plan_yield_path(id, blocker_id, current_t)
        % 鍑芥暟鍔熻兘锛氫负闇€瑕佽琛岀殑AGV瑙勫垝涓€鏉￠€€璁╄矾寰勶紝浣垮叾鏆傛椂绂诲紑鍐茬獊鍖哄煙
        % 杈撳叆鍙傛暟锛?
        %   id         - 闇€瑕佽琛岀殑AGV缂栧彿
        %   blocker_id - 闃诲褰撳墠AGV鐨勫彟涓€涓狝GV缂栧彿锛堢敤浜庣‘瀹氶€€璁╂柟鍚戯級
        %   current_t  - 褰撳墠浠跨湡鏃堕棿姝?
        % 杈撳嚭鍙傛暟锛?
        %   success    - 甯冨皵鍊硷紝true琛ㄧず鎴愬姛瑙勫垝璁╄璺緞锛宖alse琛ㄧず澶辫触
    
        success = false;                              % 鍒濆鍖栦负澶辫触
        curr_pos = AGVs(id).pos;                      % 鑾峰彇褰撳墠AGV鐨勪綅缃?
        blocker_pos = AGVs(blocker_id).pos;           % 鑾峰彇闃诲AGV鐨勪綅缃?
        % 璁＄畻褰撳墠AGV涓庨樆濉濧GV涔嬮棿鐨勬浖鍝堥】璺濈锛堢綉鏍艰窛绂伙級
        current_gap = abs(curr_pos(1) - blocker_pos(1)) + abs(curr_pos(2) - blocker_pos(2));
        candidate_nodes = [];                          % 鍒濆鍖栧€欓€夎琛岀偣鍒楄〃锛堟瘡涓偣涓?[琛? 鍒梋锛?
    
        % --- 浠庡師璺緞涓洖婧袱涓偣浣滀负鍊欓€夎琛岀偣 ---
        if ~isempty(AGVs(id).path)
            % 鍥炴函鐨勭储寮曪細褰撳墠璺緞绱㈠紩鐨勫墠涓や釜鍜屽墠涓変釜浣嶇疆
            backtrack_indices = [AGVs(id).path_idx - 2, AGVs(id).path_idx - 3];
            for idx = backtrack_indices
                % 纭繚绱㈠紩鍦ㄦ湁鏁堣寖鍥村唴锛?=1 涓?<=璺緞鎬荤偣鏁帮級
                if idx >= 1 && idx <= size(AGVs(id).path, 1)
                    % 灏嗚矾寰勭偣鍧愭爣锛堝墠涓ゅ垪锛夊姞鍏ュ€欓€夊垪琛?
                    candidate_nodes = [candidate_nodes; AGVs(id).path(idx, 1:2)]; %#ok<AGROW>
                end
            end
        end
    
        % --- 娣诲姞褰撳墠鐐圭殑鍥涗釜閭诲眳缃戞牸浣滀负鍊欓€夎琛岀偣 ---
        directions = [-1, 0; 1, 0; 0, -1; 0, 1];   % 涓娿€佷笅銆佸乏銆佸彸鍥涗釜鏂瑰悜
        for d = 1:size(directions, 1)
            candidate = curr_pos + directions(d, :);   % 璁＄畻閭诲眳缃戞牸鍧愭爣
            % 妫€鏌ユ槸鍚﹀湪鍦板浘鑼冨洿鍐?
            if candidate(1) < 1 || candidate(1) > mapH || candidate(2) < 1 || candidate(2) > mapW
                continue;                               % 瓒呭嚭鍦板浘鍒欒烦杩?
            end
            candidate_nodes = [candidate_nodes; candidate]; %#ok<AGROW> 鍔犲叆鍊欓€夊垪琛?
        end
    
        % 濡傛灉娌℃湁鏀堕泦鍒颁换浣曞€欓€夌偣锛岀洿鎺ヨ繑鍥炲け璐?
        if isempty(candidate_nodes)
            return;
        end
    
        % 鍘婚櫎鍊欓€夌偣涓殑閲嶅鍧愭爣锛堜繚鐣欑涓€娆″嚭鐜扮殑椤哄簭锛?
        [~, unique_idx] = unique(candidate_nodes, 'rows', 'stable');
        candidate_nodes = candidate_nodes(unique_idx, :);
    
        % 璁＄畻姣忎釜鍊欓€夌偣涓庨樆濉濧GV鐨勬浖鍝堥】璺濈
        candidate_gaps = abs(candidate_nodes(:, 1) - blocker_pos(1)) + abs(candidate_nodes(:, 2) - blocker_pos(2));
        % 灏嗚窛绂讳綔涓虹鍥涘垪闄勫姞鍒板€欓€夌偣鐭╅樀涓?
        candidate_nodes = [candidate_nodes, candidate_gaps];
        % 鎸夎窛绂婚檷搴忔帓搴忥紙璺濈闃诲AGV瓒婅繙鐨勭偣瓒婁紭鍏堬級
        candidate_nodes = sortrows(candidate_nodes, -3);   % -3 琛ㄧず鎸夌涓夊垪锛堣窛绂伙級闄嶅簭
    
        % 璁板綍褰撳墠AGV鐨勭姸鎬侊紝浠ヤ究璁╄缁撴潫鍚庢仮澶?
        original_status = AGVs(id).status;
    
        % 閬嶅巻鎺掑簭鍚庣殑鍊欓€夌偣锛屽皾璇曡鍒掕矾寰?
        for c_idx = 1:size(candidate_nodes, 1)
            candidate = candidate_nodes(c_idx, 1:2);      % 褰撳墠鍊欓€夌偣鍧愭爣
            % 璺宠繃褰撳墠鐐硅嚜韬拰闃诲AGV鐨勪綅缃紙鏃犳剰涔夛級
            if isequal(candidate, curr_pos) || isequal(candidate, blocker_pos)
                continue;
            end
            % 濡傛灉鍊欓€夌偣涓庨樆濉濧GV鐨勮窛绂诲皬浜庡綋鍓嶈窛绂伙紝鍒欒烦杩囷紙甯屾湜閫€璁╁緱鏇磋繙锛岃€屼笉鏄洿杩戯級
            if candidate_nodes(c_idx, 3) < current_gap
                continue;
            end
            % 灏濊瘯瑙勫垝浠庡綋鍓嶄綅缃埌鍊欓€夌偣鐨勮矾寰勶紙鐩爣鍖哄煙澶у皬涓?x1锛屽嵆绮剧‘鍒拌揪璇ョ偣锛?
            if plan_path(id, candidate, [1, 1], current_t)
                % 瑙勫垝鎴愬姛锛氳褰曡琛屽墠鐘舵€侊紝灏咥GV鐘舵€佽涓?Yielding'锛屽苟杩斿洖鎴愬姛
                AGVs(id).yield_resume_status = original_status;
                AGVs(id).status = 'Yielding';
                success = true;
                return;
            end
        end
        % 濡傛灉鎵€鏈夊€欓€夌偣閮芥棤娉曡鍒掕矾寰勶紝鍒欒繑鍥炲け璐?
    end

    function status = execute_move(id)
        % 鍑芥暟鍔熻兘锛氭墽琛孉GV鐨勪竴姝ョЩ鍔紝鍖呮嫭鍐茬獊妫€娴嬨€佷綅缃洿鏂般€佺姸鎬佽褰曠瓑
        % 杈撳叆鍙傛暟锛?
        %   id - AGV鐨勭储寮曠紪鍙?
        % 杈撳嚭鍙傛暟锛?
        %   status - 绉诲姩缁撴灉鐘舵€侊細
        %       1  = 鍒拌揪褰撳墠璺緞鐨勭粓鐐癸紙闇€瑕佸鐞嗗埌杈句簨浠讹級
        %       0  = 姝ｅ父绉诲姩涓€姝ワ紝灏氭湭鍒拌揪缁堢偣
        %       -n = 绉诲姩琚紪鍙蜂负 n 鐨凙GV闃诲锛岄渶瑕佸鐞嗗啿绐侊紙n涓烘鏁存暟锛?
    
        % 妫€鏌GV鏄惁鏈夋湁鏁堣矾寰勶紝鎴栬€呰矾寰勭储寮曟槸鍚﹀凡瓒呭嚭鑼冨洿
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            status = 1;      % 鏃犺矾寰勬垨宸插埌缁堢偣锛岃繑鍥炲埌杈剧姸鎬?
            return;          % 鎻愬墠閫€鍑哄嚱鏁?
        end
    
        curr_pos = AGVs(id).pos;                           % 褰撳墠AGV鐨勪綅缃紙缃戞牸鍧愭爣锛?
        next_node_3d = AGVs(id).path(AGVs(id).path_idx, :); % 鑾峰彇涓嬩竴涓矾寰勭偣锛堝寘鍚潗鏍囧拰鏃堕棿鎴筹級
        nr = next_node_3d(1); nc = next_node_3d(2);        % 涓嬩竴涓綅缃殑琛屻€佸垪鍧愭爣
        target_t = next_node_3d(3);                        % 棰勮鍒拌揪璇ョ偣鐨勬椂闂存锛堢敤浜庢椂闂村啿绐佹娴嬶級
    
        % --- 鍐茬獊妫€娴嬶細妫€鏌ヤ笅涓€涓妭鐐规槸鍚︿笌鍏朵粬AGV鍐茬獊 ---
        for other = 1:num_agvs
            if other == id, continue; end                  % 璺宠繃鑷韩
    
            other_curr = AGVs(other).pos;                  % 鍏朵粬AGV鐨勫綋鍓嶄綅缃?
    
            % 瀹氫箟鍝簺鐘舵€佸睘浜庘€滄鍦ㄧЩ鍔ㄢ€濈殑鐘舵€侊紙杩欎簺AGV鏈夊姩鎬佽矾寰勶級
            moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home', 'Yielding'};
    
            % 鍒ゆ柇鍏朵粬AGV鏄惁姝ｅ湪绉诲姩涓紙鏈夎矾寰勩€佹湭璧板畬銆佺Щ鍔ㄨ鏃跺櫒宸插綊闆躲€佺姸鎬佸睘浜庣Щ鍔ㄧ姸鎬侊級
            is_other_moving = ~isempty(AGVs(other).path) && ...
                              AGVs(other).path_idx <= size(AGVs(other).path, 1) && ...
                              AGVs(other).move_timer <= 0 && ...
                              ismember(AGVs(other).status, moving_states);
    
            if is_other_moving
                % 濡傛灉姝ｅ湪绉诲姩锛岃幏鍙栧叾涓嬩竴涓矾寰勭偣锛堝寘鍚椂闂存埑锛?
                other_next_3d = AGVs(other).path(AGVs(other).path_idx, :);
                other_next_r = other_next_3d(1);
                other_next_c = other_next_3d(2);
                other_next_t = other_next_3d(3);
            else
                % 濡傛灉鏈湪绉诲姩锛堥潤姝㈡垨绛夊緟锛夛紝鍒欏皢鍏跺綋鍓嶄綅缃涓哄叾鈥滀笅涓€涓妭鐐光€?
                other_next_r = other_curr(1);
                other_next_c = other_curr(2);
                other_next_t = target_t;   % 闈欐AGV鐨勬椂闂存埑瑙嗕负涓庡綋鍓岮GV鐩稿悓锛堟垨浠绘剰锛?
            end
    
            % 鍐茬獊鏉′欢1锛氫笅涓€涓妭鐐规濂芥槸鍏朵粬AGV鐨勪笅涓€涓妭鐐癸紙鍚屾椂鐢宠鍚屼竴鑺傜偣锛?
            if nr == other_next_r && nc == other_next_c
                status = -other;   % 杩斿洖璐熺殑闃诲鑰匢D
                return;
            end
    
            % 鍐茬獊鏉′欢2锛氱浉鍚戜氦鎹綅缃?
            % 鎴戠殑涓嬩竴涓妭鐐规槸鍏朵粬AGV鐨勫綋鍓嶄綅缃紝涓斿叾浠朅GV鐨勪笅涓€涓妭鐐规槸鎴戠殑褰撳墠浣嶇疆
            if nr == other_curr(1) && nc == other_curr(2) && ...
               other_next_r == curr_pos(1) && other_next_c == curr_pos(2)
                status = -other;
                return;
            end
    
            % 鍐茬獊鏉′欢3锛氭垜鐨勪笅涓€涓妭鐐硅鍏朵粬AGV鍗犳嵁锛屼笖鎴戠殑棰勮鍒拌揪鏃堕棿涓嶆櫄浜庡鏂圭寮€鐨勬椂闂?
            % 鍗冲鏂硅繕鍦ㄨ鑺傜偣鎴栧皻鏈寮€
            if nr == other_curr(1) && nc == other_curr(2) && target_t <= other_next_t
                status = -other;
                return;
            end
        end
        % --- 鍐茬獊妫€娴嬬粨鏉燂紝鏃犲啿绐侊紝鍙互绉诲姩 ---
    
        AGVs(id).pos = [nr, nc];                             % 鏇存柊AGV浣嶇疆鍒颁笅涓€涓妭鐐?
    
        curr_dir = [nr - curr_pos(1), nc - curr_pos(2)];    % 璁＄畻褰撳墠绉诲姩鏂瑰悜鐭㈤噺
    
        % 濡傛灉涓婁竴姝ユ湁鏂瑰悜锛堜笉鏄垵濮嬬姸鎬侊級涓斿綋鍓嶆柟鍚戜笌涓婁竴姝ユ柟鍚戜笉鍚岋紝鍒欒浆寮鏁板姞1
        if ~isequal(AGVs(id).last_dir, [0, 0]) && ~isequal(AGVs(id).last_dir, curr_dir)
            AGVs(id).total_turns = AGVs(id).total_turns + 1;
        end
        AGVs(id).last_dir = curr_dir;                        % 鏇存柊涓婁竴姝ユ柟鍚?
    
        tid = AGVs(id).active_task_id;                       % 鑾峰彇褰撳墠娲昏穬浠诲姟ID锛堝彇璐ф垨閫佽揣浠诲姟锛?
        if tid > 0
            % 璁板綍璇ヤ换鍔＄殑杞ㄨ抗鐐癸紙灏嗗綋鍓嶄綅缃拷鍔犲埌璇ヤ换鍔＄殑杞ㄨ抗鍒楄〃涓級
            task_trajectories{tid} = [task_trajectories{tid}; AGVs(id).pos];
        end
        if ~isempty(AGVs(id).tasks)
            % 濡傛灉AGV鏈夊墿浣欎换鍔″垪琛紝瀵逛簬姣忎釜灏氭湭瀹屾垚浣嗗凡寮€濮嬭褰曠殑浠诲姟锛堝紑濮嬫椂闂?0锛夛紝涔熻褰曞叾杞ㄨ抗
            for i = 1:length(AGVs(id).tasks)
                q_tid = AGVs(id).tasks(i);
                if q_tid ~= tid && task_times(q_tid, 1) > 0   % 浠诲姟宸插紑濮嬩絾闈炲綋鍓嶆椿璺?
                    task_trajectories{q_tid} = [task_trajectories{q_tid}; AGVs(id).pos];
                end
            end
        end
    
        AGVs(id).total_dist = AGVs(id).total_dist + 1;       % 绱琛岄┒璺濈鍔?鏍?
        AGVs(id).path_idx = AGVs(id).path_idx + 1;           % 璺緞绱㈠紩鎸囧悜涓嬩竴涓偣
        AGVs(id).move_timer = AGVs(id).step_dur;              % 璁剧疆绉诲姩璁℃椂鍣紙鐢ㄤ簬鎺у埗绉诲姩閫熷害/鍔ㄧ敾锛?
    
        % 鑳借€楄绠椾笌鐢垫睜娑堣€?
        e_b = agv_params(id).e_base;                          % 鍩虹鑳借€楃郴鏁?
        e_l = agv_params(id).e_load_factor;                   % 璐熻浇鑳借€楀洜瀛?
        cost = (e_b + e_l * AGVs(id).payload_weight / 100.0); % 褰撳墠姝ョ殑鑳借€楋紙鍩轰簬杞介噸锛?
        AGVs(id).battery = max(0, AGVs(id).battery - cost);   % 鎵ｉ櫎鐢甸噺锛屼笉浣庝簬0
    
        % 鍒ゆ柇鏄惁宸插埌杈捐矾寰勭粓鐐?
        if AGVs(id).path_idx > size(AGVs(id).path, 1)
            AGVs(id).last_dir = [0, 0];   % 鍒拌揪缁堢偣锛屾竻绌烘柟鍚戯紙涓嬫杞集涓嶈锛?
            status = 1;                    % 杩斿洖鍒拌揪鐘舵€?
        else
            status = 0;                    % 灏氭湭鍒拌揪缁堢偣锛岃繑鍥炴甯哥Щ鍔ㄧ姸鎬?
        end
    end
    
    function handle_arrival(id, ~)
        % 鍑芥暟鍔熻兘锛氬鐞咥GV鍒拌揪鐩爣鐐瑰悗鐨勪簨浠讹紝鏍规嵁褰撳墠鐘舵€佸垏鎹㈠埌鐩稿簲鐨勭瓑寰呯姸鎬?
        % 杈撳叆鍙傛暟锛?
        %   id - AGV鐨勭储寮曠紪鍙?
        %   ~  - 绗簩涓弬鏁拌蹇界暐锛堝彲鑳芥槸涓轰簡缁熶竴鎺ュ彛锛屽疄闄呮湭浣跨敤锛?
    
        % 鑾峰彇璇GV鐨勫綋鍓嶇姸鎬?
        st = AGVs(id).status;
    
        % 鏍规嵁涓嶅悓鐨勭Щ鍔ㄧ姸鎬佽繘琛屽垎鏀鐞?
        if strcmp(st, 'Moving_Pick')
            % 濡傛灉褰撳墠鐘舵€佹槸鈥滃幓鍙栬揣閫斾腑鈥濓紝璇存槑宸茬粡鍒拌揪鍙栬揣鐐?
            AGVs(id).status = 'Loading';       % 鍒囨崲鐘舵€佷负鈥滆杞戒腑鈥?
            AGVs(id).wait_timer = 6;            % 璁剧疆瑁呰浇绛夊緟鏃堕棿锛?涓椂闂存锛?
    
        elseif strcmp(st, 'Moving_Drop')
            % 濡傛灉褰撳墠鐘舵€佹槸鈥滃幓閫佽揣閫斾腑鈥濓紝璇存槑宸茬粡鍒拌揪閫佽揣鐐?
            AGVs(id).status = 'Unloading';      % 鍒囨崲鐘舵€佷负鈥滃嵏璐т腑鈥?
            AGVs(id).wait_timer = 6;            % 璁剧疆鍗歌揣绛夊緟鏃堕棿锛?涓椂闂存锛?
    
        elseif strcmp(st, 'Going_Charge')
            % 濡傛灉褰撳墠鐘舵€佹槸鈥滃幓鍏呯數閫斾腑鈥濓紝璇存槑宸茬粡鍒拌揪鍏呯數绔?
            AGVs(id).status = 'Charging';       % 鍒囨崲鐘舵€佷负鈥滃厖鐢典腑鈥?
            AGVs(id).wait_timer = 30;           % 璁剧疆鍏呯數绛夊緟鏃堕棿锛?0涓椂闂存锛?
    
        elseif strcmp(st, 'Go_Home')
            % 濡傛灉褰撳墠鐘舵€佹槸鈥滃洖瀹堕€斾腑鈥濓紝璇存槑宸茬粡鍥炲埌Home浣嶇疆
            AGVs(id).status = 'Idle';           % 鍒囨崲鐘舵€佷负鈥滅┖闂测€濓紙鍥炲鍚庢棤浜嬪彲鍋氾級
    
        elseif strcmp(st, 'Yielding')
            % 濡傛灉褰撳墠鐘舵€佹槸鈥滆琛屼腑鈥濓紝璇存槑AGV鍒拌揪浜嗕复鏃剁殑璁╄鐐?
            % 姝ゆ椂闇€瑕佹仮澶嶄箣鍓嶈涓柇鐨勪换鍔＄姸鎬?
            resume_after_yield(id, t);           % 璋冪敤鎭㈠鍑芥暟锛屼紶鍏ュ綋鍓嶆椂闂存t
        end
        % 娉ㄦ剰锛氬叾浠栫姸鎬侊紙濡侺oading, Unloading, Charging, Idle锛変笉浼氳繘鍏ユ鍑芥暟锛?
        % 鍥犱负璇ュ嚱鏁板彧鍦ㄧЩ鍔ㄧ姸鎬佸埌杈剧洰鏍囩偣鏃惰璋冪敤锛堢敱execute_move杩斿洖1瑙﹀彂锛夈€?
    end

    function resume_after_yield(id, current_t)
        % 鍑芥暟鍔熻兘锛氳琛岀粨鏉熷悗锛屾仮澶岮GV鍒拌涓柇鍓嶇殑鐘舵€侊紝缁х画鎵ц鍘熶换鍔?
        % 杈撳叆鍙傛暟锛?
        %   id        - AGV鐨勭储寮曠紪鍙?
        %   current_t - 褰撳墠浠跨湡鏃堕棿姝ワ紙鐢ㄤ簬璺緞瑙勫垝鐨勬椂闂存埑锛?
    
        % 鑾峰彇璇GV鍦ㄨ琛屽墠璁板綍鐨勭姸鎬侊紙鐢?resolve_conflict 涓缃級
        resume_status = AGVs(id).yield_resume_status;
    
        % 濡傛灉娌℃湁璁板綍浠讳綍涓柇鐘舵€侊紙鐞嗚涓婁笉浼氬彂鐢燂紝浣嗗仛闃插尽鎬у鐞嗭級
        if isempty(resume_status)
            AGVs(id).status = 'Idle';        % 鐩存帴缃负绌洪棽鐘舵€?
            return;                           % 鎻愬墠杩斿洖
        end
    
        % 鏍规嵁璁板綍鐨勪腑鏂姸鎬佽繘琛屽垎鏀仮澶?
        if strcmp(resume_status, 'Moving_Pick')
            % 涔嬪墠鏄湪鍘诲彇璐х殑璺笂琚腑鏂?
            tid = AGVs(id).active_task_id;                     % 鑾峰彇褰撴椂姝ｅ湪鎵ц鐨勫彇璐т换鍔D
            row_idx = get_task_row(tid);                        % 鍦ㄤ换鍔″垪琛ㄤ腑鏌ユ壘璇ヤ换鍔＄殑琛岀储寮?
            if row_idx == 0                                      % 濡傛灉浠诲姟涓嶅瓨鍦紙鍙兘宸茶鍒犻櫎锛?
                AGVs(id).status = 'Idle';                        % 缃负绌洪棽
                AGVs(id).yield_resume_status = '';               % 娓呯┖涓柇璁板綍
                return;
            end
            target_id = task_list(row_idx, 2);                   % 鑾峰彇鐩爣绔欑偣ID
            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); % 鑾峰彇鍙栬揣鐐瑰尯鍩熶俊鎭?
    
            % 閲嶆柊瑙勫垝鍒板彇璐х偣鐨勮矾寰?
            if plan_path(id, pick_anchor, pick_size, current_t)  % 璺緞瑙勫垝鎴愬姛
                AGVs(id).status = 'Moving_Pick';                 % 鎭㈠涓哄彇璐хЩ鍔ㄧ姸鎬?
                AGVs(id).yield_resume_status = '';                % 娓呯┖涓柇璁板綍
            else
                % 璺緞瑙勫垝澶辫触锛堝彲鑳界洰鏍囩偣琚崰鎴栦笉鍙揪锛夛紝鍒欑户缁繚鎸佸湪璁╄鐘舵€侊紝绋嶅悗閲嶈瘯
                AGVs(id).status = 'Yielding';                     % 淇濇寔璁╄鐘舵€?
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);  % 璁剧疆绉诲姩璁℃椂鍣紙绛夊緟涓€娈垫椂闂达級
            end
    
        elseif strcmp(resume_status, 'Moving_Drop')
            % 涔嬪墠鏄湪鍘婚€佽揣鐨勮矾涓婅涓柇
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                AGVs(id).status = 'Idle';
                AGVs(id).yield_resume_status = '';
                return;
            end
            target_id = task_list(row_idx, 2);
            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id); % 鑾峰彇閫佽揣鐐瑰尯鍩熶俊鎭?
    
            if plan_path(id, drop_anchor, drop_size, current_t)
                AGVs(id).status = 'Moving_Drop';
                AGVs(id).yield_resume_status = '';
            else
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
    
        elseif strcmp(resume_status, 'Go_Home')
            % 涔嬪墠鏄湪鍥炲鐨勮矾涓婅涓柇
            % 鏍规嵁AGV绫诲瀷纭畾瀹跺尯鍩熺殑灏哄
            if AGVs(id).type == 2
                agv_area_sz = [3, 3];      % 鍙夎溅鎵€闇€鍖哄煙杈冨ぇ
            else
                agv_area_sz = [1, 1];      % 鎵樹妇杞﹀尯鍩熻緝灏?
            end
            % 瑙勫垝鍥炲璺緞
            if plan_path(id, AGVs(id).home_pos, agv_area_sz, current_t)
                AGVs(id).status = 'Go_Home';
                AGVs(id).yield_resume_status = '';
            else
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
    
        elseif strcmp(resume_status, 'Going_Charge')
            % 涔嬪墠鏄湪鍘诲厖鐢电殑璺笂琚腑鏂?
            AGVs(id).yield_resume_status = '';                    % 娓呯┖涓柇璁板綍锛堥伩鍏嶅惊鐜級
            plan_to_charge(id, current_t);                         % 閲嶆柊璋冪敤鍏呯數瑙勫垝鍑芥暟
            % 妫€鏌ユ槸鍚︽垚鍔熻繘鍏ヤ簡 Going_Charge 鐘舵€侊紙plan_to_charge 鍐呴儴浼氳缃姸鎬侊級
            if ~strcmp(AGVs(id).status, 'Going_Charge')
                % 濡傛灉鏈兘杩涘叆鍏呯數鐘舵€侊紙渚嬪鎵€鏈夊厖鐢电珯琚崰锛夛紝鍒欓噸鏂拌缃腑鏂褰曞苟缁х画璁╄绛夊緟
                AGVs(id).yield_resume_status = 'Going_Charge';     % 閲嶆柊璁板綍涓柇鐘舵€?
                AGVs(id).status = 'Yielding';                       % 淇濇寔鍦ㄨ琛岀姸鎬?
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);   % 绛夊緟鍚庨噸璇?
            end
    
        else
            % 濡傛灉璁板綍鐨勪腑鏂姸鎬佷笉鍦ㄤ笂杩拌寖鍥村唴锛堢悊璁轰笂涓嶅簲鍙戠敓锛夛紝鍒欑洿鎺ユ仮澶嶅埌璁板綍鐨勭姸鎬?
            AGVs(id).status = resume_status;
            AGVs(id).yield_resume_status = '';                     % 娓呯┖涓柇璁板綍
        end
    end
    
    function finish_waiting(id, tasks_info)
        % 鍑芥暟鍔熻兘锛氬綋AGV瀹屾垚绛夊緟锛堣杞芥垨鍗歌揣锛夊悗锛屾洿鏂扮姸鎬佸苟寮€濮嬩笅涓€姝ュ姩浣?
        % 杈撳叆鍙傛暟锛?
        %   id          - AGV鐨勭储寮曠紪鍙?
        %   tasks_info  - 浠诲姟鍒楄〃鐭╅樀锛屾瘡琛?[浠诲姟ID, 鐩爣绔欑偣ID, 璐х墿閲嶉噺]
    
        st = AGVs(id).status;   % 鑾峰彇AGV褰撳墠鐘舵€侊紙Loading 鎴?Unloading锛?
    
        %% 澶勭悊瑁呰浇瀹屾垚锛圠oading 鐘舵€侊級
        if strcmp(st, 'Loading')
            tid = AGVs(id).active_task_id;                 % 鑾峰彇褰撳墠瑁呰浇鐨勪换鍔D
            row_idx = get_task_row(tid);                    % 鍦ㄤ换鍔″垪琛ㄤ腑鏌ユ壘璇ヤ换鍔＄殑琛岀储寮?
            if row_idx == 0                                  % 濡傛灉浠诲姟涓嶅瓨鍦紙鍙兘宸茶鍒犻櫎锛?
                AGVs(id).status = 'Idle';                    % 灏咥GV缃负绌洪棽
                AGVs(id).active_task_id = 0;                 % 娓呯┖娲昏穬浠诲姟ID
                return;                                       % 鐩存帴杩斿洖
            end
            task_weight = tasks_info(row_idx, 3);            % 鑾峰彇璇ヤ换鍔＄殑璐х墿閲嶉噺
    
            % 璁板綍浠诲姟寮€濮嬫椂闂达紙濡傛灉灏氭湭璁板綍锛?
            if task_times(tid, 1) == 0, task_times(tid, 1) = t; end
            task_start_dist(tid) = AGVs(id).total_dist;      % 璁板綍寮€濮嬫椂鐨勭疮璁¤椹惰窛绂?
            task_executor(tid) = id;                          % 璁板綍鎵ц璇ヤ换鍔＄殑AGV缂栧彿
    
            AGVs(id).payload_weight = AGVs(id).payload_weight + task_weight; % 澧炲姞褰撳墠杞介噸
            AGVs(id).load = 1;                                 % 鏍囪涓鸿浇璐х姸鎬?
    
            % 鎺у埗鍙拌緭鍑鸿杞戒俊鎭?
            fprintf('[AGV-%02d] 鎴愬姛瑁呰浇璁㈠崟 #%d | 閲嶉噺: %d | 杞︿笂鎬婚噸: %d\n', ...
                id, tid, task_weight, AGVs(id).payload_weight);
    
            % --- 闃熷垪娴佽浆閫昏緫 ---
            if ~isempty(AGVs(id).pick_queue)
                % 濡傛灉鍙栬揣闃熷垪涓繕鏈変换鍔★紝鍒欑户缁彇涓嬩竴涓?
                next_tid = AGVs(id).pick_queue(1);            % 鑾峰彇涓嬩竴涓换鍔D
                AGVs(id).pick_queue(1) = [];                   % 浠庨槦鍒椾腑绉婚櫎
                AGVs(id).active_task_id = next_tid;            % 璁剧疆涓哄綋鍓嶆椿璺冧换鍔?
    
                next_row = get_task_row(next_tid);
                if next_row == 0                                % 濡傛灉涓嬩竴涓换鍔℃棤鏁?
                    AGVs(id).status = 'Idle';                    % 缃负绌洪棽
                    AGVs(id).active_task_id = 0;                 % 娓呯┖娲昏穬浠诲姟
                    AGVs(id).pick_queue = [];                    % 娓呯┖鍙栬揣闃熷垪
                    AGVs(id).drop_queue = [];                    % 娓呯┖鍗歌揣闃熷垪
                    return;
                end
                next_target_id = tasks_info(next_row, 2);      % 鑾峰彇涓嬩竴涓换鍔＄殑鐩爣绔欑偣ID
                [pick_anchor, ~, pick_size, ~] = get_task_coordinates(next_target_id); % 鑾峰彇鍙栬揣鐐瑰尯鍩熶俊鎭?
    
                if plan_path(id, pick_anchor, pick_size, t)    % 瑙勫垝鍒颁笅涓€涓彇璐х偣鐨勮矾寰?
                    AGVs(id).status = 'Moving_Pick';            % 鎴愬姛鍒欒浆鍏ュ彇璐хЩ鍔ㄧ姸鎬?
                else
                    AGVs(id).wait_timer = 2;                     % 澶辫触鍒欑瓑寰?姝ュ悗閲嶈瘯
                    AGVs(id).pick_queue = [next_tid, AGVs(id).pick_queue]; % 灏嗕换鍔￠噸鏂版斁鍥為槦鍒楀ご閮?
                end
            else
                % 鍙栬揣闃熷垪涓虹┖锛岃鏄庤鎵规鐨勬墍鏈夎揣鐗╅兘宸茶杞︼紝鐜板湪寮€濮嬮€佽揣
                first_drop_tid = AGVs(id).drop_queue(1);       % 鑾峰彇鍗歌揣闃熷垪鐨勭涓€涓换鍔?
                AGVs(id).drop_queue(1) = [];                    % 浠庨槦鍒椾腑绉婚櫎
                AGVs(id).active_task_id = first_drop_tid;       % 璁剧疆涓哄綋鍓嶆椿璺冧换鍔?
    
                drop_row = get_task_row(first_drop_tid);
                if drop_row == 0                                 % 濡傛灉浠诲姟鏃犳晥
                    AGVs(id).status = 'Idle';                     % 缃负绌洪棽
                    AGVs(id).active_task_id = 0;                  % 娓呯┖娲昏穬浠诲姟
                    AGVs(id).drop_queue = [];                     % 娓呯┖鍗歌揣闃熷垪
                    return;
                end
                drop_target_id = tasks_info(drop_row, 2);       % 鑾峰彇閫佽揣鐩爣绔欑偣ID
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(drop_target_id); % 鑾峰彇閫佽揣鐐瑰尯鍩熶俊鎭?
    
                if plan_path(id, drop_anchor, drop_size, t)     % 瑙勫垝鍒伴€佽揣鐐圭殑璺緞
                    AGVs(id).status = 'Moving_Drop';             % 鎴愬姛鍒欒浆鍏ラ€佽揣绉诲姩鐘舵€?
                else
                    AGVs(id).wait_timer = 2;                      % 澶辫触鍒欑瓑寰呭悗閲嶈瘯
                    AGVs(id).drop_queue = [first_drop_tid, AGVs(id).drop_queue]; % 浠诲姟鏀惧洖闃熷垪
                end
            end
    
        %% 澶勭悊鍗歌揣瀹屾垚锛圲nloading 鐘舵€侊級
        elseif strcmp(st, 'Unloading')
            tid = AGVs(id).active_task_id;                      % 鑾峰彇褰撳墠鍗歌揣鐨勪换鍔D
            row_idx = get_task_row(tid);                         % 鏌ユ壘浠诲姟琛岀储寮?
            if row_idx == 0                                       % 浠诲姟涓嶅瓨鍦?
                AGVs(id).status = 'Idle';
                AGVs(id).active_task_id = 0;
                return;
            end
            task_weight = tasks_info(row_idx, 3);                 % 鑾峰彇浠诲姟閲嶉噺
    
            task_times(tid, 2) = t;                               % 璁板綍浠诲姟缁撴潫鏃堕棿姝?
            % 璁＄畻鑰楁椂锛堣浆鎹负绉掞紝鍋囪姣忔瀵瑰簲1/6绉掞級
            time_spent_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
            task_dist_record(tid) = AGVs(id).total_dist - task_start_dist(tid); % 璁＄畻璇ヤ换鍔¤椹惰窛绂?
    
            % 鎺у埗鍙拌緭鍑轰换鍔″畬鎴愪俊鎭?
            fprintf('鉁?[AGV-%02d] 浠诲姟瀹屾垚锛佽鍗?#%d | 鑰楁椂: %.1f绉?| 杩愰€侀噷绋? %d鏍糪n', ...
                id, tid, time_spent_sec, task_dist_record(tid));
    
            % 鎵ｉ櫎杞介噸骞朵粠璇ヨ溅鐨勫墿浣欎换鍔″垪琛ㄤ腑绉婚櫎宸插畬鎴愪换鍔?
            AGVs(id).payload_weight = max(0, AGVs(id).payload_weight - task_weight);
            AGVs(id).tasks(AGVs(id).tasks == tid) = [];          % 浠庝换鍔″垪琛ㄤ腑鍒犻櫎
    
            if ~isempty(AGVs(id).drop_queue)
                % 濡傛灉鍗歌揣闃熷垪涓繕鏈変换鍔★紝缁х画閫佷笅涓€浠?
                next_drop_tid = AGVs(id).drop_queue(1);          % 鑾峰彇涓嬩竴涓嵏璐т换鍔?
                AGVs(id).drop_queue(1) = [];                      % 浠庨槦鍒椾腑绉婚櫎
                AGVs(id).active_task_id = next_drop_tid;          % 璁剧疆涓哄綋鍓嶆椿璺冧换鍔?
    
                next_row = get_task_row(next_drop_tid);
                if next_row == 0                                   % 浠诲姟鏃犳晥
                    AGVs(id).status = 'Idle';
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    return;
                end
                next_target_id = tasks_info(next_row, 2);         % 鑾峰彇閫佽揣鐩爣绔欑偣ID
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(next_target_id); % 鑾峰彇閫佽揣鐐瑰尯鍩?
    
                if plan_path(id, drop_anchor, drop_size, t)       % 瑙勫垝璺緞
                    AGVs(id).status = 'Moving_Drop';              % 杞叆閫佽揣绉诲姩鐘舵€?
                else
                    AGVs(id).wait_timer = 2;                       % 澶辫触鍒欑瓑寰呴噸璇?
                    AGVs(id).drop_queue = [next_drop_tid, AGVs(id).drop_queue]; % 浠诲姟鏀惧洖
                end
            else
                % 鍗歌揣闃熷垪涓虹┖锛岃鏄庤鎵规鎵€鏈変换鍔″凡瀹屾垚
                fprintf('   -> AGV-%02d 鎵规閰嶉€佸叏閮ㄦ敹瀹樸€俓n', id);
                AGVs(id).status = 'Idle';                          % 缃负绌洪棽
                AGVs(id).load = 0;                                  % 鏍囪涓虹┖杞?
                AGVs(id).active_task_id = 0;                       % 娓呯┖娲昏穬浠诲姟
            end
        end
    end 

    function export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories)
        disp('>> [鏁版嵁妯″潡] 姝ｅ湪鐢熸垚浠跨湡鎶ュ憡...');
        save_dir = fileparts(mfilename('fullpath')); % 鑾峰彇褰撳墠鑴氭湰鎵€鍦ㄧ粷瀵硅矾寰?
        
        % 1. 瀵煎嚭浠诲姟鎸囨爣 (task_metrics.csv)
        try
            csv_file_path = fullfile(save_dir, 'task_metrics.csv');
            fid = fopen(csv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid, 'task_id,agv_id,time_sec,distance\n');
            for i = 1:size(task_list, 1)
                tid = task_list(i, 1);
                if task_times(tid, 2) > 0 % 鍙褰曞凡瀹屾垚鐨勪换鍔?
                    t_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
                    dist = task_dist_record(tid);
                    agv_str = sprintf('AGV-%02d', task_executor(tid));
                    fprintf(fid, '%d,%s,%.1f,%d\n', tid, agv_str, t_sec, dist);
                end
            end
            fclose(fid);
            disp('  -> 宸茬敓鎴? task_metrics.csv');
        catch ME
            fprintf('  -> [閿欒] task_metrics.csv 鐢熸垚澶辫触: %s\n', ME.message);
        end
        
        % 2. 瀵煎嚭杞ㄨ抗鏁版嵁 (task_paths.json)
        try
            path_struct = struct();
            for i = 1:size(task_list, 1)
                tid = task_list(i, 1);
                if ~isempty(task_trajectories{tid})
                    fname = sprintf('task_%d', tid);
                    path_struct.(fname) = task_trajectories{tid};
                end
            end
            
            json_str = jsonencode(path_struct);
            json_file_path = fullfile(save_dir, 'task_paths.json');
            fid_json = fopen(json_file_path, 'w');
            if fid_json ~= -1
                fprintf(fid_json, '%s', json_str);
                fclose(fid_json);
                disp('  -> 宸茬敓鎴? task_paths.json');
            else
                disp('  -> [閿欒] 鏃犳硶鍒涘缓 task_paths.json 鏂囦欢锛?);
            end
        catch ME
            fprintf('  -> [閿欒] task_paths.json 鐢熸垚澶辫触: %s\n', ME.message);
        end
        
        % 3. 瀵煎嚭璁惧鐘舵€?(agv_metrics.csv)
        try
            agv_file_path = fullfile(save_dir, 'agv_metrics.csv');
            fid_agv = fopen(agv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid_agv, 'agv_id,agv_type,battery,total_distance,total_turns\n');
            for k = 1:num_agvs
                fprintf(fid_agv, '%d,%d,%.2f,%d,%d\n', ...
                    k, AGVs(k).type, AGVs(k).battery, AGVs(k).total_dist, AGVs(k).total_turns);
            end
            fclose(fid_agv);
            disp('  -> 宸茬敓鎴? agv_metrics.csv');
        catch ME
            fprintf('  -> [閿欒] agv_metrics.csv 鐢熸垚澶辫触: %s\n', ME.message);
        end
    end

end
