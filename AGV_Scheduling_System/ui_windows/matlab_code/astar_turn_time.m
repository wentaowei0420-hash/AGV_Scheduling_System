function [path, cost] = astar_turn_time(map, start, goal, turnPenalty, occupy, Tmax)
    % 带转向惩罚的时空A*算法
    % 输入：
    %   map, start, goal, turnPenalty, occupy, Tmax
    % 输出：
    %   path: [N×3] 矩阵 [行,列,时刻] （起点时刻为1）
    %   cost: 总代价

    [rows, cols] = size(map);
    % 方向定义：1上(-1,0), 2下(1,0), 3左(0,-1), 4右(0,1)
    dirs = [-1, 0; 1, 0; 0, -1; 0, 1];

    % 状态空间 (r,c,t,dir)，dir=0表示起点，dir=1~4对应四个方向
    % 将dir映射到索引 dir+1，因此维度大小为5
    g = inf(rows, cols, Tmax, 5);   % 到达每个状态的最小代价
    f = inf(rows, cols, Tmax, 5);   % 估计总代价

    % 前驱记录
    prev_r = zeros(rows, cols, Tmax, 5);
    prev_c = zeros(rows, cols, Tmax, 5);
    prev_t = zeros(rows, cols, Tmax, 5);
    prev_dir = zeros(rows, cols, Tmax, 5);

    % 起点状态：时刻1，方向0
    start_dir = 0;
    start_dir_idx = start_dir + 1;
    g(start(1), start(2), 1, start_dir_idx) = 0;
    f(start(1), start(2), 1, start_dir_idx) = heuristic(start, goal);

    % openSet 管理：每行 [r,c,t,dir]，同时记录对应f值
    openSet = [start(1), start(2), 1, start_dir];
    openF = f(start(1), start(2), 1, start_dir_idx);
    inOpen = false(rows, cols, Tmax, 5);
    inOpen(start(1), start(2), 1, start_dir_idx) = true;

    while ~isempty(openSet)
        % 找出openSet中f最小的节点
        [~, idx] = min(openF);
        r = openSet(idx, 1);
        c = openSet(idx, 2);
        t = openSet(idx, 3);
        dir = openSet(idx, 4);
        dir_idx = dir + 1;

        % 到达目标则回溯路径
        if r == goal(1) && c == goal(2)
            path = [];
            while ~(r == start(1) && c == start(2) && t == 1 && dir == 0)
                path = [r, c, t; path];
                r2 = prev_r(r, c, t, dir_idx);
                c2 = prev_c(r, c, t, dir_idx);
                t2 = prev_t(r, c, t, dir_idx);
                dir2 = prev_dir(r, c, t, dir_idx);
                r = r2; c = c2; t = t2; dir = dir2;
                dir_idx = dir + 1;
            end
            path = [start(1), start(2), 1; path];
            cost = g(goal(1), goal(2), t, dir_idx);
            return;
        end

        % 从openSet中移除当前节点
        openSet(idx, :) = [];
        openF(idx) = [];
        inOpen(r, c, t, dir_idx) = false;

        % 扩展移动邻居（四个方向）
        for d = 1:4
            nr = r + dirs(d, 1);
            nc = c + dirs(d, 2);
            nt = t + 1;
            if nt > Tmax, continue; end
            % 边界和障碍检查
            if nr < 1 || nr > rows || nc < 1 || nc > cols || map(nr, nc) == 1
                continue;
            end
            % 时空占用检查
            if occupy(nr, nc, nt)
                continue;
            end

            % 计算新代价：移动一步代价1
            new_g = g(r, c, t, dir_idx) + 1;
            % 转弯惩罚：如果当前节点不是起点且方向改变
            if dir ~= 0 && dir ~= d
                new_g = new_g + turnPenalty;
            end

            new_dir = d;
            new_dir_idx = new_dir + 1;
            if new_g < g(nr, nc, nt, new_dir_idx)
                % 更新最优值
                g(nr, nc, nt, new_dir_idx) = new_g;
                f(nr, nc, nt, new_dir_idx) = new_g + heuristic([nr, nc], goal);
                prev_r(nr, nc, nt, new_dir_idx) = r;
                prev_c(nr, nc, nt, new_dir_idx) = c;
                prev_t(nr, nc, nt, new_dir_idx) = t;
                prev_dir(nr, nc, nt, new_dir_idx) = dir;

                if ~inOpen(nr, nc, nt, new_dir_idx)
                    % 加入openSet
                    openSet = [openSet; nr, nc, nt, new_dir];
                    openF = [openF; f(nr, nc, nt, new_dir_idx)];
                    inOpen(nr, nc, nt, new_dir_idx) = true;
                else
                    % 已在openSet中，更新其f值
                    row = find(openSet(:,1)==nr & openSet(:,2)==nc & ...
                               openSet(:,3)==nt & openSet(:,4)==new_dir, 1);
                    if ~isempty(row)
                        openF(row) = f(nr, nc, nt, new_dir_idx);
                    end
                end
            end
        end

        % 扩展等待动作（原地停留一单位时间）
        nt = t + 1;
        if nt <= Tmax && ~occupy(r, c, nt)
            new_g = g(r, c, t, dir_idx) + 1;  % 等待代价
            new_dir = dir;  % 方向不变
            new_dir_idx = new_dir + 1;
            if new_g < g(r, c, nt, new_dir_idx)
                g(r, c, nt, new_dir_idx) = new_g;
                f(r, c, nt, new_dir_idx) = new_g + heuristic([r, c], goal);
                prev_r(r, c, nt, new_dir_idx) = r;
                prev_c(r, c, nt, new_dir_idx) = c;
                prev_t(r, c, nt, new_dir_idx) = t;
                prev_dir(r, c, nt, new_dir_idx) = dir;

                if ~inOpen(r, c, nt, new_dir_idx)
                    openSet = [openSet; r, c, nt, new_dir];
                    openF = [openF; f(r, c, nt, new_dir_idx)];
                    inOpen(r, c, nt, new_dir_idx) = true;
                else
                    row = find(openSet(:,1)==r & openSet(:,2)==c & ...
                               openSet(:,3)==nt & openSet(:,4)==new_dir, 1);
                    if ~isempty(row)
                        openF(row) = f(r, c, nt, new_dir_idx);
                    end
                end
            end
        end
    end

    % 无可行路径
    path = [];
    cost = inf;
end

% ------------------------------------------------------------------------
function h = heuristic(a, b)
    % 曼哈顿距离作为启发式
    h = abs(a(1)-b(1)) + abs(a(2)-b(2));
end