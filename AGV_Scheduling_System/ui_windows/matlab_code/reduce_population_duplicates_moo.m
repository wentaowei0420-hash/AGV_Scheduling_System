%% ==================== 种群去重（目标空间） ====================
function [pop, pop_objs, pop_violation, replaced_count] = reduce_population_duplicates_moo(pop, pop_objs, pop_violation, num_tasks, num_agvs, eval_func, max_obj_copies)
% =========================================================================
% 函数功能：对整个种群在目标空间中进行去重处理。
%           若目标值（量化后）完全相同的个体超过允许的最大副本数，
%           则超出的个体将被全新的随机个体替换，以保持种群多样性。
%
% 输入参数：
%   pop          - 当前种群矩阵（pop_size × 2*num_tasks）
%                  每一行前 num_tasks 为任务顺序，后 num_tasks 为AGV分配
%   pop_objs     - 当前种群的三维目标值矩阵（pop_size × 3），[距离, 时间, 能耗]
%   pop_violation- 当前种群的约束违反向量（pop_size × 1）
%   num_tasks    - 任务总数
%   num_agvs     - 可用的AGV数量
%   eval_func    - 评估函数句柄，调用格式：[~, obj, violation] = eval_func(chromosome)
%   max_obj_copies - 种群中允许的同一量化目标值组合的最大副本数
%
% 输出参数：
%   pop          - 去重并部分随机化后的种群矩阵
%   pop_objs     - 更新后的目标值矩阵
%   pop_violation- 更新后的约束违反向量
%   replaced_count - 被替换的重复个体数量（整数）
%
% 处理流程：
%   1. 对所有个体的目标值进行量化（不同维度采用不同精度四舍五入），
%      消除微小浮点误差导致的“伪不同”解。
%   2. 利用 unique 按行找出量化后相同的目标值组合，并将相同组合的个体归为一组。
%   3. 逐个检查组内的个体数量：若超过 max_obj_copies，则将超出的个体
%      替换为全新随机生成的染色体（任务顺序随机排列 + AGV随机分配），
%      并立即评估得到新的目标值和约束违反量。
%   4. 返回更新后的种群及替除计数。
%
% 应用场景：
%   该函数应用于环境选择之后、下一代进化之前，是保持种群多样性的一种
%   主动干预机制。与 reduce_front_duplicates_moo 的区别在于：
%   - 本函数作用于**整个种群**，而非仅第一前沿；
%   - 两者的 max_obj_copies 可以不同，通常种群整体的容忍度更高。
% =========================================================================

    replaced_count = 0;                % 初始化替换计数器

    % 步骤1: 量化所有个体的目标值
    rounded_objs = quantize_moo_objectives(pop_objs);

    % 步骤2: 识别量化后相同的目标值组合，并为每个个体分配组号 obj_group
    [~, ~, obj_group] = unique(rounded_objs, 'rows', 'stable');

    % 步骤3: 遍历每一个分组
    for group_id = 1:max(obj_group)
        % 找出属于当前分组的种群索引
        members = find(obj_group == group_id);

        % 若该组未超过允许副本数，则跳过
        if numel(members) <= max_obj_copies
            continue;
        end

        % 超出的个体将被替换
        overflow = members(max_obj_copies + 1:end);

        % 逐个处理溢出个体
        for k = 1:numel(overflow)
            idx = overflow(k);                     % 在种群中的行索引

            % 用全新随机染色体覆盖
            pop(idx, 1:num_tasks) = randperm(num_tasks);
            pop(idx, num_tasks+1:end) = randi([1, num_agvs], 1, num_tasks);

            % 立即评估新个体
            [~, obj, violation] = eval_func(pop(idx, :));
            pop_objs(idx, :) = obj;
            pop_violation(idx) = violation;

            % 替换计数递增
            replaced_count = replaced_count + 1;
        end
    end
end