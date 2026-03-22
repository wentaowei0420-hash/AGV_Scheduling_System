function [pickup_anchor, dropoff_anchor, pickup_size, dropoff_size] = get_task_coordinates(station_id)
    % 修复版：精准对齐 MATLAB 1-based 矩阵索引的锚点获取
    if station_id <= 12
        % === ID 1-12: 小配件逻辑 (2x2) ===
        lb_start_x = 3; item_w = 2; gap_x = 2; u_start_x = 17; u_item_w = 2; u_gap = 3;
        
        if station_id <= 6
            col = station_id - 1; wh_y = 19; st_y = 44;                    
        else
            col = station_id - 7; wh_y = 11; st_y = 34;                    
        end
        
        % 【关键修复】：加回 +1 以对齐 fill_rect 的索引
        wh_x = lb_start_x + col * (item_w + gap_x) + 1;
        pickup_anchor = [wh_y, wh_x];       
        pickup_size = [2, 2];
        
        st_x = u_start_x + col * (u_item_w + u_gap) + 1;
        dropoff_anchor = [st_y, st_x];       
        dropoff_size = [2, 2];
        
    else
        % === ID 13-16: 转向架/梁 逻辑 (3x3 分散布局) ===
        % 定义与主地图渲染同步的基础坐标矩阵 [X, Y]
        w_bases = [4, 42; 18, 4; 40, 23; 47, 11]; % 仓库取货基准
        s_bases = [40, 11; 4, 36; 5, 23; 47, 23]; % 工位送货基准
        
        idx = station_id - 12; % 映射为 1-4 的索引
        
        % 提取当前 ID 对应的取货点 (X, Y)
        base_wh_x = w_bases(idx, 1);
        base_wh_y = w_bases(idx, 2);
        
        % 【关键修复】：将绘图 Y, X 坐标映射为矩阵 Row, Col 并加回 +1
        pickup_anchor = [base_wh_y + 1, base_wh_x + 1];     
        pickup_size = [3, 3]; 
        
        % 提取当前 ID 对应的送货点 (X, Y)
        base_st_x = s_bases(idx, 1);
        base_st_y = s_bases(idx, 2);
        
        % 【关键修复】：同样映射矩阵并加回 +1
        dropoff_anchor = [base_st_y + 1, base_st_x + 1];    
        dropoff_size = [3, 3]; 
    end
end