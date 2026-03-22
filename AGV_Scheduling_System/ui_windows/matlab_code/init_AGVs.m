function [AGVs, props, path_colors] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax)
    % 初始化 AGV 结构体数组及其图形对象 (多任务队列适配版)
    
    AGVs = struct([]);
    path_colors = lines(num_agvs);
    
    props(1).charge_stations = [
        xy2rc([2, 2]);  % 左上角充电桩
        xy2rc([2, 3]);  % 右上角充电桩
        xy2rc([3, 2]);  % 左下角充电桩
        xy2rc([3, 3])   % 右下角充电桩
    ];
    props(2).charge = xy2rc([39, 2]);  % 类型 2 AGV 的充电桩位置
    
    for k = 1:num_agvs
        % --- 基础属性字段 ---
        AGVs(k).id = k;                                
        AGVs(k).type = agv_types(k);                    
        AGVs(k).pos = depots(k, :);                     
        AGVs(k).vis_pos = depots(k, :);                 
        AGVs(k).battery = agv_params(k).battery_current; 
        AGVs(k).status = 'Idle';                         
        AGVs(k).tasks = agv_schedules{k};                
        AGVs(k).path = [];                               
        AGVs(k).path_idx = 1;                             
        AGVs(k).target_node = [];                         
        AGVs(k).wait_timer = 0;                           
        AGVs(k).load = 0;                                 
        AGVs(k).step_dur = max(1, round(6.0 / agv_params(k).speed)); 
        AGVs(k).move_timer = 0;                           
        AGVs(k).home_pos = depots(k, :);                  
        
        % 【修改区】：多任务批处理与转弯统计相关的新增字段初始化
        AGVs(k).payload_weight = 0;         % 当前实时载重
        AGVs(k).pick_queue = [];            % 取货任务队列
        AGVs(k).drop_queue = [];            % 卸货任务队列
        AGVs(k).active_task_id = 0;         % 当前正在执行的子任务ID
        AGVs(k).interrupted_status = '';    % 记忆断电前的状态
        AGVs(k).yield_resume_status = '';   % temporary resume state after yielding
        AGVs(k).total_turns = 0;            % 转弯统计
        AGVs(k).last_dir = [0, 0];          % 运动矢量记忆

        
        % --- 图形对象 ---
        r = AGVs(k).pos(1); c = AGVs(k).pos(2);           
        AGVs(k).path_line = plot(ax, NaN, NaN, '-', ...
            'Color', path_colors(k,:), 'LineWidth', 2, 'LineStyle', '--');
        
        edge_col = 'k';
        if AGVs(k).type == 2
            edge_col = 'b';
        end
        AGVs(k).handle = rectangle(ax, 'Position', [c-0.9, r-0.9, 0.8, 0.8], ...
            'Curvature', 0.2, 'FaceColor', 'g', 'EdgeColor', edge_col, 'LineWidth', 2);
        
        AGVs(k).text = text(ax, c-0.5, r-0.5, '', ...
            'Color', 'k', 'HorizontalAlignment', 'center', ...
            'FontSize', 8, 'FontWeight', 'bold');
    end
end
