function score = calculate_predictive_ahp_priority(agv, task_list, current_t, future_t, agv_params_k)
    % AHP 优先级【预测】评估算法 (基于滑动时间窗)
    
    persistent w;
    if isempty(w)
        A = [1, 5, 3; 1/5, 1, 1/3; 1/3, 3, 1];
        n = size(A, 1);
        prod_A = prod(A, 2);           
        root_A = prod_A .^ (1/n);      
        w = root_A ./ sum(root_A);     
        w = w';                        
    end
    
    % ---------------------------------------------------------
    % 1. 预测未来的状态 (s_status)：短视距内保持惯性继承
    % ---------------------------------------------------------
    s_status = 0;
    if strcmp(agv.status, 'Going_Charge')
        s_status = 1.0;
    elseif strcmp(agv.status, 'Moving_Drop') || agv.load == 1
        s_status = 0.7;
    elseif strcmp(agv.status, 'Moving_Pick')
        s_status = 0.4;
    elseif strcmp(agv.status, 'Go_Home')
        s_status = 0.1;
    end
    
    % ---------------------------------------------------------
    % 2. 预测未来的电量 (s_battery)：物理模型推演
    % ---------------------------------------------------------
    delta_t = future_t - current_t;
    if delta_t > 0
        % 预估移动的格子数 (向下取整)
        predicted_cells_moved = floor(delta_t / agv.step_dur); 
        
        % 获取物理参数
        e_b = agv_params_k.e_base; 
        e_l = agv_params_k.e_load_factor;
        if agv.type == 1, cap = 80.0; else, cap = 500.0; end
        
        % 计算推演掉电量
        predicted_cost = predicted_cells_moved * (e_b + e_l * (agv.payload_weight / cap));
        future_battery = max(0, agv.battery - predicted_cost);
    else
        future_battery = agv.battery;
    end
    s_battery = (100 - future_battery) / 100.0;
    
    % ---------------------------------------------------------
    % 3. 预测未来的紧迫度 (s_time)：时间流逝推演
    % ---------------------------------------------------------
    curr_task_id = 0;
    if isfield(agv, 'active_task_id') && agv.active_task_id > 0
        curr_task_id = agv.active_task_id;
    elseif ~isempty(agv.tasks)
        curr_task_id = agv.tasks(1); 
    end
    
    s_time = 0;
    if curr_task_id > 0
        row_idx = find(task_list(:,1) == curr_task_id);
        if ~isempty(row_idx) && size(task_list, 2) >= 4
            deadline = task_list(row_idx, 4);
            % 【关键修改】：使用 future_t 减去 deadline
            rem_time = deadline - future_t; 
            if rem_time <= 0
                s_time = 1.0;
            else
                s_time = max(0, 1 - (rem_time / 1000)); 
            end
        else
            s_time = 0.5;
        end
    else
        s_time = 0;
    end
    
    % ---------------------------------------------------------
    % 综合加权得分
    % ---------------------------------------------------------
    score = w(1)*s_status + w(2)*s_battery + w(3)*s_time;
end