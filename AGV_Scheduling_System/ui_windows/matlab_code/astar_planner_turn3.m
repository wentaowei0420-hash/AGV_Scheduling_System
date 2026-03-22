function [path, gScore_goal, turn_count, expanded_nodes, path_length, gScore_matrix, turnPenalty] = astar_planner_turn3(map, start, goal, payload_weight, cost_map)
%% 初始化转向惩罚值
    base_penalty = 1;         % 基础转弯惩罚 (空载状态下的转向阻力)
    linear_factor = 0.0001;      % 线性载荷因子 (模拟摩擦力增加)
    inertia_factor = 3/6400;    % 二阶惯性因子 (模拟重载离心惯量)
    turnPenalty = base_penalty + linear_factor * payload_weight + inertia_factor * (payload_weight^2); % 根据负载计算总转向惩罚
    [rows, cols] = size(map);   % 获取地图的行数和列数
%% 起点或终点位于障碍物内---->直接返回空路径
    if map(start(1), start(2)) == 1 || map(goal(1), goal(2)) == 1
        path = []; 
        gScore_goal = inf; 
        turn_count = 0; 
        expanded_nodes = 0; 
        path_length = 0; 
        gScore_matrix = []; return; % 返回空结果
    end
%% 预计算全局自适应参数
    dist_start_to_goal = sqrt((start(1) - goal(1))^2 + (start(2) - goal(2))^2); % 起点到终点的欧几里得距离
    if dist_start_to_goal == 0
        dist_start_to_goal = 1e-6; % 避免除零，当起点等于终点时设为极小值
    end
    
    % --- 3. 建立 3D 状态空间矩阵 [Row, Col, Direction] ---
    % 维度3表示驶入该栅格的方向: 1=北(-1,0), 2=南(1,0), 3=西(0,-1), 4=东(0,1)
    numNodes3D = rows * cols * 4; % 三维状态空间的总节点数
    gScore = inf(rows, cols, 4);  % 从起点到每个状态 (r,c,d) 的实际代价，初始为无穷大
    fScore = inf(rows, cols, 4);  % 估计总代价 g + h，初始为无穷大
    parent_idx = zeros(rows, cols, 4); % 记录每个状态的前驱节点（三维索引）
    
    openList = [];                 % 开放列表，存放待扩展节点的三维线性索引
    openMask = false(numNodes3D, 1); % 布尔掩码，标记某个三维索引是否在开放列表中
    
