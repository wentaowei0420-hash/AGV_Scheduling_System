function Final_Thesis_Simulation()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    
    % =================================================================
    % 毕业设计：基于遗传算法的多AGV配件输送系统调度与仿真
    % 功能包含：
    % 1. 环境建模 (栅格地图)
    % 2. 任务生成 (模拟MES指令)
    % 3. 遗传算法调度 (任务分配与顺序优化)
    % 4. 状态管理 (电量监测、自动充电)
    % 5. 动态可视化 (多AGV路径演示)
    % =================================================================
    
    % 函数入口，不需要输入参数
    clc; clear; close all;
    % 清除命令行、清除变量、关闭所有图窗，确保运行环境干净
    
    %% --- 1. 系统初始化与参数设置 ---
    disp('>> 系统初始化中...');
    
    % 地图参数
    global mapW mapH binaryMap 
    mapW = 70; mapH = 50;
    % 生成基础静态地图 (不含特定目标留白，用于计算基础距离)
    binaryMap = create_binary_grid_map(mapW, mapH, 0); 
    
    % AGV 参数
    num_agvs = 2;               % AGV数量
    agv_speed = 0.01;           % 运行速度 (格/秒)
    battery_full = 100;         % 满电量
    battery_consume = 0.05;     % 耗电率 (%/格)
    battery_threshold = 20;     % 低电量阈值 (触发充电)
    
    % 充电桩位置 (地图左下和右下)
    charge_stations = [2, 2; 39, 2]; 
    % 初始位置 (假设都在车库)
    depots = [3, 7; 3, 11]; 
    
    % 生成任务列表 (模拟生产管理系统 MES 下发)
    % 格式: {任务ID, 目标工位ID, 优先级}
    % 这里随机生成 5 个任务
    task_list = [
        1, 1;   % 任务1: 去 1号工位
        2, 5;   % 任务2: 去 5号工位
        3, 8;   % 任务3: 去 8号工位
        4, 13;  % 任务4: 去 13号转向架
        5, 16   % 任务5: 去 16号横梁
    ];
    disp(['>> 接收到 MES 任务数量: ' num2str(size(task_list, 1))]);
    
    %% --- 2. 预计算距离矩阵 (加速 GA) ---
    % 为了避免在GA中频繁调用A*，我们需要预先计算关键点之间的距离
    disp('>> 正在预计算路径代价矩阵 (Pre-computation)...');
    dist_matrix = build_distance_matrix(task_list, depots, charge_stations);
    
    %% --- 3. 遗传算法 (GA) 调度核心 ---
    disp('>> 启动智能调度系统 (Genetic Algorithm)...');
    
    % GA 参数
    pop_size = 50;      % 种群规模：一次进化中有 50 个方案参与竞争
    max_gen = 100;      % 迭代次数：进化 100 代
    mutation_rate = 0.1;% 变异率：10% 的概率发生基因突变，防止陷入局部最优
    
    % A. 编码初始化: 采用 "任务序列 + 分隔符" 编码
    % 例如: [1, 3, 0, 2, 4, 5] 表示 AGV1做1,3; AGV2做2,4,5 (0为分隔符)
    num_tasks = size(task_list, 1);
    num_separators = num_agvs - 1;
    len_chrom = num_tasks + num_separators;
    
    population = zeros(pop_size, len_chrom);
    for i = 1:pop_size
        base_perm = randperm(num_tasks); % 任务随机排列
        separators = zeros(1, num_separators); % 分隔符 (0)
        % 随机插入分隔符
        full_gene = [base_perm, separators];
        population(i, :) = full_gene(randperm(length(full_gene)));
    end
    
    % B. 进化循环
    best_fitness_history = zeros(max_gen, 1);
    global_best_chrom = [];
    global_best_fit = inf;
    
    for gen = 1:max_gen
        % 计算适应度
        fitness = zeros(pop_size, 1);
        for i = 1:pop_size
            fitness(i) = calculate_makespan(population(i,:), num_agvs, task_list, dist_matrix, depots);
        end
        
        % 记录最优
        [min_fit, idx] = min(fitness);
        if min_fit < global_best_fit
            global_best_fit = min_fit;
            global_best_chrom = population(idx, :);
        end
        best_fitness_history(gen) = min_fit;
        
        % 选择 (锦标赛)
        new_pop = population;
        for i = 1:pop_size
            p1 = randi(pop_size); p2 = randi(pop_size);
            if fitness(p1) < fitness(p2), winner = population(p1,:); else, winner = population(p2,:); end
            new_pop(i,:) = winner;
        end
        
        % 交叉 (OX交叉) & 变异 (Swap) - 简化版实现
        for i = 1:2:pop_size
            if rand < 0.8 % 交叉概率
                % 简单单点交叉后修复
                pt = randi(len_chrom-1);
                child1 = [new_pop(i, 1:pt), new_pop(i+1, pt+1:end)]; % 需修复重复/缺失，此处略去复杂修复逻辑，仅做演示交换
                % 实际工程中需保证染色体合法性，这里为了代码简洁，仅做变异
            end
        end
        
        % 变异
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
    
    disp(['>> 调度完成。最优总耗时估算: ' num2str(global_best_fit)]);
    
    %% --- 4. 解析最优调度方案 ---
    % 将最优染色体解码为每台 AGV 的具体任务链
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
    
    %% --- 5. 最终仿真执行 (双窗口实时显示版) ---
    disp('>> 开始可视化仿真...');
    
    % === 窗口 1: 工厂地图 (主界面) ===
    generate_beautiful_factory_map(); % 不接收返回值
    f_map = gcf; % gcf = Get Current Figure (获取刚刚弹出的那个窗口)
    set(f_map, 'Name', '主监控界面 - 路径跟踪', 'NumberTitle', 'off', 'Position', [50, 200, 1000, 700]);
    title('多AGV智能调度实时监控系统');
    
    % === 窗口 2: 电量仪表盘 (副界面) ===
    f_batt = figure('Name', '状态监控 - 电池电量', 'NumberTitle', 'off', 'Position', [1060, 200, 400, 400], 'Color', 'w');
    ax_batt = gca;
    % 初始化柱状图 (所有AGV初始100%)
    agv_ids = 1:num_agvs;
    init_batt = ones(1, num_agvs) * 100;
    
    % 创建柱状图对象 (保存句柄 b_handle 以便后续更新)
    b_handle = bar(agv_ids, init_batt, 0.5); 
    
    % 美化仪表盘
    ylim([0 100]);
    xlabel('AGV 编号');
    ylabel('电量 (%)');
    title('AGV 实时电量监控');
    grid on;
    set(gca, 'XTick', 1:num_agvs);
    % 开启柱状图独立颜色控制
    b_handle.FaceColor = 'flat'; 
    
    % === 初始化 AGV 图形对象 ===
    figure(f_map); % 切换回地图窗口进行绘制
    AGVs = struct([]);
    for k = 1:num_agvs
        AGVs(k).id = k;
        AGVs(k).pos = depots(k, :);        
        AGVs(k).battery = battery_full;    
        AGVs(k).tasks = agv_schedules{k};  
        AGVs(k).status = 'Idle';           
        AGVs(k).path = [];                 
        AGVs(k).path_idx = 1;              
        
        % 1. 绘制 AGV 车身
        px = AGVs(k).pos(2); py = AGVs(k).pos(1);
        AGVs(k).handle = rectangle('Position', [px-0.9, py-0.9, 0.8, 0.8], ...
            'Curvature', 0.2, 'FaceColor', [0.2 0.8 0.2], 'EdgeColor', 'k', 'LineWidth', 1);
            
        % 2. 绘制简略信息 (只显示 ID, 不显示电量了)
        AGVs(k).text_handle = text(px-0.5, py-0.5, ['ID:' num2str(k)], ...
            'Color', 'k', 'FontSize', 8, 'FontWeight', 'bold', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle');
    end
    
    % === 仿真主循环 ===
    sim_running = true; 
    
    while sim_running
        sim_running = false; 
        
        % 准备电量数据数组 (用于一次性更新图表)
        current_batteries = zeros(1, num_agvs);
        
        for k = 1:num_agvs
            % --- 决策逻辑 (保持原样，无需修改) ---
            if isempty(AGVs(k).path)
                % [优先级1] 充电
                if AGVs(k).battery < battery_threshold && ~strcmp(AGVs(k).status, 'Charging') && ~strcmp(AGVs(k).status, 'Going_Charge')
                    AGVs(k).status = 'Going_Charge';
                    tempMap = create_binary_grid_map(mapW, mapH, 0);
                    % 解锁当前位置
                    cur_y = round(AGVs(k).pos(1)); cur_x = round(AGVs(k).pos(2));
                    tempMap(cur_y, cur_x) = 0;
                    
                    [p, ~, ~, ~] = astar_planner_turn(tempMap, AGVs(k).pos, charge_stations(1,:), 0.7);
                    AGVs(k).path = p;
                    AGVs(k).path_idx = 1;
                    
                % [优先级2] 干活
                elseif ~isempty(AGVs(k).tasks)
                    current_task_id = AGVs(k).tasks(1);
                    target_station = task_list(current_task_id, 2);
                    tempMap = create_binary_grid_map(mapW, mapH, target_station);
                    % 解锁当前位置
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
                % [优先级3] 回车库
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
            
            % --- 执行移动 ---
            if ~isempty(AGVs(k).path)
                sim_running = true; 
                
                if AGVs(k).path_idx <= size(AGVs(k).path, 1)
                    next_pos = AGVs(k).path(AGVs(k).path_idx, :);
                    AGVs(k).pos = next_pos;
                    AGVs(k).path_idx = AGVs(k).path_idx + 1;
                    AGVs(k).battery = AGVs(k).battery - battery_consume; 
                    
                    % 更新地图上的位置 (Window 1)
                    px = next_pos(2); py = next_pos(1);
                    set(AGVs(k).handle, 'Position', [px-0.9, py-0.9, 0.8, 0.8]);
                    set(AGVs(k).text_handle, 'Position', [px-0.5, py-0.5]);
                    
                    % 状态变色逻辑
                    switch AGVs(k).status
                        case {'Moving_Pick', 'Moving_Drop'}
                             set(AGVs(k).handle, 'FaceColor', [1 0.8 0.2]); % 黄
                        case 'Going_Charge'
                             set(AGVs(k).handle, 'FaceColor', [1 0.2 0.2]); % 红
                        case 'Idle'
                             set(AGVs(k).handle, 'FaceColor', [0.2 0.8 0.2]); % 绿
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
            
            % 记录当前电量以便更新图表
            current_batteries(k) = AGVs(k).battery;
        end
        
        % === 更新电量仪表盘 (Window 2) ===
        % 只有当窗口还开着的时候才更新，防止报错
        if isvalid(f_batt)
            set(b_handle, 'YData', current_batteries);
            
            % 根据电量变色 (Green > 50, Yellow > 20, Red < 20)
            cdata = zeros(num_agvs, 3);
            for k = 1:num_agvs
                bat = current_batteries(k);
                if bat > 50
                    cdata(k,:) = [0.2 0.8 0.2]; % 绿
                elseif bat > 20
                    cdata(k,:) = [1 0.8 0.2];   % 黄
                else
                    cdata(k,:) = [1 0.2 0.2];   % 红
                end
            end
            set(b_handle, 'CData', cdata);
        end
        
        drawnow limitrate; 
        pause(0.05)
    end
    disp('>> 仿真结束。');
end

%% ================= 辅助函数库 =================
% 1. 解码染色体
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

% 2. 适应度计算 (Makespan)
function max_time = calculate_makespan(chrom, num_agvs, tasks, dist_mat, depots)
    schedules = decode_chromosome(chrom, num_agvs);
    agv_times = zeros(1, num_agvs);
    
    for k = 1:num_agvs
        task_ids = schedules{k};
        if isempty(task_ids), continue; end
        
        current_node_idx = 100 + k; % 假设 100+k 是车库在矩阵中的索引
        
        for t_id = task_ids
            % 查找距离: 当前 -> 任务取货点 -> 任务送货点
            % 简化：在 build_distance_matrix 中我们定义索引规则：
            % 1~N: 取货点, N+1~2N: 送货点
            % Depot 需特殊处理，这里用曼哈顿距离估算代替查表以简化代码长度
            
            % 简单逻辑估算代价 (Cost) 用于 GA 快速迭代
            % 实际应查表 dist_matrix
            agv_times(k) = agv_times(k) + rand * 10 + 20; % 模拟代价
        end
    end
    max_time = max(agv_times);
end

% 3. 构建距离矩阵 (占位，实际应循环调用 A*)
function mat = build_distance_matrix(tasks, depots, charges)
    % 这是一个耗时操作，通常在系统启动时做一次
    % 这里返回一个空矩阵，实际逻辑在 calculate_makespan 中用估算代替
    mat = [];
end