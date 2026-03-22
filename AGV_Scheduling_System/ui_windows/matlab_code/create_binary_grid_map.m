% 1. 地图生成函数 (包含：目标位置解锁 & AGV区域互斥逻辑)
function gridMap = create_binary_grid_map(w, h, target_id)
    % =========================================================
    % 输入：w(宽), h(高), target_id(当前任务要去的目标ID)
    % 输出：gridMap (0=可行走, 1=障碍物)
    % =========================================================

    % 初始化一个全 0 矩阵 (0 代表白色/无障碍)
    % 尺寸设为 h+1, w+1 是为了容纳坐标 0 到 w/h 的所有点 (MATLAB索引从1开始)
    gridMap = zeros(h + 1, w + 1); 
    
    % === A. 固定障碍物 (墙壁、隔断、U型生产线骨架) ===
    % 定义矩形障碍列表 [x起点, y起点, 宽度, 高度]
    obstacles = [
        0, 0, 1, 51; 
        0, 0, 51, 1; 
        51,0,1,51; 
        0, 51, 52, 1; % 四周的边框围墙
        2, 32, 1, 17;   % 左上竖墙
        2, 21, 24, 1;   % 左中横墙
        2, 8, 24, 1;    % 左下横墙
        44, 9, 2, 19;  % 右侧竖墙
    ];

    % U型生产线的几何参数定义
    top_center = [44, 42];  % 上半圆弧的圆心
    bot_center = [44, 36];  % 下半圆弧的圆心
    r_in = 4;               % 内半径

    % 将 U型线的直线段部分追加到障碍物列表
    obstacles = [obstacles;
        16, 46, (top_center(1) - 16), 2;  % 上横梁
        (top_center(1) + r_in), bot_center(2), 2, (top_center(2) - bot_center(2)); % 右竖梁
        16, 30, (bot_center(1) - 16), 2;  % 下横梁
    ];

    % 遍历障碍物列表，将其填入地图矩阵
    for i = 1:size(obstacles, 1)
        gridMap = fill_rect(gridMap, obstacles(i,:)); % 调用辅助函数填充矩形
    end
    
    % --- 处理 U型线的圆弧部分 ---
    % 生成网格坐标矩阵，用于计算圆弧
    [X, Y] = meshgrid(0:w, 0:h);
    % 计算右上角圆弧障碍 (0度到90度)
    mask_top = check_arc_collision(X, Y, 43, 41, 4, 6, 0, 90);
    % 计算右下角圆弧障碍 (-90度到0度)
    mask_bot = check_arc_collision(X, Y, 43, 36, 4, 6, -90, 0);
    % 将计算出的弧形区域在地图上标记为 1 (障碍)
    gridMap(mask_top | mask_bot) = 1;
    
    % === B. 动态障碍：小配件区 (ID 1-12) ===
    % 定义布局参数
    lb_start_x = 3; box_w = 2; box_h = 2; % 左下仓库区参数
    u_start_x = 17;            % 中间U型区参数
    
    % 遍历 1 到 12 号小配件
    for i = 1:12
        % 【关键逻辑】如果当前 i 是目标 ID，跳过(不设为障碍)，让 AGV 可以进去
        if i == target_id, continue; end 
        
        % 1. 计算仓库位置坐标 (左下角区域)
        if i <= 6
            wx = lb_start_x + (i-1)*4; wy = 18; % 上排 (1-6)
        else
            wx = lb_start_x + (i-7)*4; wy = 10; % 下排 (7-12)
        end
        gridMap = fill_rect(gridMap, [wx, wy, box_w, box_h]); % 设为障碍
        
        % 2. 计算工位位置坐标 (中间U型区域)
        if i <= 6
            sx = u_start_x + (i-1)*5; sy = 43;  % 上排
        else
            sx = u_start_x + (i-7)*5; sy = 33;  % 下排
        end
        gridMap = fill_rect(gridMap, [sx, sy, box_w, box_h]); % 设为障碍
    end

    % === C. 动态障碍：大件/转向架/梁 (ID 13-16) ===
    % 定义大件尺寸参数
    rack_w = 3; rack_h = 3; 
    
    % 同步更新为分散式地图布局物理坐标 [X, Y]
    w_bases = [4, 42; 18, 4; 40, 23; 47, 11]; % 仓库取货基准
    s_bases = [40, 11; 4, 36; 5, 23; 47, 23]; % 工位送货基准
    
    % 遍历 13 到 16 号大件
    for i = 13:16
        % 【关键逻辑】如果是目标 ID，跳过(留白不做成障碍物)，让 AGV 可以进去
        if i == target_id, continue; end 
        
        idx = i - 12; % 映射为 1-4 的矩阵索引
        
        % 1. 仓库区域 (取货点)
        wh_x = w_bases(idx, 1);
        wh_y = w_bases(idx, 2);
        gridMap = fill_rect(gridMap, [wh_x, wh_y, rack_w, rack_h]); % 设为障碍
        
        % 2. 工位区域 (送货点)
        st_x = s_bases(idx, 1);
        st_y = s_bases(idx, 2);
        gridMap = fill_rect(gridMap, [st_x, st_y, rack_w, rack_h]); % 设为障碍
    end

    % === D. 【修复后】区域互斥逻辑 ===
    % 根据 target_id 判断当前任务，严格只封锁“非同类”的基地
    
    if target_id >= 1 && target_id <= 12
        % --- 托举式 AGV 任务 (ID 1-12) ---
        % 只封锁叉车 AGV 的专属区域，决不封锁自己
        gridMap = fill_rect(gridMap, [39, 2, 3, 3]); % 叉车充电桩
        gridMap = fill_rect(gridMap, [46, 2, 3, 3]); % 叉车车库
        
    elseif target_id >= 13 && target_id <= 16
        % --- 叉车式 AGV 任务 (ID 13-16) ---
        % 只封锁托举 AGV 的专属区域
        gridMap = fill_rect(gridMap, [2, 2, 2, 2]);  % 托举充电桩
        gridMap = fill_rect(gridMap, [6, 2, 2, 2]);  % 托举车库1
        gridMap = fill_rect(gridMap, [10, 2, 2, 2]); % 托举车库2
        
    elseif target_id == 17
        % --- 托举式执行充电 ---
        gridMap = fill_rect(gridMap, [39, 2, 3, 3]); % 封锁叉车充电桩
        gridMap = fill_rect(gridMap, [46, 2, 3, 3]); % 封锁叉车车库
        
    elseif target_id == 18
        % --- 叉车式执行充电 ---
        gridMap = fill_rect(gridMap, [2, 2, 2, 2]);  % 封锁托举充电桩
        gridMap = fill_rect(gridMap, [6, 2, 2, 2]);  % 封锁托举车库1
        gridMap = fill_rect(gridMap, [10, 2, 2, 2]); % 封锁托举车库2
    end