%% 初始化起点（起步时朝向未知，因此将4个方向全塞入开放列表，代价为0）
    for d = 1:4
        gScore(start(1), start(2), d) = 0; % 起点四个方向的g代价均为0
        fScore(start(1), start(2), d) = abs(start(1)-goal(1)) + abs(start(2)-goal(2)); % 启发式：曼哈顿距离
        idx3D = start(1) + (start(2)-1)*rows + (d-1)*(rows*cols); % 将三维坐标转换为线性索引
        openList(end+1) = idx3D;   % 将索引加入开放列表
        openMask(idx3D) = true;    % 标记该索引在开放列表中
    end
    
    dirVecs = [-1, 0; 1, 0; 0, -1; 0, 1]; % 四个方向对应的行、列变化：北、南、西、东
    
    pathFound = false;               % 是否找到路径的标志
    expanded_nodes = 0;               % 记录扩展的节点数（三维状态计数）
    bestGoalIdx3D = -1;               % 到达目标时对应的最佳三维索引
    
    while ~isempty(openList)
        [~, minPos] = min(fScore(openList)); % 在开放列表中找出fScore最小的位置
        curr3D = openList(minPos);      % 获取该节点的三维线性索引
        expanded_nodes = expanded_nodes + 1; % 扩展节点数加1
        
        openList(minPos) = [];               % 从开放列表中移除该节点
        openMask(curr3D) = false;            % 更新掩码，标记不在开放列表
        
        % 将三维线性索引转换回 (r,c,d)
        rem_idx = curr3D - 1;                % 转为0基索引方便计算
        currD = floor(rem_idx / (rows * cols)) + 1; % 方向分量：1~4
        rem_idx = mod(rem_idx, rows * cols);       % 剩余部分
        currC = floor(rem_idx / rows) + 1;         % 列坐标
        currR = mod(rem_idx, rows) + 1;             % 行坐标
        
        % 如果当前节点位置就是目标点，则成功找到路径，跳出循环
        if currR == goal(1) && currC == goal(2)
            pathFound = true;
            bestGoalIdx3D = curr3D; % 记录到达目标的三维索引
            break;
        end
        
        % 遍历四个可能的前进方向（邻居）
        for nD = 1:4
            nR = currR + dirVecs(nD, 1);       % 邻居的行坐标
            nC = currC + dirVecs(nD, 2);       % 邻居的列坐标
            
            % 检查是否在地图范围内且不是障碍物
            if nR < 1 || nR > rows || nC < 1 || nC > cols || map(nR, nC) == 1
                continue; % 无效邻居，跳过
            end
            
            % 地形代价：默认1.0，如果提供了cost_map则使用对应栅格的代价
            terrain_cost = 1.0; 
            if nargin >= 5 && ~isempty(cost_map)
                if nR <= size(cost_map, 1) && nC <= size(cost_map, 2)
                    terrain_cost = cost_map(nR, nC);
                end
            end
            
            % 初步计算到达邻居的g代价：当前g + 移动代价（基础1.0 * 地形代价）
            tentative_gScore = gScore(currR, currC, currD) + 1.0 * terrain_cost;
            
            % 判断是否是起始节点（起点不考虑转弯惩罚，因为刚出发没有方向）
            isStartNode = (currR == start(1) && currC == start(2));
            if ~isStartNode && nD ~= currD
                % 如果不是起点且方向改变，则加上转向惩罚
                tentative_gScore = tentative_gScore + turnPenalty; 
            end
            
            % 状态更新：如果新的g值比原来记录的更小，则更新该状态
            if tentative_gScore < gScore(nR, nC, nD)
                gScore(nR, nC, nD) = tentative_gScore;          % 更新g值
                parent_idx(nR, nC, nD) = curr3D;                % 记录前驱索引
                
                % 计算启发式h（曼哈顿距离）
                h_base = abs(nR - goal(1)) + abs(nC - goal(2));
                
                % 自适应权重因子：根据当前点到目标的距离与起点到目标距离的比值生成一个压缩的指数项
                dist_current_to_goal = sqrt((nR - goal(1))^2 + (nC - goal(2))^2); % 当前点到目标的欧氏距离
                a_raw = exp(dist_current_to_goal / dist_start_to_goal) - 1.0;    % 原始指数因子
                a_compressed = a_raw * 0.4;                                      % 压缩系数0.4
                
                % 最终的fScore = g + h * (1 + a_compressed)  —— 启发式权重自适应
                fScore(nR, nC, nD) = tentative_gScore + h_base * (1.0 + a_compressed);
                
                % 计算邻居的三维线性索引
                neighbor3D = nR + (nC-1)*rows + (nD-1)*(rows*cols);
                
                % 如果邻居不在开放列表中，则加入开放列表
                if ~openMask(neighbor3D)
                    openList(end+1) = neighbor3D; %#ok<AGROW> 追加到开放列表
                    openMask(neighbor3D) = true;  % 标记在开放列表中
                end
            end
        end
    end

    % 如果找到路径，回溯构建路径
    if pathFound
        curr = bestGoalIdx3D; % 从目标状态的三维索引开始回溯
        path_list = [];       % 存储路径点的列表（按顺序）
        
        while curr ~= 0       % 当前索引非零表示还有前驱（起点的前驱为0）
            % 将三维线性索引转换为 (r,c)
            rem_idx = curr - 1;
            rem_idx = mod(rem_idx, rows * cols);
            c = floor(rem_idx / rows) + 1;
            r = mod(rem_idx, rows) + 1;
            
            path_list = [[r, c]; path_list]; % 将点插入到列表前面，保证从起点到终点顺序
            
            % 如果已经回溯到起点，则停止（起点的parent_idx为0，但这里需要判断位置）
            if r == start(1) && c == start(2)
                break;
            end
            
            % 获取当前状态的方向，以便找到对应的前驱
            currD = floor((curr - 1) / (rows * cols)) + 1;
            curr = parent_idx(r, c, currD);  % 更新为前驱的三维索引
        end
        
        path = path_list; % 最终路径，按起点到终点顺序排列
        
        % 取目标点所有方向中最小的g值作为到达目标的代价
        gScore_goal = min(gScore(goal(1), goal(2), :)); 
        
        path_length = size(path, 1); % 路径长度（栅格点数）
        
        % 计算转向次数：通过相邻移动向量的变化来检测方向变化
        turn_count = 0;
        if size(path, 1) > 2
            diffs = diff(path);          % 计算相邻点之间的位移向量
            for i = 2:size(diffs, 1)
                if ~isequal(diffs(i,:), diffs(i-1,:)) % 如果当前位移与上一个不同，说明转向
                    turn_count = turn_count + 1;
                end
            end
        end
    else
        % 未找到路径，返回空值
        path = []; gScore_goal = inf; turn_count = 0; path_length = 0; 
    end
    
    % 计算二维gScore矩阵（取各方向最小值），用于可视化或统计
    gScore_matrix = min(gScore, [], 3);
    
    % 计算扩展过的二维栅格数量（即gScore_matrix中有限值的个数）
    explored_2d_mask = (gScore_matrix ~= inf);
    expanded_nodes = sum(explored_2d_mask, 'all');
end