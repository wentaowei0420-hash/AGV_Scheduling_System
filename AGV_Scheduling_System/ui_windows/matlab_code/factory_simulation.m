function factory_simulation()
    clc; 
    clear; 
    close all;

    % 1. 定义地图尺寸
    mapW = 60; 
    mapH = 50;
    target_station_id = 15;  % <--- 修改这里试试，比如改成 1, 8, 12
    % 2. 生成二值化地图 (机器眼中的世界)
    % 0 = 路 (安全), 1 = 墙 (撞车)
    binaryMap = create_binary_grid_map(mapW, mapH, target_station_id);
    % 3. 定义关键航点 (预设大概位置)
    % 格式: [y, x]
    % 【用户输入】你想去几号工位？ (1-12)
    start_pos = [3, 11];    % 起点：右下角空地
    [pickup_pos, dropoff_pos] = get_task_coordinates(target_station_id);

    % 5. 运行 A* 算法
    disp('正在规划路径 1: 车库 -> 仓库...');
    [path1, ~, ~, ~] = astar_planner_turn(binaryMap, start_pos, pickup_pos, 0.7);
    disp('正在规划路径 2: 仓库 -> 工位...');
    [path2, ~, ~, ~] = astar_planner_turn(binaryMap, pickup_pos, dropoff_pos, 0.7);
    disp('正在规划路径 3: 工位 -> 车库...');
    [path3, ~, ~, ~] = astar_planner_turn(binaryMap, dropoff_pos, start_pos, 0.7);
    % 6. 绘制精美可视化地图
    generate_beautiful_factory_map();
    % 7. 绘制并动画演示路径
    if ~isempty(path1) && ~isempty(path2) && ~isempty(path3)
        % --- A. 绘制关键点 (修改为栅格方块) ---
        % 注意：rectangle 的 Position 格式是 [x, y, w, h]
        % 因为坐标是以1为起点的网格索引，转为笛卡尔坐标画图时，左下角要是 x-1, y-1
        
        % 1. 起点 (绿色方块)
        rectangle('Position', [start_pos(2)-1, start_pos(1)-1, 1, 1], ...
                  'FaceColor', [0 0.8 0], 'EdgeColor', 'k', 'LineWidth', 1);
        text(start_pos(2)-0.5, start_pos(1)-0.5, '起', ...
             'Color', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        
        % 2. 取货点 (蓝色方块)
        rectangle('Position', [pickup_pos(2)-1, pickup_pos(1)-1, 1, 1], ...
                  'FaceColor', [0 0.4 1], 'EdgeColor', 'k', 'LineWidth', 1);
        text(pickup_pos(2)-0.5, pickup_pos(1)-0.5, '取', ...
             'Color', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        
        % 3. 送货点 (红色方块)
        rectangle('Position', [dropoff_pos(2)-1, dropoff_pos(1)-1, 1, 1], ...
                  'FaceColor', [1 0.2 0.2], 'EdgeColor', 'k', 'LineWidth', 1);
        text(dropoff_pos(2)-0.5, dropoff_pos(1)-0.5, '送', ...
             'Color', 'w', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        
        % --- B. 绘制路径线 (保持不变) ---
        % 为了好看，路径线稍微抬高0.5，让它穿过方格的中心
        plot(path1(:,2)-0.5, path1(:,1)-0.5, 'Color', [0.2 0.8 0.2], 'LineWidth', 2, 'LineStyle', '--');
        plot(path2(:,2)-0.5, path2(:,1)-0.5, 'Color', [1 0.6 0], 'LineWidth', 2, 'LineStyle', '--');
        plot(path3(:,2)-0.5, path3(:,1)-0.5, 'Color', [1 0.6 0], 'LineWidth', 2, 'LineStyle', '--');
        % --- C. 动画演示 ---
        animate_agv([path1; path2;path3]);
    else
        msgbox('依然无法找到路径，可能是因为起点被障碍物完全包围了。', '错误');
    end
end


