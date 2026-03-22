function [path, path_cost, expanded_nodes] = astar_planner_time_window(map, start, goal, reservation_table, start_time, max_time_steps, move_duration)
    % =========================================================================
    % 改进版 A* 算法：支持变速移动 (move_duration) + 状态携带
    % =========================================================================
    % 输入增加: move_duration (整数，表示走一格需要几个时间步)
    
    if nargin < 7, move_duration = 1; end % 默认耗时 1
    
    [rows, cols] = size(map);
    % 动作：上 下 左 右 (前4个是移动), 等待(第5个)
    moves = [-1, 0; 1, 0; 0, -1; 0, 1; 0, 0]; 
    
    % 优先队列: [f, g, r, c, t, dir_r, dir_c]
    openList = [0, 0, start(1), start(2), start_time, 0, 0];
    
    % CameFrom: Key=Hash, Val=[parent_r, parent_c, parent_t]
    cameFrom = containers.Map('KeyType','double','ValueType','any');
    gScore = containers.Map('KeyType','double','ValueType','double');
    
    start_hash = get_hash(start(1), start(2), start_time);
    gScore(start_hash) = 0;
    
    path = []; path_cost = Inf; expanded_nodes = 0; found = false;
    end_node_state = [];
    
    while ~isempty(openList)
        % 取最小值
        [~, idx] = min(openList(:, 1));
        current = openList(idx, :);
        openList(idx, :) = []; 
        
        c_r = current(3); c_c = current(4); c_t = current(5);
        c_dr = current(6); c_dc = current(7);
        c_g = current(2);
        
        expanded_nodes = expanded_nodes + 1;
        
        % 终点判断
        if c_r == goal(1) && c_c == goal(2)
            found = true;
            end_node_state = [c_r, c_c, c_t];
            path_cost = c_g;
            break;
        end
        
        % 超时剪枝
        if c_t - start_time > max_time_steps, continue; end
        
        for k = 1:5
            is_wait = (k == 5);
            
            % 计算新坐标
            n_r = c_r + moves(k, 1);
            n_c = c_c + moves(k, 2);
            
            % 计算新时间：如果是移动，增加 move_duration；如果是等待，增加 1
            if is_wait
                step_cost = 1;
                dur = 1;
            else
                step_cost = 1.0; % 距离代价
                dur = move_duration; % 时间流逝代价
            end
            n_t = c_t + dur;
            
            % 1. 越界与静态障碍检查
            if n_r < 1 || n_r > rows || n_c < 1 || n_c > cols || map(n_r, n_c) == 1
                continue;
            end
            
            % 2. 动态障碍检查 (检查整个移动过程的时间段)
            % 如果走得慢(dur>1)，需要确保这段时间内目标点一直是空的
            collision = false;
            for dt = 1:dur
                check_t = c_t + dt;
                if is_occupied(reservation_table, n_r, n_c, check_t)
                    collision = true; break;
                end
            end
            if collision, continue; end
            
            % 3. 转弯惩罚
            new_dr = moves(k,1); new_dc = moves(k,2);
            if ~is_wait && (new_dr ~= c_dr || new_dc ~= c_dc) && (c_dr~=0 || c_dc~=0)
                step_cost = step_cost + 2.0; 
            end
            
            tentative_g = c_g + step_cost;
            n_hash = get_hash(n_r, n_c, n_t);
            
            if ~isKey(gScore, n_hash) || tentative_g < gScore(n_hash)
                gScore(n_hash) = tentative_g;
                h = abs(n_r - goal(1)) + abs(n_c - goal(2)); 
                f = tentative_g + h;
                
                openList = [openList; f, tentative_g, n_r, n_c, n_t, new_dr, new_dc]; %#ok<AGROW>
                cameFrom(n_hash) = [c_r, c_c, c_t];
            end
        end
    end
    
    % 回溯路径
    if found
        curr = end_node_state;
        while true
            % path 格式：[row, col, time]
            path = [curr; path]; %#ok<AGROW>
            if curr(1) == start(1) && curr(2) == start(2) && curr(3) == start_time
                break; 
            end
            key = get_hash(curr(1), curr(2), curr(3));
            if isKey(cameFrom, key)
                curr = cameFrom(key);
            else
                break; 
            end
        end
    end
end

function h = get_hash(r, c, t)
    h = r + c * 10000 + t * 100000000;
end

function occ = is_occupied(tbl, r, c, t)
    [~, ~, T] = size(tbl);
    if t > T, occ = false; else, occ = tbl(r,c,t) == 1; end
end