function [path, gScore_goal, turn_count, expanded_nodes, path_length, gScore_matrix] = astar_planner_turn2(map, start, goal, turnPenalty)
    % 基于障碍率改进的 A* 路径规划器 (论文动态权重 + 积分图优化版)
    
    [rows, cols] = size(map);   % 获取地图尺寸
    % --- 1. 预处理：坐标转线性索引 ---
    startIdx = sub2ind([rows, cols], start(1), start(2));
    goalIdx = sub2ind([rows, cols], goal(1), goal(2));
    
    % 检查起点和终点是否在障碍物内
    if map(startIdx) == 1 || map(goalIdx) == 1
        path = []; gScore_goal = inf; turn_count = 0; expanded_nodes = 0; 
        path_length = 0; gScore_matrix = [];
        return;
    end
    
    % --- ★ 核心优化：预计算“积分图”，用于 O(1) 时间极速计算区域障碍数 ★ ---
    % intMap(r,c) 代表从 (1,1) 到 (r,c) 这个矩形区域内所有障碍物的总和
    intMap = cumsum(cumsum(map, 1), 2);
    
    % --- 2. 初始化数据结构 ---
    numNodes = rows * cols;         
    gScore = inf(numNodes, 1);      
    fScore = inf(numNodes, 1);      
    gScore(startIdx) = 0;           
    fScore(startIdx) = abs(start(1)-goal(1)) + abs(start(2)-goal(2));
    
    parent = zeros(numNodes, 1);
    enterDir = zeros(numNodes, 1, 'int8');
    
    openList = startIdx;            
    openMask = false(numNodes, 1);  
    openMask(startIdx) = true;      
    
    dirVecs = [-1, 0; 1, 0; 0, -1; 0, 1];
    pathFound = false;              
    expanded_nodes = 0;             
    
    % --- 3. 主循环 ---
    while ~isempty(openList)
        [~, minPos] = min(fScore(openList));
        currentIdx = openList(minPos);      
        expanded_nodes = expanded_nodes + 1; 
        
        if currentIdx == goalIdx
            pathFound = true;
            break;
        end
        
        openList(minPos) = [];               
        openMask(currentIdx) = false;        
        
        [currR, currC] = ind2sub([rows, cols], currentIdx);
        
        for d = 1:4
            nR = currR + dirVecs(d, 1);
            nC = currC + dirVecs(d, 2);
            
            if nR < 1 || nR > rows || nC < 1 || nC > cols
                continue;
            end
            neighborIdx = nR + (nC - 1) * rows;
            if map(neighborIdx) == 1
                continue;
            end
            
            tentative_gScore = gScore(currentIdx) + 1;
            
            currentDir = enterDir(currentIdx);
            if currentIdx ~= startIdx && currentDir ~= 0 && currentDir ~= d
                tentative_gScore = tentative_gScore + turnPenalty; 
            end
            
            if tentative_gScore < gScore(neighborIdx)
                parent(neighborIdx) = currentIdx;          
                gScore(neighborIdx) = tentative_gScore;    
                enterDir(neighborIdx) = d;                  
                
                % --- ★ 论文改进逻辑：基于障碍率的动态权重计算 ★ ---
                h_base = abs(nR - goal(1)) + abs(nC - goal(2));
                
                % 确定当前节点到目标点构成的矩形边界
                min_r = min(nR, goal(1)); max_r = max(nR, goal(1));
                min_c = min(nC, goal(2)); max_c = max(nC, goal(2));
                
                % 利用积分图极速查询矩形内的障碍物数量 N
                N = intMap(max_r, max_c);
                if min_r > 1
                    N = N - intMap(min_r-1, max_c);
                end
                if min_c > 1
                    N = N - intMap(max_r, min_c-1);
                end
                if min_r > 1 && min_c > 1
                    N = N + intMap(min_r-1, min_c-1);
                end
                
                % 计算面积与障碍率 R
                area = (max_r - min_r + 1) * (max_c - min_c + 1);
                R = N / area;
                
                % 论文核心公式：动态计算启发式权重
                dynamic_w = 1 + exp(-R);
                fScore(neighborIdx) = tentative_gScore + dynamic_w * h_base;
                % ----------------------------------------------------
                
                if ~openMask(neighborIdx)
                    openList(end+1) = neighborIdx; %#ok<AGROW> 
                    openMask(neighborIdx) = true;            
                end
            end
        end
    end
    
    % --- 4. 路径重构 ---
    if pathFound
        curr = goalIdx;
        pathIdx = [];
        while curr ~= 0
            pathIdx(end+1) = curr;       
            curr = parent(curr);          
            if curr == startIdx
                pathIdx(end+1) = curr;   
                break;
            end
        end
        pathIdx = flip(pathIdx);
        [pRows, pCols] = ind2sub([rows, cols], pathIdx');
        path = [pRows, pCols];
        gScore_goal = gScore(goalIdx);
        path_length = size(path, 1); 
        
        turn_count = 0;
        if size(path, 1) > 2
            diffs = diff(path);          
            for i = 2:size(diffs, 1)
                if ~isequal(diffs(i,:), diffs(i-1,:))
                    turn_count = turn_count + 1;
                end
            end
        end
    else
        path = []; gScore_goal = inf; turn_count = 0; path_length = 0; 
    end
    gScore_matrix = reshape(gScore, [rows, cols]);
end