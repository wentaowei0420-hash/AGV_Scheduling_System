function run_visualization_loop_time(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
    
    global mapW mapH; 
    
    % --- 1. 初始化图形界面 ---
    generate_beautiful_factory_map();   
    % 【新增】：声明全局代价地图并执行一次预计算
    global costmap_type1 costmap_type2;
    init_global_costmaps();
    f_map = gcf;                        
    ax = findobj(f_map, 'Type', 'Axes'); 
    hold(ax, 'on');                      
    set(f_map, 'Name', '实时动态调度仿真', 'NumberTitle', 'off', 'MenuBar', 'none', 'ToolBar', 'none', 'Position', [50, 200, 1000, 700]);
    [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs);
    
    % --- 2. 初始化 AGV 对象 ---
    [AGVs, props, ~] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax);
    
    % --- 3. 实时仿真主循环 ---
    disp('>> [系统] 实时仿真启动...'); 

    for k = 1:num_agvs
        AGVs(k).total_turns = 0;           % 运行转弯总数
        AGVs(k).last_dir = [0, 0];         % 上一步方向矢量
        
        AGVs(k).pick_queue = [];           % 取货任务队列
        AGVs(k).drop_queue = [];           % 卸货任务队列
        AGVs(k).active_task_id = 0;        % 当前正在导航的具体子任务ID
        AGVs(k).interrupted_status = '';   % 记忆因没电去充电前被中断的状态
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
    % 主仿真循环：当仿真运行标志为真且当前步数未超过最大步数时循环
    while sim_running && t < MAX_STEPS   
        t = t + 1;                       % 时间步递增（离散时间单位）
        all_finished = true;              % 假设所有AGV都已完成任务，后续如果任一AGV未完成则置false
    
        % --- A. 逻辑更新：遍历每个AGV，根据其状态执行相应动作 ---
        for k = 1:num_agvs   
            % 如果AGV正在移动中（move_timer > 0），则减少计时器，跳过该AGV的详细逻辑
            if AGVs(k).move_timer > 0      
                AGVs(k).move_timer = AGVs(k).move_timer - 1; 
                all_finished = false;      % 仍有AGV在移动，未全部完成
                continue;                   % 跳过该AGV后续处理，直接处理下一个AGV
            end
    
            % 动态设置专属车位/充电桩的尺寸，用于区域检测（如是否停在充电站内）
            if AGVs(k).type == 2
                agv_area_sz = [3, 3];      % 叉车（类型2）尺寸较大
            else
                agv_area_sz = [1, 1];      % 托举式（类型1）尺寸较小
            end
    
            % 根据AGV当前状态进行多分支处理（状态机）
            switch AGVs(k).status
                case 'Idle'   % 空闲状态
                    % 电量低于20%，需要充电
                    if AGVs(k).battery < 20   
                        plan_to_charge(k, t);     % 调用规划充电函数
                        all_finished = false;
                        
                    % 如果存在未完成的活跃任务（可能是之前中断的），则尝试继续
                    elseif AGVs(k).active_task_id > 0
                        tid = AGVs(k).active_task_id;
                        row_idx = get_task_row(tid);   % 获取任务在task_list中的行索引
                        if row_idx == 0                 % 任务不存在（可能已被移除），清空活跃任务
                            AGVs(k).active_task_id = 0;
                            all_finished = false;
                            continue;
                        end
                        target_id = task_list(row_idx, 2);  % 获取目标站点ID
    
                        % 根据中断时记录的状态，恢复对应的移动类型
                        if strcmp(AGVs(k).interrupted_status, 'Moving_Drop')
                            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id); % 获取送货点区域
                            if plan_path(k, drop_anchor, drop_size, t)    % 规划到送货点的路径
                                AGVs(k).status = 'Moving_Drop';           % 切换状态为送货移动
                                AGVs(k).interrupted_status = '';          % 清除中断记录
                            end
                        elseif strcmp(AGVs(k).interrupted_status, 'Moving_Pick')
                            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); % 获取取货点区域
                            if plan_path(k, pick_anchor, pick_size, t)
                                AGVs(k).status = 'Moving_Pick';
                                AGVs(k).interrupted_status = '';
                            end     
                        else
                            AGVs(k).active_task_id = 0;    % 无有效中断状态，清除活跃任务
                        end
                        all_finished = false;
                        
                    % 有空闲且有未开始的任务，准备取货（分批处理）
                    elseif ~isempty(AGVs(k).tasks)  
                        max_load_capacity = 80;            % 最大载重（硬编码，可从参数传入）
                        batch_tasks = [];                   % 当前批次的取货任务ID列表
                        current_batch_weight = 0;            % 当前批次累计重量
    
                        % 遍历该AGV剩余任务，按顺序放入批次，直到容量满或类型限制
                        for i = 1:length(AGVs(k).tasks)
                            tid = AGVs(k).tasks(i);
                            row_idx = get_task_row(tid);
                            if row_idx == 0                  % 任务不存在（可能已被删除），跳过
                                continue;
                            end
                            w = task_list(row_idx, 3);       % 任务重量
    
                            % 叉车（type 2）只能一次携带一个任务（可能由于物理限制）
                            if AGVs(k).type == 2 && i > 1
                                break; 
                            end
    
                            % 如果是第一个任务，或者当前批次重量加上该任务不超过容量，则加入批次
                            if i == 1 || (current_batch_weight + w <= max_load_capacity)
                                batch_tasks = [batch_tasks, tid];
                                current_batch_weight = current_batch_weight + w;
                            else
                                break;   % 超过容量，停止继续添加（剩余任务留在tasks中下次处理）
                            end
                        end
    
                        AGVs(k).pick_queue = batch_tasks;    % 设置取货队列
                        AGVs(k).drop_queue = batch_tasks;    % 卸货队列（与取货队列相同）
    
                        % 开始第一个取货任务
                        first_tid = AGVs(k).pick_queue(1);
                        AGVs(k).pick_queue(1) = [];           % 从取货队列中移除第一个
                        AGVs(k).active_task_id = first_tid;   % 设置活跃任务ID
    
                        row_idx = get_task_row(first_tid);
                        if row_idx == 0                        % 任务无效，回退
                            AGVs(k).pick_queue = [];
                            AGVs(k).drop_queue = [];
                            AGVs(k).active_task_id = 0;
                            all_finished = false;
                            continue;
                        end
                        target_id = task_list(row_idx, 2);
                        [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); % 获取取货点区域
    
                        if plan_path(k, pick_anchor, pick_size, t)   % 规划到取货点的路径
                            AGVs(k).status = 'Moving_Pick';           % 切换为取货移动状态
                        else
                            % 路径规划失败，回退队列，稍后重试（本步不做处理，下次循环可能重新尝试）
                            AGVs(k).pick_queue = [];
                            AGVs(k).drop_queue = [];
                            AGVs(k).active_task_id = 0;
                        end
                        all_finished = false;
                        
                    else   % 没有任务且空闲，考虑回家或充电
                        home_pos = AGVs(k).home_pos;                   % 获取AGV的家位置（depot）
                        if AGVs(k).battery < 95                        % 电量不满95%，考虑充电
                            % 获取该类型AGV的充电站列表
                            if isfield(props(AGVs(k).type), 'charge_stations') && ~isempty(props(AGVs(k).type).charge_stations)
                                candidate_stations = props(AGVs(k).type).charge_stations;
                            else
                                candidate_stations = props(AGVs(k).type).charge; % 兜底字段
                            end
    
                            % 检查当前是否已经在充电站区域内
                            is_at_charger = false;
                            for s = 1:size(candidate_stations, 1)
                                if check_in_area(AGVs(k).pos, candidate_stations(s, :), agv_area_sz)      
                                    is_at_charger = true;
                                    break; 
                                end
                            end
    
                            if is_at_charger      
                                AGVs(k).status = 'Charging';           % 已在充电站，开始充电
                                AGVs(k).wait_timer = 5;                % 设置充电等待时间（步数）
                            else
                                plan_to_charge(k, t);                  % 不在充电站，规划去充电
                            end
                            all_finished = false;
    
                        elseif ~check_in_area(AGVs(k).pos, home_pos, agv_area_sz)        
                            % 电量充足但不在家，规划回家
                            if plan_path(k, home_pos, agv_area_sz, t)
                                AGVs(k).status = 'Go_Home';            % 转为回家状态
                            end
                            all_finished = false;
                        end
                        % 如果在家且电量充足，则保持空闲，不做任何事（all_finished已为true，但下面会保持）
                    end
    
                % 移动相关状态：取货中、送货中、回家中、去充电中、让行中
                case {'Moving_Pick', 'Moving_Drop', 'Go_Home', 'Going_Charge', 'Yielding'}  
                    all_finished = false;      % 有AGV在移动，肯定未完成
    
                    % 电量检查：如果电量低于20%且当前状态不是去充电或充电中，则中断当前任务去充电
                    if AGVs(k).battery < 20 && ~strcmp(AGVs(k).status, 'Going_Charge') && ~strcmp(AGVs(k).status, 'Charging')
                        disp(['AGV-', num2str(k), ' 电量耗尽，保留队列现场，前往充电！']);
                        AGVs(k).interrupted_status = AGVs(k).status;   % 记录被中断的状态
                        plan_to_charge(k, t);                           % 规划去充电
                        continue;                                       % 跳过该AGV本步的移动执行
                    end
    
                    move_status = execute_move(k);                      % 执行移动一步
                    if move_status == 1                                  % 返回值1表示到达目标点
                        handle_arrival(k, task_list);                   % 处理到达事件（如装载、卸货等）
                    elseif move_status < 0                               % 负数表示移动被阻塞，返回阻塞者的ID
                        blocker_id = -move_status;                      % 获取阻塞AGV编号
                        resolve_conflict(k, blocker_id, task_list, t);  % 解决冲突
                    end
    
                % 等待状态：装载、卸货、充电
                case {'Loading', 'Unloading', 'Charging'}  
                    all_finished = false;
                    AGVs(k).wait_timer = AGVs(k).wait_timer - 1;        % 等待计时器递减
    
                    if strcmp(AGVs(k).status, 'Charging')               % 充电状态
                        AGVs(k).battery = min(100, AGVs(k).battery + 2.0); % 每步增加电量（上限100）
                        if AGVs(k).battery >= 100 && AGVs(k).wait_timer <= 0  % 充满且等待结束
                            AGVs(k).status = 'Idle';                     % 转为空闲
                        end
                    end
    
                    % 非充电状态且等待结束，且不是回家状态，则完成等待并执行后续动作
                    if AGVs(k).wait_timer <= 0 && ~strcmp(AGVs(k).status, 'Charging') && ~strcmp(AGVs(k).status, 'Go_Home')
                        finish_waiting(k, task_list);                   % 完成等待（如装载后取下一个货或开始送货）
                    end
            end
        end

        % 如果所有AGV都已完成任务（all_finished为true），则提前退出主循环
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
            pause(0.02);                                  
        end
    end
    export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories);
    disp('>> 仿真结束。');                              
    
    disp('========================================');
    disp('         AGV 运行总转弯次数统计       ');
    disp('========================================');
    for k = 1:num_agvs
        agv_type_str = '未知';
        if AGVs(k).type == 1, agv_type_str = '托举式'; end
        if AGVs(k).type == 2, agv_type_str = '叉车式'; end
        fprintf('  AGV-%02d (%s)  |  共转弯: %d 次\n', k, agv_type_str, AGVs(k).total_turns);
    end
    disp('========================================');
    
    function resolve_conflict(id_self, id_blocker, tasks_info, current_t)
        % 函数功能：解决两个AGV之间的路径冲突
        % 输入参数：
        %   id_self     - 当前检测到冲突的AGV编号
        %   id_blocker  - 阻塞当前AGV的另一个AGV编号
        %   tasks_info  - 任务列表矩阵，用于优先级计算
        %   current_t   - 当前仿真时间步
    
        % 获取当前AGV（id_self）的当前位置
        pos_self = AGVs(id_self).pos;
        % 获取当前AGV计划的下一个目标点（从路径中取出，前两列是坐标）
        target_self = AGVs(id_self).path(AGVs(id_self).path_idx, 1:2);
        % 计算当前AGV的运动方向矢量（目标点减当前位置）
        dir_self = target_self - pos_self;
    
        % 获取阻塞AGV（id_blocker）的当前位置
        pos_blocker = AGVs(id_blocker).pos;
    
        % 定义“正在移动”的状态列表（这些状态下的AGV有动态路径）
        moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home'};
        % 判断阻塞AGV是否处于移动状态之一
        is_blocker_in_moving_state = ismember(AGVs(id_blocker).status, moving_states);
        % 判断阻塞AGV是否有有效路径且尚未走完
        has_path = ~isempty(AGVs(id_blocker).path) && AGVs(id_blocker).path_idx <= size(AGVs(id_blocker).path, 1);
    
        if is_blocker_in_moving_state && has_path
            % 如果阻塞AGV正在移动且有路径，则获取它的下一个目标点
            true_target_blocker = AGVs(id_blocker).path(AGVs(id_blocker).path_idx, 1:2);
            % 计算阻塞AGV的运动方向
            dir_blocker = true_target_blocker - pos_blocker;
    
            % 根据阻塞AGV的移动计时器计算其“速度”（每步移动所需时间的倒数）
            if AGVs(id_blocker).move_timer > 0
                v_blocker = 0.001;   % 如果还在等待中，视为极慢（几乎静止）
            else
                v_blocker = 1.0 / AGVs(id_blocker).step_dur;   % 速度 = 1格 / step_dur 时间步
            end
            target_blocker = true_target_blocker;   % 阻塞AGV的目标点
        else
            % 如果阻塞AGV不在移动状态或无路径，则将其当前位置视为目标点
            true_target_blocker = pos_blocker;
            target_blocker = pos_blocker;
            dir_blocker = [0, 0];   % 方向为零矢量
            v_blocker = 0;           % 速度为零
        end
    
        % 计算两个AGV运动方向的点积（用于判断是相向、同向还是垂直）
        dot_product = dir_self(1)*dir_blocker(1) + dir_self(2)*dir_blocker(2);
    
        % 计算当前AGV的“速度”
        if AGVs(id_self).move_timer > 0
            v_self = 0.001;   % 等待中视为慢
        else
            v_self = 1.0 / AGVs(id_self).step_dur;
        end
    
        % 初始化冲突类型和名称
        c_type = 0;
        conflict_name = '未知冲突';
    
        % 定义特殊状态标志
        % 交换位置：我的目标点是阻塞者的当前位置，且阻塞者的目标点是我的当前位置
        is_swapping = isequal(target_self, pos_blocker) && isequal(true_target_blocker, pos_self);
        % 目标点相同：我的目标点和阻塞者的目标点相同
        is_same_target = isequal(target_self, target_blocker);
    
        % 开始冲突类型判断（多条件分支）
        if is_swapping
            c_type = 1; conflict_name = '相向冲突(交换)';
    
        elseif isequal(target_self, pos_blocker)
            % 我的目标点是阻塞者的当前位置
            if v_blocker == 0
                c_type = 3; conflict_name = '占位冲突';   % 阻塞者静止不动，占着我要去的位置
            elseif dot_product > 0 && v_self > v_blocker
                c_type = 4; conflict_name = '追赶冲突';   % 同向且我更快，可能追尾
            else
                c_type = 1; conflict_name = '相向冲突(交换)';   % 其他情况归为相向交换
            end
    
        elseif is_same_target
            % 目标点相同
            if dot_product < 0
                c_type = 1; conflict_name = '相向冲突(相遇)';   % 相向而行，会在目标点相遇
            else
                c_type = 2; conflict_name = '节点冲突';         % 同向或垂直，同时竞争同一个节点
            end
        end
    
        % 输出冲突双方的当前坐标和目标坐标（用于调试）
        fprintf('   [坐标] AGV-%d: 当前(%d,%d) 目标(%d,%d) | AGV-%d: 当前(%d,%d) 目标(%d,%d)\n', ...
            id_self, pos_self(1), pos_self(2), target_self(1), target_self(2), ...
            id_blocker, pos_blocker(1), pos_blocker(2), true_target_blocker(1), true_target_blocker(2));
    
        % 生成冲突的唯一键，避免同一时间步重复处理相同冲突对
        conflict_pair = sort([id_self, id_blocker]);
        conflict_key = sprintf('%d_%d_%d', current_t, conflict_pair(1), conflict_pair(2));
        should_handle_conflict = ~isKey(reported_conflict_keys, conflict_key);
        if ~should_handle_conflict
            return;   % 如果已处理过，直接返回
        end
        reported_conflict_keys(conflict_key) = true;   % 标记已处理
    
        % 在控制台显示冲突信息
        disp(['[Conflict] T=', num2str(current_t), ' ', conflict_name, ' (AGV-', num2str(id_self), ' -> AGV-', num2str(id_blocker), ')']);
    
        % 尝试发送冲突事件到外部 webhook（用于监控或记录）
        if ~send_conflict_webhook(current_t, id_self, pos_self, id_blocker, pos_blocker, conflict_name)
            fprintf('[Webhook] Conflict event send failed and was written to local log: T=%d, AGV-%d vs AGV-%d\n', current_t, id_self, id_blocker);
        end
    
        % 计算两个AGV的优先级（基于AHP多准则决策）
        P_self = calculate_ahp_priority(AGVs(id_self), tasks_info, current_t);
        P_blocker = calculate_ahp_priority(AGVs(id_blocker), tasks_info, current_t);
    
        % 决定哪一方应该让行：优先级低的让行，如果相等则ID大的让行（避免死锁）
        should_self_yield = (P_self < P_blocker) || (P_self == P_blocker && id_self > id_blocker);
        if should_self_yield
            loser_id = id_self;      % 需要让行的AGV
            winner_id = id_blocker;  % 可以优先通行的AGV
        else
            loser_id = id_blocker;
            winner_id = id_self;
        end
    
        % 输出优先级比较结果和让行方
        fprintf('冲突消解: AGV-%d 优先级 = %.2f, AGV-%d 优先级 = %.2f | loser = AGV-%d, winner = AGV-%d\n', ...
            id_self, P_self, id_blocker, P_blocker, loser_id, winner_id);
    
        % 根据冲突类型采取不同的让行策略
        if c_type == 1
            % 相向冲突：让低优先级的AGV退让到临时让行点
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' retreats to a temporary yield node.']);
            success = plan_yield_path(loser_id, winner_id, current_t);   % 规划让行路径
            if ~success && ~isempty(AGVs(loser_id).target_node)
                % 如果让行失败，尝试重新规划到原目标点（可能绕路）
                success = plan_path(loser_id, AGVs(loser_id).target_node, [1, 1], current_t);
            end
            if ~success
                % 如果仍然失败，则让低优先级AGV等待一段时间
                AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
            end
    
        elseif c_type == 2
            % 节点冲突：低优先级AGV原地等待
            disp(['  -> Yield strategy: lower-priority AGV-', num2str(loser_id), ' waits before retrying.']);
            AGVs(loser_id).move_timer = max(AGVs(loser_id).step_dur, 3);
    
        elseif c_type == 3
            % 占位冲突：尝试绕行
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
            % 追赶冲突：重新规划或减速
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
        % 函数功能：为指定的AGV规划前往充电站的路径，并切换到充电状态
        % 输入参数：
        %   id        - AGV的索引编号
        %   current_t - 当前仿真时间步（用于路径时间戳）
        
        % 获取该类型AGV的充电站列表
        % 首先尝试从props结构体中读取 'charge_stations' 字段（可能包含多个充电站）
        if isfield(props(AGVs(id).type), 'charge_stations') && ~isempty(props(AGVs(id).type).charge_stations)
            candidate_stations = props(AGVs(id).type).charge_stations;   % 使用专用的充电站列表
        else
            candidate_stations = props(AGVs(id).type).charge;            % 否则使用后备字段 'charge'
        end
    
        % 根据AGV类型确定充电区域的尺寸（用于路径规划的目标区域）
        if AGVs(id).type == 2
            charge_area_sz = [3, 3];   % 叉车（类型2）体积大，充电区域也大
        else
            charge_area_sz = [1, 1];   % 托举式（类型1）体积小，充电区域为一个网格
        end
    
        best_cost = inf;               % 初始化最佳路径代价为无穷大
        best_station = [];             % 记录最优充电站的锚点位置
        best_station_target = [];      % 记录最优充电站区域内实际目标点（网格坐标）
        best_station_path = [];        % 记录最优路径点序列
    
        % 遍历所有候选充电站，选择代价最小的可用充电站
        for s = 1:size(candidate_stations, 1)
            station_pos = candidate_stations(s, :);   % 充电站的锚点坐标（通常是区域的左上角）
            
            % 检查该充电站是否被其他AGV占用
            is_occupied = false;
            for other = 1:num_agvs
                if other == id, continue; end   % 跳过自身
                % 如果其他AGV的位置或目标节点正好位于该充电站的锚点位置
                if isequal(AGVs(other).pos, station_pos) || isequal(AGVs(other).target_node, station_pos)
                    % 并且该AGV处于充电中或正在去充电的状态，才认为被占用
                    if ismember(AGVs(other).status, {'Charging', 'Going_Charge'})
                        is_occupied = true;
                        break;
                    end
                end
            end
    
            if ~is_occupied
                % 如果充电站空闲，则调用路径规划函数寻找从当前位置到该充电站区域的最佳路径
                % 参数说明：
                %   id              - AGV编号
                %   station_pos     - 充电站锚点
                %   charge_area_sz  - 充电区域尺寸
                %   'charge'        - 附加标识，可能用于指定目标类型（如充电站），影响代价地图或障碍处理
                [candidate_path, candidate_target, candidate_cost] = find_best_target_path(id, station_pos, charge_area_sz, 'charge');
                
                % 如果找到可行路径且代价小于当前最优，则更新最优记录
                if ~isempty(candidate_path) && candidate_cost < best_cost
                    best_cost = candidate_cost;
                    best_station = station_pos;
                    best_station_target = candidate_target;
                    best_station_path = candidate_path;
                end
            end
        end
    
        % 如果找到了可用的充电站
        if ~isempty(best_station)
            % 将规划好的路径分配给该AGV（添加时间戳）
            assign_planned_path(id, best_station_path, best_station_target, current_t);
            % 将AGV状态设置为“去充电”
            AGVs(id).status = 'Going_Charge';
            % 控制台输出分配信息
            disp(['[Charge Dispatch] AGV-', num2str(id), ' assigned to charger (', num2str(best_station(1)), ',', num2str(best_station(2)), ')']);
        else
            % 如果没有找到任何可用充电站（可能所有充电站都被占用或不可达）
            disp(['[Charge Warning] AGV-', num2str(id), ' found no reachable idle charger and will wait.']);
            % 设置一个移动计时器，让AGV等待一段时间后再尝试
            AGVs(id).move_timer = 5;
        end
    end
    
    function [best_path, best_target, best_cost] = find_best_target_path(id, target_anchor, area_size, planning_mode)
        % 函数功能：为指定的AGV寻找从当前位置到目标锚点区域内最佳目标点的路径
        % 输入参数：
        %   id            - AGV的索引编号
        %   target_anchor - 目标区域的锚点坐标（通常是左上角网格坐标），[行, 列]
        %   area_size     - 目标区域的尺寸 [高度, 宽度]（以网格为单位）
        %   planning_mode - 规划模式，'task' 或 'charge'，影响虚拟目标ID的选择（用于构建临时障碍地图）
        % 输出参数：
        %   best_path   - 最优路径点序列，每一行 [行, 列]
        %   best_target - 最优目标点（区域内的具体网格坐标）
        %   best_cost   - 最优路径的代价值（越小越好）
    
        % 设置默认参数：如果 area_size 未提供或为空，则默认为 [2,2]
        if nargin < 3 || isempty(area_size), area_size = [2, 2]; end
        % 设置默认参数：如果 planning_mode 未提供或为空，则默认为 'task'
        if nargin < 4 || isempty(planning_mode), planning_mode = 'task'; end
    
        % 根据规划模式确定虚拟目标ID（用于构建二值网格地图时排除某些区域）
        virtual_target_id = 0;
        if strcmp(planning_mode, 'charge')
            % 充电模式：托举车使用ID 17，叉车使用ID 18
            if AGVs(id).type == 1, virtual_target_id = 17; end
            if AGVs(id).type == 2, virtual_target_id = 18; end
        else
            % 任务模式：托举车使用ID 1，叉车使用ID 13
            if AGVs(id).type == 1, virtual_target_id = 1; end
            if AGVs(id).type == 2, virtual_target_id = 13; end
        end
    
        % 创建二值网格地图（1为障碍，0为可行），并传入虚拟目标ID以排除特定区域
        tempMap = create_binary_grid_map(mapW, mapH, virtual_target_id);
        area_h = area_size(1);   % 区域高度
        area_w = area_size(2);   % 区域宽度
    
        % 将目标锚点周围的区域在临时地图中设为可行（清除障碍）
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr;  % 当前网格行坐标
                c = target_anchor(2) + dc;  % 当前网格列坐标
                % 确保坐标在地图范围内
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    tempMap(r, c) = 0;       % 设为可行
                end
            end
        end
    
        % 收集区域内所有未被其他AGV占据或作为目标点的网格作为候选目标点
        valid_targets = [];
        for dr = 0 : (area_h - 1)
            for dc = 0 : (area_w - 1)
                r = target_anchor(1) + dr;
                c = target_anchor(2) + dc;
                if r >= 1 && r <= mapH && c >= 1 && c <= mapW
                    occupied = false;   % 初始化占用标志
                    % 遍历所有其他AGV，检查该网格是否被占用
                    for other = 1:num_agvs
                        if other == id, continue; end   % 跳过自身
                        % 检查其他AGV的当前位置是否等于该网格
                        is_pos_occupied = (AGVs(other).pos(1) == r && AGVs(other).pos(2) == c);
                        % 检查其他AGV的目标节点是否等于该网格
                        is_target_occupied = ~isempty(AGVs(other).target_node) && ...
                                             (AGVs(other).target_node(1) == r && AGVs(other).target_node(2) == c);
                        if is_pos_occupied || is_target_occupied
                            occupied = true;
                            break;   % 一旦发现占用，提前退出内层循环
                        end
                    end
                    if ~occupied
                        % 如果未被占用，则将该网格加入候选列表
                        valid_targets = [valid_targets; r, c]; %#ok<AGROW>
                    end
                end
            end
        end
    
        % 初始化最优结果
        best_path = [];
        best_target = [];
        best_cost = inf;   % 初始代价设为无穷大
    
        % 如果没有候选目标点，直接返回空结果
        if isempty(valid_targets)
            return;
        end
    
        % 获取AGV当前载重（用于代价地图中的负载代价计算）
        current_weight = 0;
        if isfield(AGVs(id), 'payload_weight') && AGVs(id).load == 1
            current_weight = AGVs(id).payload_weight;
        end
    
        % 根据AGV类型选择对应的代价地图（不同类型对不同区域的通行代价不同）
        if AGVs(id).type == 2
            current_costmap = costmap_type2;
        else
            current_costmap = costmap_type1;
        end
    
        curr_pos = AGVs(id).pos;   % AGV当前位置
    
        % 遍历所有候选目标点，使用A*算法规划路径，选择代价最小的
        for idx = 1:size(valid_targets, 1)
            candidate_target = valid_targets(idx, :);   % 当前候选目标点
            evalMap = tempMap;                           % 复制临时地图用于评估
            evalMap(curr_pos(1), curr_pos(2)) = 0;       % 确保起点可行（可能之前被标记为障碍？但一般起点是可行）
    
            % 将其他AGV的当前位置设为障碍（除非该位置恰好是当前候选目标点，这样目标点本身仍然可行）
            for other = 1:num_agvs
                if other ~= id
                    pos_r = AGVs(other).pos(1);
                    pos_c = AGVs(other).pos(2);
                    % 只有当其他AGV的位置不等于候选目标点时，才将其设为障碍
                    if ~(pos_r == candidate_target(1) && pos_c == candidate_target(2))
                        evalMap(pos_r, pos_c) = 1;   % 设为障碍
                    end
                end
            end
    
            % 调用A*路径规划器（考虑转弯代价和负载代价）
            [candidate_path, candidate_cost, ~, ~, ~, ~] = astar_planner_turn3(evalMap, curr_pos, candidate_target, current_weight, current_costmap);
            % 如果找到可行路径且代价小于当前最优，则更新最优记录
            if ~isempty(candidate_path) && candidate_cost < best_cost
                best_cost = candidate_cost;
                best_target = candidate_target;
                best_path = candidate_path;
            end
        end
    end
    
    function assign_planned_path(id, path, actual_target, current_t)
        % 函数功能：将规划好的路径分配给指定的AGV，并添加时间戳
        % 输入参数：
        %   id            - AGV的索引编号
        %   path          - 路径点矩阵，每一行是一个网格坐标 [行, 列]，按从起点到终点的顺序排列
        %   actual_target - 实际的目标点（区域内的具体网格坐标），用于记录AGV当前前往的目标节点
        %   current_t     - 当前仿真时间步，用于计算每个路径点的时间戳
    
        path_length = size(path, 1);          % 获取路径点的总数（路径长度）
        time_stamps = zeros(path_length, 1);  % 初始化时间戳数组，与路径点一一对应
        step_time = AGVs(id).step_dur;        % 获取该AGV移动一格所需的仿真时间步数（速度参数）
    
        % 为每个路径点计算预计到达的时间步
        for p_idx = 1:path_length
            % 当前路径点的预计到达时间 = 当前时间 + (索引-1) * step_time
            % 起点（索引1）的时间戳为 current_t，意味着AGV将在当前时间步开始移动？
            % 注意：起点通常是AGV当前位置，所以到达起点的时间为 current_t（已经在该点）
            time_stamps(p_idx) = current_t + (p_idx - 1) * step_time;
        end
    
        % 将路径点与时间戳合并，存储到AGV的path字段
        % 新矩阵每一行为 [行, 列, 时间戳]
        AGVs(id).path = [path, time_stamps];
    
        % 设置路径索引为2，表示下一个要移动到的点是路径中的第二个点
        % 因为第一个点是当前所在位置，不需要移动
        AGVs(id).path_idx = 2;
    
        % 记录AGV当前的目标节点（区域内的具体网格坐标）
        % 这个目标节点用于冲突检测和导航
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
        % 函数功能：为指定AGV规划一条到目标锚点区域内某可达点的路径，并分配路径
        % 输入参数：
        %   id            - AGV的索引编号
        %   target_anchor - 目标区域的锚点坐标（通常是左上角网格坐标），[行, 列]
        %   area_size     - 目标区域的尺寸 [高度, 宽度]（以网格为单位）
        %   current_t     - 当前仿真时间步
        %   planning_mode - 规划模式，'task' 或 'charge'，影响路径规划中的代价地图和虚拟目标ID
        % 输出参数：
        %   success       - 布尔值，true 表示成功找到路径并分配，false 表示规划失败
    
        % 如果 area_size 未提供或为空，则使用默认值 [2, 2]
        if nargin < 3 || isempty(area_size), area_size = [2, 2]; end
    
        % 如果 planning_mode 未提供或为空，则使用默认值 'task'
        if nargin < 5 || isempty(planning_mode), planning_mode = 'task'; end
    
        % 调用 find_best_target_path 函数，寻找从AGV当前位置到目标锚点区域内最佳目标点的路径
        % 该函数返回：
        %   path          - 最优路径点序列（每一行 [行, 列]）
        %   actual_target - 区域内实际选中的具体目标点（网格坐标）
        %   ~             - 第三个返回值（代价）被忽略，因为此处只关心路径是否存在
        [path, actual_target, ~] = find_best_target_path(id, target_anchor, area_size, planning_mode);
    
        % 判断是否找到可行路径
        if ~isempty(path)
            % 如果路径非空，调用 assign_planned_path 函数将路径分配给AGV
            % 该函数会为路径添加时间戳，并设置 AGV 的 path、path_idx、target_node 等字段
            assign_planned_path(id, path, actual_target, current_t);
            success = true;   % 设置成功标志
        else
            success = false;  % 未找到路径，设置失败标志
        end
    end

    function success = plan_yield_path(id, blocker_id, current_t)
        % 函数功能：为需要让行的AGV规划一条退让路径，使其暂时离开冲突区域
        % 输入参数：
        %   id         - 需要让行的AGV编号
        %   blocker_id - 阻塞当前AGV的另一个AGV编号（用于确定退让方向）
        %   current_t  - 当前仿真时间步
        % 输出参数：
        %   success    - 布尔值，true表示成功规划让行路径，false表示失败
    
        success = false;                              % 初始化为失败
        curr_pos = AGVs(id).pos;                      % 获取当前AGV的位置
        blocker_pos = AGVs(blocker_id).pos;           % 获取阻塞AGV的位置
        % 计算当前AGV与阻塞AGV之间的曼哈顿距离（网格距离）
        current_gap = abs(curr_pos(1) - blocker_pos(1)) + abs(curr_pos(2) - blocker_pos(2));
        candidate_nodes = [];                          % 初始化候选让行点列表（每个点为 [行, 列]）
    
        % --- 从原路径中回溯两个点作为候选让行点 ---
        if ~isempty(AGVs(id).path)
            % 回溯的索引：当前路径索引的前两个和前三个位置
            backtrack_indices = [AGVs(id).path_idx - 2, AGVs(id).path_idx - 3];
            for idx = backtrack_indices
                % 确保索引在有效范围内（>=1 且 <=路径总点数）
                if idx >= 1 && idx <= size(AGVs(id).path, 1)
                    % 将路径点坐标（前两列）加入候选列表
                    candidate_nodes = [candidate_nodes; AGVs(id).path(idx, 1:2)]; %#ok<AGROW>
                end
            end
        end
    
        % --- 添加当前点的四个邻居网格作为候选让行点 ---
        directions = [-1, 0; 1, 0; 0, -1; 0, 1];   % 上、下、左、右四个方向
        for d = 1:size(directions, 1)
            candidate = curr_pos + directions(d, :);   % 计算邻居网格坐标
            % 检查是否在地图范围内
            if candidate(1) < 1 || candidate(1) > mapH || candidate(2) < 1 || candidate(2) > mapW
                continue;                               % 超出地图则跳过
            end
            candidate_nodes = [candidate_nodes; candidate]; %#ok<AGROW> 加入候选列表
        end
    
        % 如果没有收集到任何候选点，直接返回失败
        if isempty(candidate_nodes)
            return;
        end
    
        % 去除候选点中的重复坐标（保留第一次出现的顺序）
        [~, unique_idx] = unique(candidate_nodes, 'rows', 'stable');
        candidate_nodes = candidate_nodes(unique_idx, :);
    
        % 计算每个候选点与阻塞AGV的曼哈顿距离
        candidate_gaps = abs(candidate_nodes(:, 1) - blocker_pos(1)) + abs(candidate_nodes(:, 2) - blocker_pos(2));
        % 将距离作为第四列附加到候选点矩阵中
        candidate_nodes = [candidate_nodes, candidate_gaps];
        % 按距离降序排序（距离阻塞AGV越远的点越优先）
        candidate_nodes = sortrows(candidate_nodes, -3);   % -3 表示按第三列（距离）降序
    
        % 记录当前AGV的状态，以便让行结束后恢复
        original_status = AGVs(id).status;
    
        % 遍历排序后的候选点，尝试规划路径
        for c_idx = 1:size(candidate_nodes, 1)
            candidate = candidate_nodes(c_idx, 1:2);      % 当前候选点坐标
            % 跳过当前点自身和阻塞AGV的位置（无意义）
            if isequal(candidate, curr_pos) || isequal(candidate, blocker_pos)
                continue;
            end
            % 如果候选点与阻塞AGV的距离小于当前距离，则跳过（希望退让得更远，而不是更近）
            if candidate_nodes(c_idx, 3) < current_gap
                continue;
            end
            % 尝试规划从当前位置到候选点的路径（目标区域大小为1x1，即精确到达该点）
            if plan_path(id, candidate, [1, 1], current_t)
                % 规划成功：记录让行前状态，将AGV状态设为'Yielding'，并返回成功
                AGVs(id).yield_resume_status = original_status;
                AGVs(id).status = 'Yielding';
                success = true;
                return;
            end
        end
        % 如果所有候选点都无法规划路径，则返回失败
    end

    function status = execute_move(id)
        % 函数功能：执行AGV的一步移动，包括冲突检测、位置更新、状态记录等
        % 输入参数：
        %   id - AGV的索引编号
        % 输出参数：
        %   status - 移动结果状态：
        %       1  = 到达当前路径的终点（需要处理到达事件）
        %       0  = 正常移动一步，尚未到达终点
        %       -n = 移动被编号为 n 的AGV阻塞，需要处理冲突（n为正整数）
    
        % 检查AGV是否有有效路径，或者路径索引是否已超出范围
        if isempty(AGVs(id).path) || AGVs(id).path_idx > size(AGVs(id).path, 1)
            status = 1;      % 无路径或已到终点，返回到达状态
            return;          % 提前退出函数
        end
    
        curr_pos = AGVs(id).pos;                           % 当前AGV的位置（网格坐标）
        next_node_3d = AGVs(id).path(AGVs(id).path_idx, :); % 获取下一个路径点（包含坐标和时间戳）
        nr = next_node_3d(1); nc = next_node_3d(2);        % 下一个位置的行、列坐标
        target_t = next_node_3d(3);                        % 预计到达该点的时间步（用于时间冲突检测）
    
        % --- 冲突检测：检查下一个节点是否与其他AGV冲突 ---
        for other = 1:num_agvs
            if other == id, continue; end                  % 跳过自身
    
            other_curr = AGVs(other).pos;                  % 其他AGV的当前位置
    
            % 定义哪些状态属于“正在移动”的状态（这些AGV有动态路径）
            moving_states = {'Moving_Pick', 'Moving_Drop', 'Going_Charge', 'Go_Home', 'Yielding'};
    
            % 判断其他AGV是否正在移动中（有路径、未走完、移动计时器已归零、状态属于移动状态）
            is_other_moving = ~isempty(AGVs(other).path) && ...
                              AGVs(other).path_idx <= size(AGVs(other).path, 1) && ...
                              AGVs(other).move_timer <= 0 && ...
                              ismember(AGVs(other).status, moving_states);
    
            if is_other_moving
                % 如果正在移动，获取其下一个路径点（包含时间戳）
                other_next_3d = AGVs(other).path(AGVs(other).path_idx, :);
                other_next_r = other_next_3d(1);
                other_next_c = other_next_3d(2);
                other_next_t = other_next_3d(3);
            else
                % 如果未在移动（静止或等待），则将其当前位置视为其“下一个节点”
                other_next_r = other_curr(1);
                other_next_c = other_curr(2);
                other_next_t = target_t;   % 静止AGV的时间戳视为与当前AGV相同（或任意）
            end
    
            % 冲突条件1：下一个节点正好是其他AGV的下一个节点（同时申请同一节点）
            if nr == other_next_r && nc == other_next_c
                status = -other;   % 返回负的阻塞者ID
                return;
            end
    
            % 冲突条件2：相向交换位置
            % 我的下一个节点是其他AGV的当前位置，且其他AGV的下一个节点是我的当前位置
            if nr == other_curr(1) && nc == other_curr(2) && ...
               other_next_r == curr_pos(1) && other_next_c == curr_pos(2)
                status = -other;
                return;
            end
    
            % 冲突条件3：我的下一个节点被其他AGV占据，且我的预计到达时间不晚于对方离开的时间
            % 即对方还在该节点或尚未离开
            if nr == other_curr(1) && nc == other_curr(2) && target_t <= other_next_t
                status = -other;
                return;
            end
        end
        % --- 冲突检测结束，无冲突，可以移动 ---
    
        AGVs(id).pos = [nr, nc];                             % 更新AGV位置到下一个节点
    
        curr_dir = [nr - curr_pos(1), nc - curr_pos(2)];    % 计算当前移动方向矢量
    
        % 如果上一步有方向（不是初始状态）且当前方向与上一步方向不同，则转弯次数加1
        if ~isequal(AGVs(id).last_dir, [0, 0]) && ~isequal(AGVs(id).last_dir, curr_dir)
            AGVs(id).total_turns = AGVs(id).total_turns + 1;
        end
        AGVs(id).last_dir = curr_dir;                        % 更新上一步方向
    
        tid = AGVs(id).active_task_id;                       % 获取当前活跃任务ID（取货或送货任务）
        if tid > 0
            % 记录该任务的轨迹点（将当前位置追加到该任务的轨迹列表中）
            task_trajectories{tid} = [task_trajectories{tid}; AGVs(id).pos];
        end
        if ~isempty(AGVs(id).tasks)
            % 如果AGV有剩余任务列表，对于每个尚未完成但已开始记录的任务（开始时间>0），也记录其轨迹
            for i = 1:length(AGVs(id).tasks)
                q_tid = AGVs(id).tasks(i);
                if q_tid ~= tid && task_times(q_tid, 1) > 0   % 任务已开始但非当前活跃
                    task_trajectories{q_tid} = [task_trajectories{q_tid}; AGVs(id).pos];
                end
            end
        end
    
        AGVs(id).total_dist = AGVs(id).total_dist + 1;       % 累计行驶距离加1格
        AGVs(id).path_idx = AGVs(id).path_idx + 1;           % 路径索引指向下一个点
        AGVs(id).move_timer = AGVs(id).step_dur;              % 设置移动计时器（用于控制移动速度/动画）
    
        % 能耗计算与电池消耗
        e_b = agv_params(id).e_base;                          % 基础能耗系数
        e_l = agv_params(id).e_load_factor;                   % 负载能耗因子
        cost = (e_b + e_l * AGVs(id).payload_weight / 100.0); % 当前步的能耗（基于载重）
        AGVs(id).battery = max(0, AGVs(id).battery - cost);   % 扣除电量，不低于0
    
        % 判断是否已到达路径终点
        if AGVs(id).path_idx > size(AGVs(id).path, 1)
            AGVs(id).last_dir = [0, 0];   % 到达终点，清空方向（下次转弯不计）
            status = 1;                    % 返回到达状态
        else
            status = 0;                    % 尚未到达终点，返回正常移动状态
        end
    end
    
    function handle_arrival(id, ~)
        % 函数功能：处理AGV到达目标点后的事件，根据当前状态切换到相应的等待状态
        % 输入参数：
        %   id - AGV的索引编号
        %   ~  - 第二个参数被忽略（可能是为了统一接口，实际未使用）
    
        % 获取该AGV的当前状态
        st = AGVs(id).status;
    
        % 根据不同的移动状态进行分支处理
        if strcmp(st, 'Moving_Pick')
            % 如果当前状态是“去取货途中”，说明已经到达取货点
            AGVs(id).status = 'Loading';       % 切换状态为“装载中”
            AGVs(id).wait_timer = 6;            % 设置装载等待时间（6个时间步）
    
        elseif strcmp(st, 'Moving_Drop')
            % 如果当前状态是“去送货途中”，说明已经到达送货点
            AGVs(id).status = 'Unloading';      % 切换状态为“卸货中”
            AGVs(id).wait_timer = 6;            % 设置卸货等待时间（6个时间步）
    
        elseif strcmp(st, 'Going_Charge')
            % 如果当前状态是“去充电途中”，说明已经到达充电站
            AGVs(id).status = 'Charging';       % 切换状态为“充电中”
            AGVs(id).wait_timer = 30;           % 设置充电等待时间（30个时间步）
    
        elseif strcmp(st, 'Go_Home')
            % 如果当前状态是“回家途中”，说明已经回到Home位置
            AGVs(id).status = 'Idle';           % 切换状态为“空闲”（回家后无事可做）
    
        elseif strcmp(st, 'Yielding')
            % 如果当前状态是“让行中”，说明AGV到达了临时的让行点
            % 此时需要恢复之前被中断的任务状态
            resume_after_yield(id, t);           % 调用恢复函数，传入当前时间步t
        end
        % 注意：其他状态（如Loading, Unloading, Charging, Idle）不会进入此函数，
        % 因为该函数只在移动状态到达目标点时被调用（由execute_move返回1触发）。
    end

    function resume_after_yield(id, current_t)
        % 函数功能：让行结束后，恢复AGV到被中断前的状态，继续执行原任务
        % 输入参数：
        %   id        - AGV的索引编号
        %   current_t - 当前仿真时间步（用于路径规划的时间戳）
    
        % 获取该AGV在让行前记录的状态（由 resolve_conflict 中设置）
        resume_status = AGVs(id).yield_resume_status;
    
        % 如果没有记录任何中断状态（理论上不会发生，但做防御性处理）
        if isempty(resume_status)
            AGVs(id).status = 'Idle';        % 直接置为空闲状态
            return;                           % 提前返回
        end
    
        % 根据记录的中断状态进行分支恢复
        if strcmp(resume_status, 'Moving_Pick')
            % 之前是在去取货的路上被中断
            tid = AGVs(id).active_task_id;                     % 获取当时正在执行的取货任务ID
            row_idx = get_task_row(tid);                        % 在任务列表中查找该任务的行索引
            if row_idx == 0                                      % 如果任务不存在（可能已被删除）
                AGVs(id).status = 'Idle';                        % 置为空闲
                AGVs(id).yield_resume_status = '';               % 清空中断记录
                return;
            end
            target_id = task_list(row_idx, 2);                   % 获取目标站点ID
            [pick_anchor, ~, pick_size, ~] = get_task_coordinates(target_id); % 获取取货点区域信息
    
            % 重新规划到取货点的路径
            if plan_path(id, pick_anchor, pick_size, current_t)  % 路径规划成功
                AGVs(id).status = 'Moving_Pick';                 % 恢复为取货移动状态
                AGVs(id).yield_resume_status = '';                % 清空中断记录
            else
                % 路径规划失败（可能目标点被占或不可达），则继续保持在让行状态，稍后重试
                AGVs(id).status = 'Yielding';                     % 保持让行状态
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);  % 设置移动计时器（等待一段时间）
            end
    
        elseif strcmp(resume_status, 'Moving_Drop')
            % 之前是在去送货的路上被中断
            tid = AGVs(id).active_task_id;
            row_idx = get_task_row(tid);
            if row_idx == 0
                AGVs(id).status = 'Idle';
                AGVs(id).yield_resume_status = '';
                return;
            end
            target_id = task_list(row_idx, 2);
            [~, drop_anchor, ~, drop_size] = get_task_coordinates(target_id); % 获取送货点区域信息
    
            if plan_path(id, drop_anchor, drop_size, current_t)
                AGVs(id).status = 'Moving_Drop';
                AGVs(id).yield_resume_status = '';
            else
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
    
        elseif strcmp(resume_status, 'Go_Home')
            % 之前是在回家的路上被中断
            % 根据AGV类型确定家区域的尺寸
            if AGVs(id).type == 2
                agv_area_sz = [3, 3];      % 叉车所需区域较大
            else
                agv_area_sz = [1, 1];      % 托举车区域较小
            end
            % 规划回家路径
            if plan_path(id, AGVs(id).home_pos, agv_area_sz, current_t)
                AGVs(id).status = 'Go_Home';
                AGVs(id).yield_resume_status = '';
            else
                AGVs(id).status = 'Yielding';
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);
            end
    
        elseif strcmp(resume_status, 'Going_Charge')
            % 之前是在去充电的路上被中断
            AGVs(id).yield_resume_status = '';                    % 清空中断记录（避免循环）
            plan_to_charge(id, current_t);                         % 重新调用充电规划函数
            % 检查是否成功进入了 Going_Charge 状态（plan_to_charge 内部会设置状态）
            if ~strcmp(AGVs(id).status, 'Going_Charge')
                % 如果未能进入充电状态（例如所有充电站被占），则重新设置中断记录并继续让行等待
                AGVs(id).yield_resume_status = 'Going_Charge';     % 重新记录中断状态
                AGVs(id).status = 'Yielding';                       % 保持在让行状态
                AGVs(id).move_timer = max(AGVs(id).step_dur, 2);   % 等待后重试
            end
    
        else
            % 如果记录的中断状态不在上述范围内（理论上不应发生），则直接恢复到记录的状态
            AGVs(id).status = resume_status;
            AGVs(id).yield_resume_status = '';                     % 清空中断记录
        end
    end
    
    function finish_waiting(id, tasks_info)
        % 函数功能：当AGV完成等待（装载或卸货）后，更新状态并开始下一步动作
        % 输入参数：
        %   id          - AGV的索引编号
        %   tasks_info  - 任务列表矩阵，每行 [任务ID, 目标站点ID, 货物重量]
    
        st = AGVs(id).status;   % 获取AGV当前状态（Loading 或 Unloading）
    
        %% 处理装载完成（Loading 状态）
        if strcmp(st, 'Loading')
            tid = AGVs(id).active_task_id;                 % 获取当前装载的任务ID
            row_idx = get_task_row(tid);                    % 在任务列表中查找该任务的行索引
            if row_idx == 0                                  % 如果任务不存在（可能已被删除）
                AGVs(id).status = 'Idle';                    % 将AGV置为空闲
                AGVs(id).active_task_id = 0;                 % 清空活跃任务ID
                return;                                       % 直接返回
            end
            task_weight = tasks_info(row_idx, 3);            % 获取该任务的货物重量
    
            % 记录任务开始时间（如果尚未记录）
            if task_times(tid, 1) == 0, task_times(tid, 1) = t; end
            task_start_dist(tid) = AGVs(id).total_dist;      % 记录开始时的累计行驶距离
            task_executor(tid) = id;                          % 记录执行该任务的AGV编号
    
            AGVs(id).payload_weight = AGVs(id).payload_weight + task_weight; % 增加当前载重
            AGVs(id).load = 1;                                 % 标记为载货状态
    
            % 控制台输出装载信息
            fprintf('[AGV-%02d] 成功装载订单 #%d | 重量: %d | 车上总重: %d\n', ...
                id, tid, task_weight, AGVs(id).payload_weight);
    
            % --- 队列流转逻辑 ---
            if ~isempty(AGVs(id).pick_queue)
                % 如果取货队列中还有任务，则继续取下一个
                next_tid = AGVs(id).pick_queue(1);            % 获取下一个任务ID
                AGVs(id).pick_queue(1) = [];                   % 从队列中移除
                AGVs(id).active_task_id = next_tid;            % 设置为当前活跃任务
    
                next_row = get_task_row(next_tid);
                if next_row == 0                                % 如果下一个任务无效
                    AGVs(id).status = 'Idle';                    % 置为空闲
                    AGVs(id).active_task_id = 0;                 % 清空活跃任务
                    AGVs(id).pick_queue = [];                    % 清空取货队列
                    AGVs(id).drop_queue = [];                    % 清空卸货队列
                    return;
                end
                next_target_id = tasks_info(next_row, 2);      % 获取下一个任务的目标站点ID
                [pick_anchor, ~, pick_size, ~] = get_task_coordinates(next_target_id); % 获取取货点区域信息
    
                if plan_path(id, pick_anchor, pick_size, t)    % 规划到下一个取货点的路径
                    AGVs(id).status = 'Moving_Pick';            % 成功则转入取货移动状态
                else
                    AGVs(id).wait_timer = 2;                     % 失败则等待2步后重试
                    AGVs(id).pick_queue = [next_tid, AGVs(id).pick_queue]; % 将任务重新放回队列头部
                end
            else
                % 取货队列为空，说明该批次的所有货物都已装车，现在开始送货
                first_drop_tid = AGVs(id).drop_queue(1);       % 获取卸货队列的第一个任务
                AGVs(id).drop_queue(1) = [];                    % 从队列中移除
                AGVs(id).active_task_id = first_drop_tid;       % 设置为当前活跃任务
    
                drop_row = get_task_row(first_drop_tid);
                if drop_row == 0                                 % 如果任务无效
                    AGVs(id).status = 'Idle';                     % 置为空闲
                    AGVs(id).active_task_id = 0;                  % 清空活跃任务
                    AGVs(id).drop_queue = [];                     % 清空卸货队列
                    return;
                end
                drop_target_id = tasks_info(drop_row, 2);       % 获取送货目标站点ID
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(drop_target_id); % 获取送货点区域信息
    
                if plan_path(id, drop_anchor, drop_size, t)     % 规划到送货点的路径
                    AGVs(id).status = 'Moving_Drop';             % 成功则转入送货移动状态
                else
                    AGVs(id).wait_timer = 2;                      % 失败则等待后重试
                    AGVs(id).drop_queue = [first_drop_tid, AGVs(id).drop_queue]; % 任务放回队列
                end
            end
    
        %% 处理卸货完成（Unloading 状态）
        elseif strcmp(st, 'Unloading')
            tid = AGVs(id).active_task_id;                      % 获取当前卸货的任务ID
            row_idx = get_task_row(tid);                         % 查找任务行索引
            if row_idx == 0                                       % 任务不存在
                AGVs(id).status = 'Idle';
                AGVs(id).active_task_id = 0;
                return;
            end
            task_weight = tasks_info(row_idx, 3);                 % 获取任务重量
    
            task_times(tid, 2) = t;                               % 记录任务结束时间步
            % 计算耗时（转换为秒，假设每步对应1/6秒）
            time_spent_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
            task_dist_record(tid) = AGVs(id).total_dist - task_start_dist(tid); % 计算该任务行驶距离
    
            % 控制台输出任务完成信息
            fprintf('✅ [AGV-%02d] 任务完成！订单 #%d | 耗时: %.1f秒 | 运送里程: %d格\n', ...
                id, tid, time_spent_sec, task_dist_record(tid));
    
            % 扣除载重并从该车的剩余任务列表中移除已完成任务
            AGVs(id).payload_weight = max(0, AGVs(id).payload_weight - task_weight);
            AGVs(id).tasks(AGVs(id).tasks == tid) = [];          % 从任务列表中删除
    
            if ~isempty(AGVs(id).drop_queue)
                % 如果卸货队列中还有任务，继续送下一件
                next_drop_tid = AGVs(id).drop_queue(1);          % 获取下一个卸货任务
                AGVs(id).drop_queue(1) = [];                      % 从队列中移除
                AGVs(id).active_task_id = next_drop_tid;          % 设置为当前活跃任务
    
                next_row = get_task_row(next_drop_tid);
                if next_row == 0                                   % 任务无效
                    AGVs(id).status = 'Idle';
                    AGVs(id).active_task_id = 0;
                    AGVs(id).drop_queue = [];
                    return;
                end
                next_target_id = tasks_info(next_row, 2);         % 获取送货目标站点ID
                [~, drop_anchor, ~, drop_size] = get_task_coordinates(next_target_id); % 获取送货点区域
    
                if plan_path(id, drop_anchor, drop_size, t)       % 规划路径
                    AGVs(id).status = 'Moving_Drop';              % 转入送货移动状态
                else
                    AGVs(id).wait_timer = 2;                       % 失败则等待重试
                    AGVs(id).drop_queue = [next_drop_tid, AGVs(id).drop_queue]; % 任务放回
                end
            else
                % 卸货队列为空，说明该批次所有任务已完成
                fprintf('   -> AGV-%02d 批次配送全部收官。\n', id);
                AGVs(id).status = 'Idle';                          % 置为空闲
                AGVs(id).load = 0;                                  % 标记为空载
                AGVs(id).active_task_id = 0;                       % 清空活跃任务
            end
        end
    end 

    function export_simulation_results(num_agvs, AGVs, task_list, task_times, task_dist_record, task_executor, task_trajectories)
        disp('>> [数据模块] 正在生成仿真报告...');
        save_dir = fileparts(mfilename('fullpath')); % 获取当前脚本所在绝对路径
        
        % 1. 导出任务指标 (task_metrics.csv)
        try
            csv_file_path = fullfile(save_dir, 'task_metrics.csv');
            fid = fopen(csv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid, 'task_id,agv_id,time_sec,distance\n');
            for i = 1:size(task_list, 1)
                tid = task_list(i, 1);
                if task_times(tid, 2) > 0 % 只记录已完成的任务
                    t_sec = (task_times(tid, 2) - task_times(tid, 1)) / 6.0;
                    dist = task_dist_record(tid);
                    agv_str = sprintf('AGV-%02d', task_executor(tid));
                    fprintf(fid, '%d,%s,%.1f,%d\n', tid, agv_str, t_sec, dist);
                end
            end
            fclose(fid);
            disp('  -> 已生成: task_metrics.csv');
        catch ME
            fprintf('  -> [错误] task_metrics.csv 生成失败: %s\n', ME.message);
        end
        
        % 2. 导出轨迹数据 (task_paths.json)
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
                disp('  -> 已生成: task_paths.json');
            else
                disp('  -> [错误] 无法创建 task_paths.json 文件！');
            end
        catch ME
            fprintf('  -> [错误] task_paths.json 生成失败: %s\n', ME.message);
        end
        
        % 3. 导出设备状态 (agv_metrics.csv)
        try
            agv_file_path = fullfile(save_dir, 'agv_metrics.csv');
            fid_agv = fopen(agv_file_path, 'w', 'n', 'utf-8');
            fprintf(fid_agv, 'agv_id,agv_type,battery,total_distance,total_turns\n');
            for k = 1:num_agvs
                fprintf(fid_agv, '%d,%d,%.2f,%d,%d\n', ...
                    k, AGVs(k).type, AGVs(k).battery, AGVs(k).total_dist, AGVs(k).total_turns);
            end
            fclose(fid_agv);
            disp('  -> 已生成: agv_metrics.csv');
        catch ME
            fprintf('  -> [错误] agv_metrics.csv 生成失败: %s\n', ME.message);
        end
    end

end
