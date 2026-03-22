function verify_conflict_resolution_with_3D()
    % =========================================================================
    % 极简多 AGV 冲突消解验证仿真 (带 X-Y-T 三维时空投影图 - 完美修复版)
    % =========================================================================
    clc; clear; close all;
    
    global mapW mapH;
    mapW = 30; mapH = 30;
    
    disp('====================================================');
    disp('>> 仿真开始：经典相向冲突验证测试');
    disp('====================================================');
    
    % --- 1. 初始化 AGV 参数 ---
    AGVs(1).id = 1;
    AGVs(1).pos = [15, 1];          % 起点
    AGVs(1).target = [15, 30];      % 终点
    AGVs(1).battery = 73;           % 电量 73%
    AGVs(1).rem_time = 500;         % 剩余时间
    AGVs(1).status = 'Moving_Pick'; % 状态: 取货
    AGVs(1).step_dur = 2;           % 两次走一格 (快车)
    
    AGVs(2).id = 2;
    AGVs(2).pos = [15, 30];         % 起点
    AGVs(2).target = [15, 1];       % 终点
    AGVs(2).battery = 86;           % 电量 86%
    AGVs(2).rem_time = 230;         % 剩余时间
    AGVs(2).status = 'Moving_Drop'; % 状态: 送货
    AGVs(2).step_dur = 3;           % 三次走一格 (慢车)
    
    for k = 1:2
        AGVs(k).path = [];
        AGVs(k).path_idx = 1;
        AGVs(k).move_timer = 0;
        AGVs(k).finished = false;
        AGVs(k).path = simple_astar(AGVs(k).pos, AGVs(k).target, zeros(mapH, mapW));
    end
    
    % 用于记录时空轨迹的数组
    traj_1 = []; 
    traj_2 = [];
    
    % --- 2. 初始化 2D 可视化界面 ---
    fig_2d = figure('Name', '2D 实时防碰撞动画', 'Position', [50, 100, 600, 600], 'Color', 'w');
    hold on; grid on; axis equal;
    axis([0.5, mapW+0.5, 0.5, mapH+0.5]);
    set(gca, 'YDir', 'reverse');
    title('AGV 实时冲突动态消解 (2D 俯视图)', 'FontSize', 14);
    
    colors = lines(2);
    p1 = plot(AGVs(1).pos(2), AGVs(1).pos(1), 's', 'MarkerSize', 15, 'MarkerFaceColor', colors(1,:), 'MarkerEdgeColor', 'k');
    p2 = plot(AGVs(2).pos(2), AGVs(2).pos(1), 'o', 'MarkerSize', 15, 'MarkerFaceColor', colors(2,:), 'MarkerEdgeColor', 'k');
    line1 = plot(AGVs(1).path(:,2), AGVs(1).path(:,1), '--', 'Color', colors(1,:), 'LineWidth', 1.5);
    line2 = plot(AGVs(2).path(:,2), AGVs(2).path(:,1), '--', 'Color', colors(2,:), 'LineWidth', 1.5);
    legend([p1, p2], {'AGV 1 (快车)', 'AGV 2 (慢车)'}, 'Location', 'northeast');
    
    % --- 3. 仿真主循环 ---
    t = 0;
    while ~(AGVs(1).finished && AGVs(2).finished) && t < 300
        t = t + 1;
        
        for k = 1:2
            if AGVs(k).finished
                continue; 
            end
            
            if AGVs(k).move_timer > 0
                AGVs(k).move_timer = AGVs(k).move_timer - 1;
                continue;
            end
            
            if AGVs(k).path_idx >= size(AGVs(k).path, 1)
                AGVs(k).finished = true;
                fprintf('[T=%d] AGV-%d 到达终点！\n', t, k);
                continue;
            end
            
            next_node = AGVs(k).path(AGVs(k).path_idx + 1, :);
            other_id = 3 - k;
            other_pos = AGVs(other_id).pos;
            
            if ~AGVs(other_id).finished && AGVs(other_id).path_idx < size(AGVs(other_id).path, 1)
                other_next = AGVs(other_id).path(AGVs(other_id).path_idx + 1, :);
            else
                other_next = other_pos;
            end
            
            % =========================================================
            % [核心修复区]：单步前瞻与冲突检测
            is_conflict = false;
            if isequal(next_node, other_pos) && isequal(other_next, AGVs(k).pos)
                is_conflict = true;
            elseif isequal(next_node, other_pos) || isequal(next_node, other_next)
                is_conflict = true;
            end
            
            will_move = true; % 物理移动允许标志位
            
            if is_conflict
                fprintf('\n[T=%d] 🚨 探测到物理干涉 (AGV-%d -> AGV-%d)\n', t, k, other_id);
                score_self = calculate_ahp_score(AGVs(k));
                score_other = calculate_ahp_score(AGVs(other_id));
                
                % 加入 ID 作为平局决胜条件 (Tie-breaker)
                if score_self < score_other || (score_self == score_other && k > other_id)
                    fprintf('   -> ⚖️ 判决: AGV-%d 优先级低，执行重规划绕行！\n', k);
                    temp_map = zeros(mapH, mapW);
                    temp_map(other_pos(1), other_pos(2)) = 1;
                    temp_map(other_next(1), other_next(2)) = 1;
                    
                    new_path = simple_astar(AGVs(k).pos, AGVs(k).target, temp_map);
                    
                    if ~isempty(new_path)
                        AGVs(k).path = new_path;
                        AGVs(k).path_idx = 1;
                        next_node = AGVs(k).path(2, :);
                        if k == 1, set(line1, 'XData', new_path(:,2), 'YData', new_path(:,1));
                        else, set(line2, 'XData', new_path(:,2), 'YData', new_path(:,1)); end
                        % 绕路成功，本回合允许按新路线移动
                    else
                        % 绕行失败，取消本次移动，原地死等
                        fprintf('   -> ❌ 无路可绕，原地死等。\n');
                        will_move = false; 
                        AGVs(k).move_timer = 2; 
                    end
                else
                    % 高优先级车取消本次移动，原地停滞鸣笛，等待对方驶离
                    fprintf('   -> ⚖️ 判决: AGV-%d 优先级高，原地鸣笛等待对方让路。\n', k);
                    will_move = false; 
                    AGVs(k).move_timer = 1; 
                end
            end
            
            % 只有被允许移动时，才推进坐标和路径索引
            if will_move
                AGVs(k).pos = next_node;
                AGVs(k).path_idx = AGVs(k).path_idx + 1;
                AGVs(k).move_timer = AGVs(k).step_dur;
            end
            % =========================================================
        end
        
        % 记录每个时间步的时空坐标 X(列), Y(行), T
        if ~AGVs(1).finished
            traj_1 = [traj_1; AGVs(1).pos(2), AGVs(1).pos(1), t];
        else
            traj_1 = [traj_1; AGVs(1).target(2), AGVs(1).target(1), t]; % 到达终点后继续在原位置记录时间流逝
        end
        
        if ~AGVs(2).finished
            traj_2 = [traj_2; AGVs(2).pos(2), AGVs(2).pos(1), t];
        else
            traj_2 = [traj_2; AGVs(2).target(2), AGVs(2).target(1), t];
        end
        
        % 更新动画
        set(p1, 'XData', AGVs(1).pos(2), 'YData', AGVs(1).pos(1));
        set(p2, 'XData', AGVs(2).pos(2), 'YData', AGVs(2).pos(1));
        drawnow;
    end
    disp('====================================================');
    disp('>> 仿真结束，准备绘制 3D 时空轨迹图...');
    
    % --- 4. 绘制符合高质量学术标准的 X-Y-T 时空螺旋图 ---
    fig_3d = figure('Name', '相向冲突消解后路径关系图', 'Position', [700, 100, 700, 700], 'Color', 'w');
    hold on; grid on;
    view(-40, 25); % 调整为最佳的倾斜俯视透角
    
    % 定义纯正的学术配色 (亮绿与橙色)
    color_agv1 = [0.1, 0.9, 0.1]; % 亮绿 (快车/绕行)
    color_agv2 = [1.0, 0.5, 0.1]; % 橙色 (慢车/直行)
    
    % 绘制 AGV 1 的 3D 时空实线
    p1 = plot3(traj_1(:,1), traj_1(:,2), traj_1(:,3), '-', ...
        'Color', color_agv1, 'LineWidth', 2.5, 'DisplayName', 'AGV1');
    
    % 绘制 AGV 2 的 3D 时空实线
    p2 = plot3(traj_2(:,1), traj_2(:,2), traj_2(:,3), '-', ...
        'Color', color_agv2, 'LineWidth', 2.5, 'DisplayName', 'AGV2');
    
    % 绘制底部的 2D 空间投影虚线 (将 Z 轴强制归零)
    plot3(traj_1(:,1), traj_1(:,2), zeros(size(traj_1(:,3))), '--', ...
        'Color', color_agv1, 'LineWidth', 1.5, 'HandleVisibility', 'off');
    plot3(traj_2(:,1), traj_2(:,2), zeros(size(traj_2(:,3))), '--', ...
        'Color', color_agv2, 'LineWidth', 1.5, 'HandleVisibility', 'off');
    
    % 坐标轴范围与方向
    xlim([1, 30]); 
    ylim([1, 30]); 
    zlim([0, max(t) + 10]);
    set(gca, 'YDir', 'reverse'); 
    set(gca, 'XTick', 0:5:30, 'YTick', 0:5:30, 'ZTick', 0:20:max(t)+10);
    
    % 全局字体与边框设置 (学术标配)
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 12);
    set(gca, 'Box', 'on', 'LineWidth', 1.0); 
    set(gca, 'GridLineStyle', '-', 'GridColor', [0.7 0.7 0.7], 'GridAlpha', 0.4); 
    
    % 坐标轴标签 (LaTeX 斜体规范)
    xlabel('\it x', 'FontSize', 16, 'FontWeight', 'bold');
    ylabel('\it y', 'FontSize', 16, 'FontWeight', 'bold');
    zlabel('\it t', 'FontSize', 16, 'FontWeight', 'bold', 'Rotation', 0, 'HorizontalAlignment', 'right');
    
    % 图例设置
    lgd = legend([p1, p2], 'Location', 'northeast');
    set(lgd, 'FontName', 'Times New Roman', 'FontSize', 11, 'Box', 'on');
    
    rotate3d on;
    disp('>> [完成] 3D 时空图已生成，可直接导出放入论文。');
