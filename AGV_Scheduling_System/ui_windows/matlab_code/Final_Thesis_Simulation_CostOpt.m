function Final_Thesis_Simulation_CostOpt()
    % =================================================================
    % 毕业设计：基于总成本最小化的多AGV调度与仿真
    % 优化目标：Min(路径成本 + 能耗成本 + 延期惩罚)
    % =================================================================
    
    clc; clear; close all;
    
    %% --- 1. 系统初始化与参数设置 ---
    disp('>> 系统初始化中...');
    
    global mapW mapH binaryMap
    mapW = 70; mapH = 50;
    binaryMap = create_binary_grid_map(mapW, mapH, 0); 
    
    % --- AGV 物理参数 ---
    num_agvs = 2;               
    agv_speed = 1.5;            % 速度 (格/秒)
    battery_full = 100;         
    
    % --- 能耗参数 (关键模型) ---
    base_energy_rate = 0.02;    % 空载耗电 (%/格)
    load_energy_factor = 0.01;  % 负载系数: 每增加1kg重量，耗电增加多少
    
    % --- 成本权重系数 ---
    w_dist = 1.0;               % 距离成本权重 (元/格)
    w_energy = 5.0;             % 能耗成本权重 (元/%)
    w_penalty = 10.0;           % 延期惩罚权重 (元/秒)
    
    % 位置定义
    charge_stations = [2, 2; 39, 2]; 
    depots = [3, 7; 3, 11]; 
    
    % --- 任务列表 (新增两列：重量、截止时间) ---
    % 格式: {ID, 目标工位ID, 货物重量(kg), 截止时间(秒)}
    task_list = [
        1, 1,  10, 200;   % 任务1: 去1号, 重10kg, 200秒内送到
        2, 5,  5,  150;   % 任务2: 去5号, 轻货, 截止时间紧
        3, 8,  20, 300;   % 任务3: 去8号, 重货
        4, 13, 15, 250;   % 任务4: 转向架
        5, 16, 8,  180    % 任务5: 横梁
    ];
    disp(['>> 接收到任务: ' num2str(size(task_list, 1)) ' 个 (含重量与截止时间)']);

    %% --- 2. 遗传算法 (GA) 成本优化 ---
    disp('>> 启动基于成本优化的调度系统...');
    
    pop_size = 50; max_gen = 80; mutation_rate = 0.15;
    
    % 编码初始化
    num_tasks = size(task_list, 1);
    len_chrom = num_tasks + num_agvs - 1;
    population = zeros(pop_size, len_chrom);
    for i = 1:pop_size
        base_perm = randperm(num_tasks);
        full_gene = [base_perm, zeros(1, num_agvs-1)];
        population(i, :) = full_gene(randperm(length(full_gene)));
    end
    
    % 进化循环
    best_cost_history = zeros(max_gen, 1);
    global_best_chrom = [];
    global_min_cost = inf;
    
    for gen = 1:max_gen
        costs = zeros(pop_size, 1);
        for i = 1:pop_size
            % 【核心修改】计算总成本，而非单纯的时间
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
        
        % 简单的锦标赛选择与变异
        new_pop = population;
        for i = 1:pop_size
            if rand < mutation_rate
                pos = randperm(len_chrom, 2);
                new_pop(i, [pos(1), pos(2)]) = new_pop(i, [pos(2), pos(1)]);
            end
        end
        population = new_pop;
    end
    
    disp(['>> 优化完成。最低综合成本: ' num2str(global_min_cost)]);
    
    %% --- 3. 解析最优调度 ---
    agv_schedules = decode_chromosome(global_best_chrom, num_agvs);
        % 打印调度结果
    for k = 1:num_agvs
        task_ids = agv_schedules{k};
        str = sprintf('AGV-%d 任务队列: ', k);
        if isempty(task_ids)
            str = [str '空闲'];
        else
            for t = task_ids
                str = [str, sprintf('Task-%d(工位%d) -> ', t, task_list(t, 2))];
            end
        end
        disp(str);
    end
    
    %% --- 4. 可视化仿真 ---
    % === 窗口 1: 工厂地图 (主界面) ===
    generate_beautiful_factory_map(); % 不接收返回值
    f_map = gcf; % gcf = Get Current Figure (获取刚刚弹出的那个窗口)
    set(f_map, 'Name', '主监控界面: 路径跟踪', 'NumberTitle', 'off', 'Position', [50, 200, 1000, 700]);
    title('多AGV智能调度实时监控系统');
    
    f_batt = figure('Name', '电量监控', 'NumberTitle', 'off', 'Position', [1060, 200, 400, 300], 'Color', 'w');
    b_handle = bar(1:num_agvs, ones(1,num_agvs)*100, 0.5); 
    title('AGV 实时电量'); ylim([0 100]); b_handle.FaceColor = 'flat';
    
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
        AGVs(k).current_load = 0; % 当前负载重量
        
        px = AGVs(k).pos(2); py = AGVs(k).pos(1);
        AGVs(k).handle = rectangle('Position', [px-0.9, py-0.9, 0.8, 0.8], ...
            'Curvature', 0.2, 'FaceColor', [0.2 0.8 0.2], 'EdgeColor', 'k', 'LineWidth', 1.5);
        AGVs(k).text_handle = text(px-0.5, py-0.5, ['ID:' num2str(k)], ...
            'Color', 'k', 'FontSize', 8, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
    end
    
    sim_running = true; 
    
    while sim_running
        sim_running = false; 
        current_batteries = zeros(1, num_agvs);
        
        for k = 1:num_agvs
            if isempty(AGVs(k).path)
                % [决策逻辑]
                if ~isempty(AGVs(k).tasks)
                    task_idx = AGVs(k).tasks(1);
                    target_id = task_list(task_idx, 2);
                    task_weight = task_list(task_idx, 3); % 获取重量
                    
                    tempMap = create_binary_grid_map(mapW, mapH, target_id);
                    % 解锁起点
                    cy = round(AGVs(k).pos(1)); cx = round(AGVs(k).pos(2));
                    if cy>=1 && cy<=mapH && cx>=1 && cx<=mapW, tempMap(cy, cx)=0; end

                    if strcmp(AGVs(k).status, 'Idle') || strcmp(AGVs(k).status, 'Task_Done') || strcmp(AGVs(k).status, 'Backing_Garage')
                        AGVs(k).status = 'Moving_Pick';
                        AGVs(k).current_load = 0; % 去取货时是空载
                        [pickup, ~] = get_task_coordinates(target_id);
                        if tempMap(pickup(1), pickup(2))==1, tempMap(pickup(1), pickup(2))=0; end
                        [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, pickup, 0.7);
                        AGVs(k).path = p;
                        AGVs(k).path_idx = 1;
                        
                    elseif strcmp(AGVs(k).status, 'Picked_Up')
                        AGVs(k).status = 'Moving_Drop';
                        AGVs(k).current_load = task_weight; % 装货，负载增加
                        [~, dropoff] = get_task_coordinates(target_id);
                        [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, dropoff, 0.7);
                        AGVs(k).path = p;
                        AGVs(k).path_idx = 1;
                    end
                elseif AGVs(k).battery < 20
                     % ... (充电逻辑同前) ...
                    AGVs(k).status = 'Going_Charge';
                    tempMap = create_binary_grid_map(mapW, mapH, 0);
                    % 解锁当前位置
                    cur_y = round(AGVs(k).pos(1)); cur_x = round(AGVs(k).pos(2));
                    tempMap(cur_y, cur_x) = 0;
                    [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, charge_stations(1,:), 0.7);
                    AGVs(k).path = p;
                    AGVs(k).path_idx = 1;
                else
                     % ... (回车库逻辑同前) ...
                     if ~strcmp(AGVs(k).status, 'Backing_Garage') && ~strcmp(AGVs(k).status, 'Idle')
                        dist = sum(abs(AGVs(k).pos - depots(k,:)));
                        if dist > 1
                             AGVs(k).status = 'Backing_Garage';
                             AGVs(k).current_load = 0; % 空载回家
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
            
            % [移动执行]
            if ~isempty(AGVs(k).path)
                sim_running = true; 
                if AGVs(k).path_idx <= size(AGVs(k).path, 1)
                    next_pos = AGVs(k).path(AGVs(k).path_idx, :);
                    AGVs(k).pos = next_pos;
                    AGVs(k).path_idx = AGVs(k).path_idx + 1;
                    
                    % === 【关键】动态能耗计算 ===
                    % 耗电量 = 基础耗电 + 负载系数 * 重量
                    current_consume = base_energy_rate + load_energy_factor * AGVs(k).current_load;
                    AGVs(k).battery = AGVs(k).battery - current_consume;
                    
                    % 更新图形
                    px = next_pos(2); py = next_pos(1);
                    set(AGVs(k).handle, 'Position', [px-0.9, py-0.9, 0.8, 0.8]);
                    set(AGVs(k).text_handle, 'Position', [px-0.5, py-0.5]);
                    
                    % 状态颜色
                    if AGVs(k).current_load > 0
                        set(AGVs(k).handle, 'FaceColor', [1 0.6 0]); % 载重时深橙色
                    else
                        set(AGVs(k).handle, 'FaceColor', [0.2 0.8 0.2]); % 空载绿色
                    end
                else
                     % 到达逻辑
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
             % 变色逻辑略
        end
        drawnow limitrate;
        pause(0.05)
    end
end

%% ================= 核心算法函数库 =================

% --- 解码 ---
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

% --- 【核心】总成本计算函数 ---
function total_cost = calculate_total_cost(chrom, num_agvs, tasks, depots, speed, e_base, e_load, w1, w2, w3)
    schedules = decode_chromosome(chrom, num_agvs);
    
    total_dist = 0;
    total_energy = 0;
    total_penalty = 0;
    
    for k = 1:num_agvs
        task_ids = schedules{k};
        if isempty(task_ids), continue; end
        
        current_pos = depots(k, :); % 逻辑坐标
        current_time = 0;
        
        for t_id = task_ids
            target_id = tasks(t_id, 2);
            weight = tasks(t_id, 3);
            deadline = tasks(t_id, 4);
            
            [pickup, dropoff] = get_task_coordinates(target_id);
            
            % 1. 空载行驶 (去取货)
            % 这里为了速度，用曼哈顿距离代替 A* (GA迭代中必须快)
            dist_empty = sum(abs(current_pos - pickup)); 
            time_empty = dist_empty / speed;
            energy_empty = dist_empty * e_base;
            
            % 2. 负载行驶 (去送货)
            dist_loaded = sum(abs(pickup - dropoff));
            time_loaded = dist_loaded / speed;
            % 【能耗模型】：负载越重，耗电越多
            energy_loaded = dist_loaded * (e_base + e_load * weight);
            
            % 更新状态
            current_pos = dropoff;
            current_time = current_time + time_empty + time_loaded + 5; % +5s 装卸时间
            
            % 3. 计算惩罚
            if current_time > deadline
                penalty = (current_time - deadline) * w3; % 超时罚款
            else
                penalty = 0;
            end
            
            % 累加各项成本
            total_dist = total_dist + dist_empty + dist_loaded;
            total_energy = total_energy + energy_empty + energy_loaded;
            total_penalty = total_penalty + penalty;
        end
    end
    
    % 总成本公式
    total_cost = (w1 * total_dist) + (w2 * total_energy) + total_penalty;
end

% --- 需要粘贴的其他函数 ---
% 请务必在下方粘贴: 
% 1. get_task_coordinates
% 2. create_binary_grid_map
% 3. astar_planner_turn (优化版)
% 4. generate_beautiful_factory_map
% 5. 辅助绘图函数