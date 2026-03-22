function [path, gScore_goal, turn_count, expanded_nodes, path_length, gScore_matrix] = astar_planner_turn(map, start, goal, turnPenalty)
    % 带转弯惩罚的 A* 路径规划器 (优化版，使用线性索引加速)
    % 输入:
    %   map        - 二维地图矩阵，0=可通行，1=障碍物
    %   start      - 起点坐标 [row, col]
    %   goal       - 终点坐标 [row, col]
    %   turnPenalty- 转弯惩罚权重（正数，越大越不喜欢转弯）
    % 输出:
    %   path          - 路径点序列 [row col] 格式，若失败则为空
    %   gScore_goal   - 到达终点的实际代价（包含转弯惩罚），若失败则为 inf
    %   turn_count    - 路径中的转弯次数
    %   expanded_nodes- 扩展过的节点总数
    %   path_length   - 最终路径包含的栅格数量 (即经过的节点数) % <--- 【新增说明】
    
    [rows, cols] = size(map);   % 获取地图尺寸
    % --- 1. 预处理：坐标转线性索引 ---
    % 将 (r,c) 转换为单个数 index，提高访问速度（避免反复调用 sub2ind）
    startIdx = sub2ind([rows, cols], start(1), start(2));
    goalIdx = sub2ind([rows, cols], goal(1), goal(2));
    
    % 检查起点和终点是否在障碍物内（map 中 1 表示障碍）
    if map(startIdx) == 1 || map(goalIdx) == 1
        warning('起点或终点在障碍物内');
        path = []; gScore_goal = inf; turn_count = 0; expanded_nodes = 0; 
        path_length = 0; % <--- 【新增：起点或终点无效时，栅格数为0】
        return;
    end
    
    % --- 2. 初始化数据结构 ---
    numNodes = rows * cols;         % 节点总数
    gScore = inf(numNodes, 1);      % g 值数组，初始为无穷大
    fScore = inf(numNodes, 1);      % f 值数组，初始为无穷大
    gScore(startIdx) = 0;           % 起点 g 值为 0
    % 计算起点的启发式 h (曼哈顿距离) 并赋给 fScore
    fScore(startIdx) = abs(start(1)-goal(1)) + abs(start(2)-goal(2));
    
    % parent 数组用于重构路径，存储父节点的线性索引（0 表示无父节点）
    parent = zeros(numNodes, 1);
    
    % enterDir 数组记录进入该节点时的移动方向（1:上, 2:下, 3:左, 4:右），用于转弯判断
    % 使用 int8 节省内存
    enterDir = zeros(numNodes, 1, 'int8');
    
    % OpenSet 管理：采用列表 + 标志位的方式
    openList = startIdx;            % 待扩展节点列表（初始只包含起点）
    openMask = false(numNodes, 1);  % 快速判断节点是否在 openList 中
    openMask(startIdx) = true;      % 标记起点在列表中
    
    % 方向定义: 上(-1,0), 下(1,0), 左(0,-1), 右(0,1)
    dirVecs = [-1, 0; 1, 0; 0, -1; 0, 1];
    % 注意：方向编号 1=上, 2=下, 3=左, 4=右，与 enterDir 中的记录一致
    pathFound = false;              % 标记是否找到路径
    expanded_nodes = 0;             % 已扩展节点计数器
    
    % --- 3. 主循环 ---
    while ~isempty(openList)
        % --- A. 寻找 fScore 最小的节点 ---
        % 直接在 openList 中找最小值（只对列表中的节点计算 min）
        [~, minPos] = min(fScore(openList));
        currentIdx = openList(minPos);      % 当前要扩展的节点索引
        expanded_nodes = expanded_nodes + 1; % 增加扩展计数
        
        % 如果当前节点是目标点，则搜索成功
        if currentIdx == goalIdx
            pathFound = true;
            break;
        end
        
        % --- B. 将当前节点移出 OpenSet ---
        openList(minPos) = [];               % 从列表中删除
        openMask(currentIdx) = false;        % 标记为不在 OpenSet
        
        % 获取当前节点的行列坐标（用于计算邻居）
        [currR, currC] = ind2sub([rows, cols], currentIdx);
        
        % --- C. 扩展四个方向的邻居 ---
        for d = 1:4
            % 计算邻居坐标
            nR = currR + dirVecs(d, 1);
            nC = currC + dirVecs(d, 2);
            % 1. 越界检查
            if nR < 1 || nR > rows || nC < 1 || nC > cols
                continue;
            end
            % 计算邻居线性索引（手动计算加速，避免 sub2ind）
            neighborIdx = nR + (nC - 1) * rows;
            % 2. 障碍物检查
            if map(neighborIdx) == 1
                continue;
            end
            
            % --- D. 代价计算 ---
            % 基础移动代价固定为 1（每步代价）
            tentative_gScore = gScore(currentIdx) + 1;
            
            % 转弯惩罚逻辑：
            % 如果不是起点（currentIdx ~= startIdx），且进入当前节点的方向（enterDir）与现在移动的方向 d 不同
            currentDir = enterDir(currentIdx);
            if currentIdx ~= startIdx && currentDir ~= 0 && currentDir ~= d
                tentative_gScore = tentative_gScore + turnPenalty; % 增加惩罚
            end
            
            % --- E. 如果找到了更优路径，更新节点信息 ---
            if tentative_gScore < gScore(neighborIdx)
                parent(neighborIdx) = currentIdx;          % 记录父节点
                gScore(neighborIdx) = tentative_gScore;    % 更新 g 值
                enterDir(neighborIdx) = d;                  % 记录进入方向
                
                % 计算启发式 h（曼哈顿距离）
                h_cost = abs(nR - goal(1)) + abs(nC - goal(2));
                fScore(neighborIdx) = tentative_gScore + h_cost; % 更新 f 值
                
                % 如果邻居不在 openList 中，则加入
                if ~openMask(neighborIdx)
                    openList(end+1) = neighborIdx;          % 添加到列表尾部
                    openMask(neighborIdx) = true;            % 标记在 OpenSet
                end
            end
        end
    end
    
    % --- 4. 路径重构 ---
    if pathFound
        % 从目标点回溯到起点，收集路径索引
        curr = goalIdx;
        pathIdx = [];
        while curr ~= 0
            pathIdx(end+1) = curr;       % 将当前节点加入列表（注意是反向顺序）
            curr = parent(curr);          % 移动到父节点
            if curr == startIdx
                pathIdx(end+1) = curr;   % 将起点也加入
                break;
            end
        end
        % 由于回溯是从目标到起点，需要翻转得到从起点到目标的顺序
        pathIdx = flip(pathIdx);
        % 将线性索引转换回 [row, col] 坐标
        [pRows, pCols] = ind2sub([rows, cols], pathIdx');
        path = [pRows, pCols];
        
        % 记录到达终点的总代价（包含转弯惩罚）
        gScore_goal = gScore(goalIdx);
        
        % 获取路径包含的栅格总数 % <--- 【新增：由于 path 矩阵的行数就是经过的栅格数，直接取 size 的行数即可】
        path_length = size(path, 1); 
        
        % 统计路径中的转弯次数
        turn_count = 0;
        if size(path, 1) > 2
            diffs = diff(path);          % 计算每一步的位移向量（[Δr, Δc]）
            for i = 2:size(diffs, 1)
                % 如果相邻两步的位移向量不同，说明发生了转弯
                if ~isequal(diffs(i,:), diffs(i-1,:))
                    turn_count = turn_count + 1;
                end
            end
        end
    else
        % 未找到路径，输出空结果
        path = [];
        gScore_goal = inf;
        turn_count = 0;
        path_length = 0; % <--- 【新增：未找到路径时，栅格数为0】
    end
    % 还原二维代价矩阵供热力图渲染
    gScore_matrix = reshape(gScore, [rows, cols]);
end