end

% =========================================================================
% 辅助函数 1：AHP 动态优先级计算
% =========================================================================
function score = calculate_ahp_score(agv)
    w = [0.6370, 0.1047, 0.2583]; 
    s_status = 0;
    if strcmp(agv.status, 'Moving_Drop'), s_status = 0.7; 
    elseif strcmp(agv.status, 'Moving_Pick'), s_status = 0.4; 
    end
    s_battery = (100 - agv.battery) / 100.0;
    s_time = max(0, 1 - (agv.rem_time / 1000));
    score = w(1)*s_status + w(2)*s_battery + w(3)*s_time;
end

% =========================================================================
% 辅助函数 2：极简二维 A* 路径规划算法
% =========================================================================
function path = simple_astar(start_pos, goal_pos, obstacle_map)
    [mapH, mapW] = size(obstacle_map);
    dirs = [-1 0; 1 0; 0 -1; 0 1];
    openList = start_pos;
    gScore = inf(mapH, mapW); gScore(start_pos(1), start_pos(2)) = 0;
    fScore = inf(mapH, mapW); fScore(start_pos(1), start_pos(2)) = sum(abs(start_pos - goal_pos));
    cameFrom_r = zeros(mapH, mapW); cameFrom_c = zeros(mapH, mapW);
    
    while ~isempty(openList)
        [~, min_idx] = min(fScore(sub2ind([mapH, mapW], openList(:,1), openList(:,2))));
        curr = openList(min_idx, :);
        if isequal(curr, goal_pos)
            path = curr;
            while cameFrom_r(curr(1), curr(2)) ~= 0
                pr = cameFrom_r(curr(1), curr(2)); pc = cameFrom_c(curr(1), curr(2));
                curr = [pr, pc]; path = [curr; path]; %#ok<AGROW>
            end
            return;
        end
        openList(min_idx, :) = [];
        for i = 1:4
            neighbor = curr + dirs(i, :); nr = neighbor(1); nc = neighbor(2);
            if nr >= 1 && nr <= mapH && nc >= 1 && nc <= mapW && obstacle_map(nr, nc) == 0
                tentative_gScore = gScore(curr(1), curr(2)) + 1;
                if tentative_gScore < gScore(nr, nc)
                    cameFrom_r(nr, nc) = curr(1); cameFrom_c(nr, nc) = curr(2);
                    gScore(nr, nc) = tentative_gScore; fScore(nr, nc) = tentative_gScore + sum(abs(neighbor - goal_pos));
                    if ~ismember(neighbor, openList, 'rows'), openList = [openList; neighbor]; %#ok<AGROW>
                    end
                end
            end
        end
    end
    path = []; 
end