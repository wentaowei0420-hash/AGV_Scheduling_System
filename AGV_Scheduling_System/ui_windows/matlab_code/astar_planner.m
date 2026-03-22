function [path, gScore_goal, turn_count, expanded_nodes, path_length, gScore_matrix] = astar_planner(map, start, goal,w)
    % A*路径规划函数
    % 输入：
    %   map    : 二维栅格地图 (0:自由, 1:障碍)
    %   start  : 起点坐标 [行, 列]
    %   goal   : 终点坐标 [行, 列]
    % 输出：
    %   path          : 路径点列表，每行为 [行, 列]
    %   gScore_goal   : 从起点到终点的路径长度
    %   turn_count    : 路径中的转弯次数（方向变化次数）
    %   expanded_nodes: 搜索过程中扩展的节点总数
    %   path_length   : 最终路径包含的栅格总数 % <--- 【新增说明】
    
    % 获取地图尺寸
    mapSize = size(map);
    
    % 初始化A*数据结构
    openSet = start;
    cameFrom = zeros(mapSize(1), mapSize(2), 2);
    gScore = inf(mapSize);
    gScore(start(1), start(2)) = 0;
    
    fScore = inf(mapSize);
    fScore(start(1), start(2)) = heuristic(start, goal);
    
    % 四方向移动
    directions = [-1, 0; 1, 0; 0, -1; 0, 1];
    moveCost = [1, 1, 1, 1];
    
    pathFound = false;
    expanded_nodes = 0;  % 新增：扩展节点计数器
    while ~isempty(openSet)
        % 从openSet中找到fScore最小的节点
        [~, currentIdx] = min(fScore(openSet(:,1) + (openSet(:,2)-1)*mapSize(1)));
        current = openSet(currentIdx, :);
        
        % 每取出一个节点进行扩展，计数器加1
        expanded_nodes = expanded_nodes + 1;
        
        if isequal(current, goal)
            pathFound = true;
            break;
        end
        
        openSet(currentIdx, :) = [];
        
        for d = 1:size(directions, 1)
            neighbor = current + directions(d, :);
            if neighbor(1) < 1 || neighbor(1) > mapSize(1) || ...
               neighbor(2) < 1 || neighbor(2) > mapSize(2)
                continue;
            end
            if map(neighbor(1), neighbor(2)) == 1
                continue;
            end
            
            tentative_gScore = gScore(current(1), current(2)) + moveCost(d);
            if tentative_gScore < gScore(neighbor(1), neighbor(2))
                cameFrom(neighbor(1), neighbor(2), :) = [current(1), current(2)];
                gScore(neighbor(1), neighbor(2)) = tentative_gScore;
                fScore(neighbor(1), neighbor(2)) = tentative_gScore + w*heuristic(neighbor, goal);
                
                if ~ismember(neighbor, openSet, 'rows')
                    openSet = [openSet; neighbor];
                end
            end
        end
    end
    
    if pathFound
        % 重构路径
        path = goal;
        while ~isequal(path(1,:), start)
            parent = squeeze(cameFrom(path(1,1), path(1,2), :))';
            path = [parent; path];
        end
        gScore_goal = gScore(goal(1), goal(2));
        
        path_length = size(path, 1);
        
        % 统计转弯次数
        turn_count = 0;
        if size(path, 1) > 2
            prev_dir = path(2, :) - path(1, :);
            for i = 3:size(path, 1)
                curr_dir = path(i, :) - path(i-1, :);
                if ~isequal(curr_dir, prev_dir)
                    turn_count = turn_count + 1;
                end
                prev_dir = curr_dir;
            end
        end
    else
        path = [];
        gScore_goal = inf;
        turn_count = 0;
        path_length = 0; % <--- 【新增：未找到路径时，栅格数为0】
    end
    % expanded_nodes 已在循环中累计，无需额外处理
    % 直接输出代价矩阵供热力图渲染
    gScore_matrix = gScore;
end

function h = heuristic(a, b)
    % 曼哈顿距离
    h = abs(b(1)-a(1)) + abs(b(2)-a(2));
end