function score = calculate_ahp_priority(agv, task_list, t)
    % AHP 优先级评估算法 (多任务队列适配版)
    persistent w;
    if isempty(w)
        A = [1, 5, 3; 1/5, 1, 1/3; 1/3, 3, 1];
        n = size(A, 1);
        prod_A = prod(A, 2);           
        root_A = prod_A .^ (1/n);      
        w = root_A ./ sum(root_A);     
        w = w';                        
    end
    
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
    
    s_battery = (100 - agv.battery) / 100.0;
    
    curr_task_id = 0;
    if isfield(agv, 'active_task_id') && agv.active_task_id > 0
        curr_task_id = agv.active_task_id;
    elseif ~isempty(agv.tasks)
        curr_task_id = agv.tasks(1); % 兜底逻辑
    end

    s_time = 0;
    if curr_task_id > 0
        % Use the first matching task row only. Some validation scripts build
        % task_list with repeated active_task_id values, and taking every match
        % turns the scalar priority into a vector, which breaks callers such
        % as arrayfun(..., 'UniformOutput', true).
        row_idx = find(task_list(:,1) == curr_task_id, 1, 'first');
        if ~isempty(row_idx) && size(task_list, 2) >= 4
            deadline = task_list(row_idx, 4);
            rem_time = deadline - t;
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
    
    score = w(1)*s_status + w(2)*s_battery + w(3)*s_time;
end
