function [pick, drop] = get_coords_simple(target_id, current_pos)
    % 输入: 
    %   target_id   - 任务工位ID (1-12为小件, 13-16为大件)
    %   current_pos - AGV当前坐标 [x, y]
    % 输出:
    %   pick        - 曼哈顿距离最短的取货点 [x, y]
    %   drop        - 曼哈顿距离最短的送货点 [x, y]

    if target_id <= 12
        % --- 小件区动态寻优逻辑 (ID 1-12, 2x2 区域) ---
        if target_id <= 6
            offset = target_id - 1;
            % 左下仓库基准 (X起始:3, 间隔:4, Y:18)
            pick_base = [3 + offset * 4, 18];
            % 中间U型工位基准 (X起始:17, 间隔:5, Y:43)
            drop_base = [17 + offset * 5, 43];
        else
            offset = target_id - 7;
            % 左下仓库基准 (X起始:3, 间隔:4, Y:10)
            pick_base = [3 + offset * 4, 10];
            % 中间U型工位基准 (X起始:17, 间隔:5, Y:33)
            drop_base = [17 + offset * 5, 33];
        end
        
        % 在 2x2 区域内寻找曼哈顿距离最短的点
        pick = find_nearest_grid_custom(pick_base, current_pos, 2);
        drop = find_nearest_grid_custom(drop_base, pick, 2);
        
    else
        % --- 大件区动态寻优逻辑 (ID 13-16, 3x3 区域) ---
        % 同步更新为分散式地图布局坐标
        w_bases = [4, 42; 18, 4; 40, 23; 47, 11]; % 仓库取货基准
        s_bases = [40, 11; 4, 36; 5, 23; 47, 23]; % 工位送货基准
        
        idx = target_id - 12; % 映射到 bases 矩阵索引 (1-4)
        pick_base = w_bases(idx, :); 
        drop_base = s_bases(idx, :); 
        
        % 在 3x3 区域内寻找曼哈顿距离最短的取货点
        pick = find_nearest_grid_custom(pick_base, current_pos, 3);
        % 根据取货后的位置寻找曼哈顿距离最短的送货点
        drop = find_nearest_grid_custom(drop_base, pick, 3);
    end
end

function best_pt = find_nearest_grid_custom(base_xy, reference_pos, size_n)

    % 在 n x n 区域内寻找曼哈顿距离最短的栅格点
    min_dist = inf;
    best_pt = base_xy;
    
    for dx = 0:size_n-1
        for dy = 0:size_n-1
            test_pt = [base_xy(1) + dx, base_xy(2) + dy];
            % 计算曼哈顿距离: |x1-x2| + |y1-y2|
            dist = sum(abs(test_pt - reference_pos));
            
            if dist < min_dist
                min_dist = dist;
                best_pt = test_pt;
            end
        end
    end
end