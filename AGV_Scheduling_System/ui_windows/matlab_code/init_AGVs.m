function [AGVs, props, path_colors] = init_AGVs(num_agvs, depots, agv_schedules, agv_params, agv_types, ax)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % 鍒濆鍖?AGV 缁撴瀯浣撴暟缁勫強鍏跺浘褰㈠璞?(澶氫换鍔￠槦鍒楅€傞厤鐗?
    
    AGVs = struct([]);
    path_colors = lines(num_agvs);
    
    props(1).charge_stations = [
        xy2rc([2, 2]);  % 宸︿笂瑙掑厖鐢垫々
        xy2rc([2, 3]);  % 鍙充笂瑙掑厖鐢垫々
        xy2rc([3, 2]);  % 宸︿笅瑙掑厖鐢垫々
        xy2rc([3, 3])   % 鍙充笅瑙掑厖鐢垫々
    ];
    props(2).charge = xy2rc([39, 2]);  % 绫诲瀷 2 AGV 鐨勫厖鐢垫々浣嶇疆
    
    for k = 1:num_agvs
        % --- 鍩虹灞炴€у瓧娈?---
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
        
        % 銆愪慨鏀瑰尯銆戯細澶氫换鍔℃壒澶勭悊涓庤浆寮粺璁＄浉鍏崇殑鏂板瀛楁鍒濆鍖?
        AGVs(k).payload_weight = 0;         % 褰撳墠瀹炴椂杞介噸
        AGVs(k).pick_queue = [];            % 鍙栬揣浠诲姟闃熷垪
        AGVs(k).drop_queue = [];            % 鍗歌揣浠诲姟闃熷垪
        AGVs(k).active_task_id = 0;         % 褰撳墠姝ｅ湪鎵ц鐨勫瓙浠诲姟ID
        AGVs(k).interrupted_status = '';    % 璁板繂鏂數鍓嶇殑鐘舵€?
        AGVs(k).yield_resume_status = '';   % temporary resume state after yielding
        AGVs(k).total_turns = 0;            % 杞集缁熻
        AGVs(k).last_dir = [0, 0];          % 杩愬姩鐭㈤噺璁板繂

        
        % --- 鍥惧舰瀵硅薄 ---
        r = AGVs(k).pos(1); c = AGVs(k).pos(2);           
        AGVs(k).path_line = plot(ax, NaN, NaN, '-', ...
            'Color', path_colors(k,:), 'LineWidth', 1, 'LineStyle', '--');
        
        edge_col = 'k';
        if AGVs(k).type == 2
            edge_col = 'b';
        end
        AGVs(k).handle = rectangle(ax, 'Position', [c-0.9, r-0.9, 0.8, 0.8], ...
            'Curvature', 0.2, 'FaceColor', 'g', 'EdgeColor', edge_col, 'LineWidth', 1);
        
        AGVs(k).text = text(ax, c-0.5, r-0.5, '', ...
            'Color', 'k', 'HorizontalAlignment', 'center', ...
            'FontSize', 8, 'FontWeight', 'bold');
    end
end