end

function map = fill_rect(map, rect)
    % 输入 map: 当前的栅格地图矩阵 (0是路, 1是墙)
    % 输入 rect: 一个1x4向量 [x起点, y起点, 宽度, 高度]
    
    % 1. 获取地图尺寸
    % size(map, 2) 是列数，对应物理世界的 宽度 (Width)
    w_map = size(map, 2); 
    % size(map, 1) 是行数，对应物理世界的 高度 (Height)
    h_map = size(map, 1);
    
    % 2. 计算 列索引 (Column Index) -> 对应 X 轴
    % rect(1) 是矩形的 x 起点。
    % floor() 是向下取整。
    % 【关键点】 +1 是因为 MATLAB 索引从 1 开始，而物理坐标通常从 0 开始。
    c_start = floor(rect(1)) + 1; 
    
    % rect(3) 是矩形的宽度。rect(1)+rect(3) 就是 x 终点。
    % ceil() 是向上取整，保证矩形边缘被完全覆盖。
    c_end = ceil(rect(1) + rect(3));
    
    % 3. 计算 行索引 (Row Index) -> 对应 Y 轴
    % rect(2) 是矩形的 y 起点。rect(4) 是高度。逻辑同上。
    r_start = floor(rect(2)) + 1; 
    r_end = ceil(rect(2) + rect(4));
    
    % 4. 边界检查 (Boundary Check) - 防止报错
    % max(1, ...) 确保索引最小是 1，防止出现 0 或负数索引。
    % min(w_map, ...) 确保索引不超过地图最大宽度。
    c_start = max(1, c_start); 
    c_end = min(w_map, c_end);
    
    % 对 Y 轴做同样的边界检查
    r_start = max(1, r_start); 
    r_end = min(h_map, r_end);
    
    % 5. 填充障碍物
    % 使用矩阵切片操作，将指定的矩形区域全部赋值为 1。
    map(r_start:r_end, c_start:c_end) = 1;
end

function mask = check_arc_collision(X, Y, cx, cy, r_in, r_out, ang_min, ang_max)
    % 输入 X, Y: 网格坐标矩阵 (由 meshgrid 生成)
    % 输入 cx, cy: 圆心的 x, y 坐标
    % 输入 r_in, r_out: 内半径, 外半径 (像甜甜圈的内圈和外圈)
    % 输入 ang_min, ang_max: 起始角度, 结束角度 (单位：度)
    
    % 1. 计算距离 (Distance)
    % 计算全图每个点 (X,Y) 到圆心 (cx,cy) 的欧几里得距离。
    % .^2 表示对矩阵每个元素平方。
    dist = sqrt((X - cx).^2 + (Y - cy).^2);
    
    % 2. 计算角度 (Angle)
    % 计算全图每个点相对于圆心的角度。
    % atan2d 返回的是角度值 (-180 到 180 度)，这比弧度更直观。
    angle = atan2d(Y - cy, X - cx);
    
    % 3. 距离筛选 (生成圆环)
    % 如果点的距离 >= 内径 且 <= 外径，则 mask_dist 对应位置为 1 (真)。
    % 这一步画出了一个完整的圆环。
    mask_dist = (dist >= r_in) & (dist <= r_out);
    
    % 4. 角度筛选 (切割圆环成扇形)
    if ang_min > ang_max
        % 特殊情况：跨越 ±180 度分界线
        % 例如：从 170度 到 -170度 (跨过了正左边的分界线)
        % 逻辑是：大于起点 OR 小于终点
        mask_ang = (angle >= ang_min) | (angle <= ang_max);
    else
        % 一般情况：例如从 0度 到 90度
        % 逻辑是：大于起点 AND 小于终点
        mask_ang = (angle >= ang_min) & (angle <= ang_max); 
    end
    
    % 5. 合并结果
    % 一个点必须既在圆环内 (距离满足)，又在扇形内 (角度满足)，才算障碍。
    mask = mask_dist & mask_ang;
end