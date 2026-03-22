% =================================================================
% 辅助函数：构建全局占用表 (Reservation Table)
% 该函数根据所有其他AGV的当前剩余路径，生成一个三维时空占用表，
% 用于后续路径规划中的冲突检测。表的大小为 (地图高, 地图宽, 最大预测步数)，
% 每个元素值为1表示该时间步的该位置被其他AGV占用，0表示空闲。
% =================================================================
function res_table = build_reservation_table(AGVs, current_k, mapH, mapW, max_steps)
    % 初始化一个全零的三维矩阵
    % 第一维：行坐标（1..mapH），第二维：列坐标（1..mapW），第三维：时间步（1..max_steps）
    res_table = zeros(mapH, mapW, max_steps);
    
    num_agvs = length(AGVs);                     % AGV的总数量
    for i = 1:num_agvs
        % 只考虑其他AGV（i ~= current_k），并且该AGV的路径非空（即正在执行任务）
        if i ~= current_k && ~isempty(AGVs(i).path)
            
            % 获取该AGV的剩余路径
            % AGVs(i).path 是该AGV的完整路径（N行2列的矩阵，每行[行,列]）
            % AGVs(i).path_idx 是当前时刻该AGV已经走过的路径索引（即下一步将要移动到的位置索引）
            % 因此剩余路径为从 path_idx 到末尾的所有路径点
            future_path = AGVs(i).path(AGVs(i).path_idx : end, :);
            
            len = size(future_path, 1);           % 剩余路径的长度（步数）
            
            % 将剩余路径上的每个点按照时间顺序标记为占用
            % 注意：只考虑前 max_steps 步（因为占用表只预测到 max_steps）
            for t = 1:min(len, max_steps)
                r = future_path(t, 1);             % 第t步的行坐标
                c = future_path(t, 2);             % 第t步的列坐标
                
                % 在占用表中标记该时间步该位置被占用
                res_table(r, c, t) = 1;
                
                % 【可选优化】膨胀障碍物：
                % 如果希望增加安全裕度，可以将当前格子及其周围一圈也标记为占用，
                % 这样可以避免两车擦肩而过时因尺寸或定位误差导致的碰撞。
                % 但需注意处理边界，防止索引越界。
                % 示例：res_table(max(1,r-1):min(mapH,r+1), max(1,c-1):min(mapW,c+1), t) = 1;
            end
            
            % 【关键】终点驻留锁定
            % 如果该AGV在 max_steps 步内就走完了剩余路径（即 len < max_steps），
            % 那么它到达终点后可能停在终点（如充电、等待指令等），
            % 因此终点位置在之后的时间步（t+1 到 max_steps）应继续保持占用状态。
            % 注意：循环结束后 t 的值为 min(len, max_steps)，
            % 若 len < max_steps，则 t = len，且 t < max_steps 成立。
            if t < max_steps
                final_pos = future_path(end, :);   % 终点坐标
                % 将终点位置从 t+1 到 max_steps 的所有时间步都设为1
                res_table(final_pos(1), final_pos(2), t+1:max_steps) = 1;
            end
        end
    end
end