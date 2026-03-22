% =================================================================
% 模块：电量监控更新 (UI优化版：含动态变色与数字显示)
% =================================================================
function update_battery_monitor(f_batt, b_handle, t_handles, curr_bat)
    if isvalid(f_batt) && isvalid(b_handle)
        % 1. 更新柱状图高度
        set(b_handle, 'YData', curr_bat);
        
        % 定义配色方案
        col_healthy = [0.1 0.7 0.3]; % 优良 (深绿)
        col_warning = [1.0 0.6 0.0]; % 警告 (橙色)
        col_critical= [0.9 0.1 0.1]; % 严重 (深红)
        
        cdata = b_handle.CData;
        for k = 1:length(curr_bat)
            bat_val = curr_bat(k);
            
            % 2. 【新增】更新柱顶的文字标签内容和位置
            set(t_handles(k), 'String', sprintf('%.1f%%', bat_val), ...
                              'Position', [k, bat_val + 2, 0]); % 位置跟随柱子高度

            % 3. 动态变色逻辑
            if bat_val > 50
                cdata(k,:) = col_healthy;
                txt_col = [0.2 0.2 0.2]; % 文字黑色
            elseif bat_val > 20
                cdata(k,:) = col_warning;
                txt_col = [0.2 0.2 0.2]; % 文字黑色
            else
                cdata(k,:) = col_critical;
                txt_col = col_critical;  % 严重时文字也变红强调
            end
            set(t_handles(k), 'Color', txt_col);
        end
        % 应用新颜色
        set(b_handle, 'CData', cdata);
        drawnow limitrate; % 确保UI及时刷新
    end
end