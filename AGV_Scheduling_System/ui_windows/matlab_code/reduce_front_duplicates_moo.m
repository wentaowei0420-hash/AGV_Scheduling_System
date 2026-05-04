function [pop, pop_objs, pop_violation, replaced_count] = reduce_front_duplicates_moo(pop, pop_objs, pop_violation, front_idx, num_tasks, num_agvs, eval_func, max_obj_copies)
% =========================================================================
% 函数功能：针对第一前沿进行目标空间去重，确保前沿面的多样性。
%           如果第一前沿中存在过多“量化后目标值相同”的个体（即本质上
%           相同的解），则将多余的个体替换为全新随机生成的个体。
%
% 输入参数：
%   pop          - 当前种群矩阵（pop_size × 2*num_tasks）
%   pop_objs     - 当前种群的目标值矩阵（pop_size × 3），[距离, 时间, 能耗]
%   pop_violation- 当前种群的约束违反向量（pop_size × 1）
%   front_idx    - 第一前沿在种群中的索引向量
%   num_tasks    - 任务总数
%   num_agvs     - AGV数量
%   eval_func    - 评估函数句柄，用于计算新个体的目标值和约束违反量
%   max_obj_copies - 第一前沿中允许的同一量化目标值组合的最大副本数
%
% 输出参数：
%   pop          - 去重并部分随机化后的种群矩阵
%   pop_objs     - 更新后的目标值矩阵
%   pop_violation- 更新后的约束违反向量
%   replaced_count - 本函数实际替换的个体数量（整数）
%
% 实现机制：
%   1. 将第一前沿个体的目标值按指定精度进行量化（四舍五入），得到量化矩阵。
%   2. 利用 unique 识别出那些量化后完全相同（即“实质相同”）的解，并将它们分组。
%   3. 对每个分组，如果其成员数量超过允许的最大副本数 max_obj_copies，
%      则将超出部分的个体用全新的随机个体替换，以引入多样性。
%   4. 新个体立即通过 eval_func 评估，获得新的目标值和约束违反量。
%   5. 返回替换后的完整种群及更新后的目标值/约束，同时统计替换数量。
%
% 注意：
%   - 此去重仅限于**第一前沿**，不影响其它非支配层，意在保持Pareto前沿
%     的多样性和信息量。
%   - 超出副本数被替换的个体索引通过 front_idx 映射回整个种群的位置。
% =========================================================================

    replaced_count = 0;                 % 初始化替换计数器

    % 如果第一前沿为空，直接返回，无需处理
    if isempty(front_idx)
        return;
    end

    % 提取第一前沿个体的目标值，并进行量化（四舍五入）
    rounded_front = quantize_moo_objectives(pop_objs(front_idx, :));
    
    % 按行识别唯一的量化目标值组合，并给每个个体分配组号
    % unique 返回 ~（忽略）和 ~，以及每个个体所属的组编号 obj_group
    [~, ~, obj_group] = unique(rounded_front, 'rows', 'stable');
    
    % 遍历每一个分组（即每一种“实质相同”的解）
    for group_id = 1:max(obj_group)
        % 找出属于当前分组的原种群索引（即 front_idx 中符合该组号的成员）
        members = front_idx(obj_group == group_id);
        
        % 如果该组个体数量没有超过最大允许副本数，则无需替换
        if numel(members) <= max_obj_copies
            continue;
        end
        
        % 选择超出上限的个体作为待替换目标
        overflow = members(max_obj_copies + 1:end);
        
        % 逐个替换溢出的个体
        for k = 1:numel(overflow)
            idx = overflow(k);                     % 在种群中的实际行索引
            
            % 用全新的随机染色体覆盖该个体
            pop(idx, 1:num_tasks) = randperm(num_tasks);          % 随机任务顺序
            pop(idx, num_tasks+1:end) = randi([1, num_agvs], 1, num_tasks); % 随机AGV分配
            
            % 立即评估新染色体的目标值和约束违反
            [~, obj, violation] = eval_func(pop(idx, :));
            pop_objs(idx, :) = obj;
            pop_violation(idx) = violation;
            
            % 替换计数加一
            replaced_count = replaced_count + 1;
        end
    end
end