function update_agv_plot(agv)
    % 更新AGV在UI上的位置和状态颜色 (带动态载重与多任务队列显示)
    
    set(agv.handle, 'Position', [agv.vis_pos(2)-0.9, agv.vis_pos(1)-0.9, 0.8, 0.8]);
    
    % ========================================================
    % 【修改区】：动态构建悬浮文本，展示批量装载的实时重量和剩余件数
    if isfield(agv, 'payload_weight') && agv.payload_weight > 0
        queue_len = length(agv.drop_queue); % 查看卸货队列里还有几件没卸
        if queue_len > 0
            % 如果是托举车批量装载，显示当前总重和算上正在运的这一件的剩余总件数
            txt = sprintf('AGV%d W:%d(余%d)\n%s', agv.id, agv.payload_weight, queue_len + 1, agv.status); 
        else
            % 如果是单件（叉车），只显示当前重量
            txt = sprintf('AGV%d W:%d\n%s', agv.id, agv.payload_weight, agv.status);
        end
    else
        % 空载状态
        txt = sprintf('AGV%d 空载\n%s', agv.id, agv.status);
    end
    % ========================================================
    
    set(agv.text, 'Position', [agv.vis_pos(2)-0.5, agv.vis_pos(1)-0.5], 'String', txt);
    
    % 根据状态更改车身颜色
    col=[0.2 0.8 0.2]; 
    if agv.load > 0, col=[1 0.6 0]; end
    if contains(agv.status, 'Charge') || contains(agv.status, 'Low'), col=[1 0.2 0.2]; end 
    
    set(agv.handle, 'FaceColor', col);
end