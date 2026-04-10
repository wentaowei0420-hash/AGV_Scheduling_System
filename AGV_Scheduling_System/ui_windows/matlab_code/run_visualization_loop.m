function run_visualization_loop(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % 实时仿真主循环函数，负责可视化所有AGV的运动、任务执行、充电、冲突消解等。
    
    global mapW mapH binaryMap; 
    
    % --- 1. 初始化图形界面 ---
    generate_beautiful_factory_map();   
    f_map = gcf;                        
    ax = findobj(f_map, 'Type', 'Axes'); 
    hold(ax, 'on');                      
    set(f_map, 'Name', '实时动态调度仿真', 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', 'Position', [50, 200, 1000, 700]);
    
    [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs);
    
    % --- 2. 初始化 AGV 对象 ---
    [AGVs, props, ~] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax);
    
    % --- 3. 实时仿真主循环 ---
    disp('>> [系统] 实时仿真启动...'); 
    
    % ========================================================
    % 【新增1】：初始化多载荷队列与状态记忆
    for k = 1:num_agvs
        AGVs(k).total_turns = 0;           % 运行转弯总数
        AGVs(k).last_dir = [0, 0];         % 上一步方向矢量
        
        AGVs(k).pick_queue = [];           % 取货任务队列
        AGVs(k).drop_queue = [];           % 卸货任务队列
        AGVs(k).active_task_id = 0;        % 当前正在导航的具体子任务ID
        AGVs(k).interrupted_status = '';   % 记忆因没电去充电前被中断的状态
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
        % --- A. 逻辑更新 ---
        for k = 1:num_agvs                
            if AGVs(k).move_timer > 0      
                AGVs(k).move_timer = AGVs(k).move_timer - 1; 
                all_finished = false;       
                continue;                    
            end
            
            % 动态设置专属车体/充电桩尺寸
            if AGVs(k).type == 2
                agv_area_sz = [3, 3]; % 叉车大尺寸
            else
                agv_area_sz = [2, 2]; % 托举小尺寸
            end
            
            % 根据当前状态执行相应行为
            switch AGVs(k).status
                case 'Idle'   % 空闲状态
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
                            AGVs(k).active_task_id = 0; % 非法记忆则重置
                        end
                        all_finished = false;
                        
                    elseif ~isempty(AGVs(k).tasks)  
                        % ======================================================
                        % 【新增核心】：批量组装订单逻辑 (Type 1 多件，Type 2 单件)
                        max_load_capacity = 80; % 托举车最大载重（可调）
                        batch_tasks = [];
                        current_batch_weight = 0;
                        
                        for i = 1:length(AGVs(k).tasks)
                            tid = AGVs(k).tasks(i);
                            row_idx = find(task_list(:,1) == tid);
                            w = task_list(row_idx, 3);
                            
                            % 【物理约束】：叉车(Type 2) 一次严格只拉一个！
                            if AGVs(k).type == 2 && i > 1
                                break; 
                            end
                            
                            % 【物理约束】：托举车(Type 1) 根据载重一直往里塞
                            if i == 1 || (current_batch_weight + w <= max_load_capacity)
                                batch_tasks = [batch_tasks, tid];
                                current_batch_weight = current_batch_weight + w;
                            else
                                break; % 超重，截断当前批次
                            end
                        end
                        
                        AGVs(k).pick_queue = batch_tasks;
                        AGVs(k).drop_queue = batch_tasks;
                        
                        % 弹出第一个任务，前往取货点
                        first_tid = AGVs(k).pick_queue(1);
                        AGVs(k).pick_queue(1) = [];
                        AGVs(k).active_task_id = first_tid;
                        
                        row_idx = find(task_list(:,1) == first_tid);
                        target_id = task_list(row_idx, 2);
                        [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); 
                        
                        if plan_path(k, pick_anchor, pick_size)
                            AGVs(k).status = 'Moving_Pick';      
                        else
                            % 被堵死规划失败，退回防丢失
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
                    % 【新增记忆功能】：没电去充电时，精准记住死在了哪个状态！
                    if AGVs(k).battery < 20 && ~strcmp(AGVs(k).status, 'Going_Charge') && ~strcmp(AGVs(k).status, 'Charging')
                        disp(['AGV-', num2str(k), ' 电量耗尽，保留队列现场，前往充电...']);
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
                            % 充满电后直接打回 'Idle'，下个周期会让它利用记忆自动接续任务
                            AGVs(k).status = 'Idle'; 
                        end
                    end
                    
                    if AGVs(k).wait_timer <= 0 && ~strcmp(AGVs(k).status, 'Charging') && ~strcmp(AGVs(k).status, 'Go_Home')
                        finish_waiting(k, task_list);   
                    end
            end
        end
        if all_finished, break; end   
        
        % --- B. 动画显示 ---
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
        csv_file_path = fullfile(save_dir, 'task_metrics.csv'); % 拼接绝对路径
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
                % 只有当任务真正执行并产生轨迹时才记录
                if ~isempty(task_trajectories{tid})
                    % 以 task_ID 为 Key 存储坐标矩阵
                    fname = sprintf('task_%d', tid);
                    path_struct.(fname) = task_trajectories{tid};
                end
            end
            
            % 转换为 JSON 格式字符串并写入文件
            json_str = jsonencode(path_struct);
            json_file_path = fullfile(save_dir, 'task_paths.json'); % 拼接绝对路径
            fid_json = fopen(json_file_path, 'w');
            if fid_json ~= -1
                fprintf(fid_json, '%s', json_str);
                fclose(fid_json);
                disp('>> 已生成轨迹详细数据：task_paths.json');
            else
                disp('>> 错误：无法创建 task_paths.json 文件！');
            end
        catch ME
            fprintf('>> 轨迹导出异常: %s\n', ME.message);
        end
        disp('>> 已生成任务指标报告：task_metrics.csv');
    catch
        disp('>> 警告：生成 task_metrics.csv 失败！');
    end
    try
        agv_file_path = fullfile(save_dir, 'agv_metrics.csv'); % 拼接绝对路径
        fid_agv = fopen(agv_file_path, 'w', 'n', 'utf-8');
        fprintf(fid_agv, 'agv_id,agv_type,battery,total_distance,total_turns\n');
        for k = 1:num_agvs
            fprintf(fid_agv, '%d,%d,%.2f,%d,%d\n', ...
                k, AGVs(k).type, AGVs(k).battery, AGVs(k).total_dist, AGVs(k).total_turns);
        end
        fclose(fid_agv);
        disp('>> 已生成设备状态报告：agv_metrics.csv');
    catch
        disp('>> 警告：生成 agv_metrics.csv 失败！');
    end
    % ========================================================
    disp('>> 仿真结束。');                              
    
    disp('========================================');
    disp('         AGV 运行总转弯次数统计         ');
    disp('========================================');
    for k = 1:num_agvs
        agv_type_str = '未知';
        if AGVs(k).type == 1, agv_type_str = '托举式'; end
        if AGVs(k).type == 2, agv_type_str = '叉车式'; end
        fprintf('  AGV-%02d (%s)  |  共转弯 %d 次\n', k, agv_type_str, AGVs(k).total_turns);
    end
    disp('========================================');
    
    
    % ==============================================================
    % ============== 嵌套辅助函数区域 ==============================
    % ==============================================================
    function resolve_conflict(id_self, id_blocker, tasks_info, current_t)
        c_type = identify_conflict(id_self, id_blocker, AGVs); 
        conflict_name = '未知冲突';
        if c_type == 1, conflict_name = '相向冲突'; end
        if c_type == 2, conflict_name = '节点冲突'; end
        if c_type == 3, conflict_name = '占位冲突'; end
        if c_type == 4, conflict_name = '追赶冲突'; end
        
        P_self = calculate_ahp_priority(AGVs(id_self), tasks_info, current_t);
        P_blocker = calculate_ahp_priority(AGVs(id_blocker), tasks_info, current_t);
        
        disp(['[控制台] 检测到 ', conflict_name, ' (AGV-', num2str(id_self), ' 与 AGV-', num2str(id_blocker), ')']);
        
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
                disp(['[AHP调度] 对方 AGV-', num2str(id_blocker), ' 物理停滞(', blocker_status, ')。AGV-', num2str(id_self), ' 绕行。']);
                if ~isempty(AGVs(id_self).target_node) 
                    success = plan_path(id_self, AGVs(id_self).target_node, [1, 1]); 
                    if ~success
                        disp(['[警告] 绕行死胡同！AGV-', num2str(id_self), ' 原地休眠...']);
                        AGVs(id_self).move_timer = 5; 
                    end
                end
            else
                disp(['[AHP调度] AGV-', num2str(id_self), ' 鸣笛要求对方让路...']);
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
        % 【核心修复】：动态推导虚拟 Target ID，激活底层区域互锁机制！
        virtual_target_id = 0;
        
        if strcmp(AGVs(id).status, 'Going_Charge') || strcmp(AGVs(id).status, 'Charging')
            % 去充电时，传入专属充电 ID
            if AGVs(id).type == 1, virtual_target_id = 17; end % 托举车充电
            if AGVs(id).type == 2, virtual_target_id = 18; end % 叉车充电
        else
            % 正常执行任务或回车库时，借用同类的 ID 来触发互锁逻辑
            if AGVs(id).type == 1, virtual_target_id = 1; end  % 托举车借用 ID 1
            if AGVs(id).type == 2, virtual_target_id = 13; end % 叉车借用 ID 13
        end
        
        % 【关键动作】：废弃静态全局地图，每次寻路都生成带有针对性互锁的动态地图！
        tempMap = create_binary_grid_map(mapW, mapH, virtual_target_id);
        % ==========================================================
        
        area_h = area_size(1); area_w = area_size(2);
        
        % 1. 在互锁地图上，强行把目标靶区“挖空”，保证 AGV 能开进去
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
        [path, ~, ~, ~, ~, ~] = astar_planner_turn3(tempMap, curr_pos, actual_target, current_weight, [], AGVs(id).type);
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
        
        % 冲突检查逻辑不变
        if OccupancyGrid(nr, nc) ~= 0 && OccupancyGrid(nr, nc) ~= id
            status = -OccupancyGrid(nr, nc); 
            return; 
        end
        
        % 转弯统计逻辑不变
        curr_dir = [nr - AGVs(id).pos(1), nc - AGVs(id).pos(2)]; 
        if ~isequal(AGVs(id).last_dir, [0, 0]) && ~isequal(AGVs(id).last_dir, curr_dir)
            AGVs(id).total_turns = AGVs(id).total_turns + 1; 
        end
        AGVs(id).last_dir = curr_dir; 
        
        % --- 关键修改位置：更新坐标并记录轨迹 ---
        OccupancyGrid(AGVs(id).pos(1), AGVs(id).pos(2)) = 0; 
        AGVs(id).pos = next_node;                       % 更新位置
        OccupancyGrid(nr, nc) = id; 
        
        tid = AGVs(id).active_task_id;
        if tid > 0
            task_trajectories{tid} = [task_trajectories{tid}; AGVs(id).pos];
        end
        % ---------------------------------------
        if ~isempty(AGVs(id).tasks)
            for i = 1:length(AGVs(id).tasks)
                q_tid = AGVs(id).tasks(i);
                % 满足条件：不是主动任务，且 task_times(q_tid, 1) > 0 (表示已完成 Loading)
                if q_tid ~= tid && task_times(q_tid, 1) > 0
                    task_trajectories{q_tid} = [task_trajectories{q_tid}; AGVs(id).pos];
                end
            end
        end
        AGVs(id).total_dist = AGVs(id).total_dist + 1;
        AGVs(id).path_idx = AGVs(id).path_idx + 1;      
        AGVs(id).move_timer = AGVs(id).step_dur;         
        
        % 动态获取该车型的最大载重（与 GA 保持绝对一致）
        if AGVs(id).type == 1
            cap = 80.0;  % 托举车最大载重
        elseif AGVs(id).type == 2
            cap = 500.0; % 叉车最大载重
        else
            cap = 100.0; % 兜底默认值
        end
        
        cost = (e_b + e_l * (AGVs(id).payload_weight / cap)); 
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
            
            % 1. 【核心：仅记录起点】记录开始时间和里程，不进行结算
            if task_times(tid, 1) == 0, task_times(tid, 1) = t; end
            task_start_dist(tid) = AGVs(id).total_dist;
            task_executor(tid) = id;
            
            % 2. 装载货物
            AGVs(id).payload_weight = AGVs(id).payload_weight + task_weight; 
            AGVs(id).load = 1;                     
            
            fprintf('📦 [AGV-%02d] 成功装载订单 #%d | 重量: %d | 车上总重: %d\n', ...
                id, tid, task_weight, AGVs(id).payload_weight);
                
            % 3. 队列流转逻辑
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
                % 取完货了，出发去送货
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
            
            % ★【核心：结算终点指标】只有在卸货完成时才记录结束时间和总路程
            task_times(tid, 2) = t; 
            time_spent_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
            task_dist_record(tid) = AGVs(id).total_dist - task_start_dist(tid);
            
            fprintf('✅ [AGV-%02d] 任务完成！订单 #%d | 耗时: %.1f秒 | 运送里程: %d格\n', ...
                    id, tid, time_spent_sec, task_dist_record(tid));
            
            % 扣除载重并从该车任务链中移除
            AGVs(id).payload_weight = max(0, AGVs(id).payload_weight - task_weight); 
            AGVs(id).tasks(AGVs(id).tasks == tid) = [];                
                
            if ~isempty(AGVs(id).drop_queue)
                % 继续送下一件
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
                % 全部送完，回归空闲
                fprintf('   -> 🎉 AGV-%02d 批次配送全部收官。\n', id);
                AGVs(id).status = 'Idle';                   
                AGVs(id).load = 0;                           
                AGVs(id).active_task_id = 0;
            end
        end
    end  
end