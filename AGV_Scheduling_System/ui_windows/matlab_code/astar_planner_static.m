% === A* Planner (带转弯惩罚版) ===
function [path, cost] = astar_planner_static(map, start, goal)
    [rows, cols] = size(map);
    
    % --- 配置参数 ---
    turnPenalty = 2.0; % 转弯惩罚值 (值越大越喜欢走直线)
    
    if map(goal(1), goal(2)) == 1, path = []; cost = inf; return; end
    
    % 方向定义: 1:上, 2:下, 3:左, 4:右
    moves = [-1, 0; 1, 0; 0, -1; 0, 1]; 
    
    % OpenList 结构增加第5列: [f, g, r, c, last_dir]
    % last_dir: 0表示起点无方向，1-4表示从哪个方向来到(r,c)
    openList = [0, 0, start(1), start(2), 0]; 
    
    cameFrom = containers.Map('KeyType','double','ValueType','any');
    gScore = containers.Map('KeyType','double','ValueType','double');
    
    start_hash = start(1) + start(2)*10000;
    gScore(start_hash) = 0;
    
    path = []; cost = inf; found = false;
    
    while ~isempty(openList)
        % 取出 f 值最小的节点
        [~, idx] = min(openList(:, 1)); 
        current = openList(idx, :); 
        openList(idx, :) = [];
        
        c_r = current(3); 
        c_c = current(4); 
        c_g = current(2);
        c_dir = current(5); % 获取到达当前节点的方向
        
        % 到达终点
        if c_r == goal(1) && c_c == goal(2), found = true; cost = c_g; break; end
        
        for k = 1:4
            nr = c_r + moves(k, 1); 
            nc = c_c + moves(k, 2);
            
            % 越界或障碍物检查
            if nr<1 || nr>rows || nc<1 || nc>cols || map(nr, nc)==1, continue; end
            
            % --- 计算新的代价 (核心修改) ---
            step_cost = 1; % 基础移动代价
            
            % 如果不是起点(c_dir~=0) 且 新方向(k) 不等于 旧方向(c_dir)，则加惩罚
            if c_dir ~= 0 && c_dir ~= k
                step_cost = step_cost + turnPenalty;
            end
            
            tentative_g = c_g + step_cost; 
            n_hash = nr + nc*10000;
            
            % 如果找到了更优路径
            if ~isKey(gScore, n_hash) || tentative_g < gScore(n_hash)
                gScore(n_hash) = tentative_g;
                % 曼哈顿距离作为启发式
                h = abs(nr-goal(1)) + abs(nc-goal(2));
                f = tentative_g + h;
                
                % 将新节点加入 openList，并记录当前的移动方向 k 作为该节点的 last_dir
                openList = [openList; f, tentative_g, nr, nc, k]; %#ok<AGROW>
                cameFrom(n_hash) = [c_r, c_c];
            end
        end
    end
    
    % 路径回溯
    if found
        curr = goal;
        while true
            path = [curr; path]; %#ok<AGROW>
            if isequal(curr, start), break; end
            curr = cameFrom(curr(1) + curr(2)*10000);
        end
    end
end