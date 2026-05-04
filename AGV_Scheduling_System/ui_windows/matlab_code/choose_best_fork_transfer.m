function transfer_idx = choose_best_fork_transfer(chrom, num_tasks, heavy_tasks_idx, target_agv, eval_func)
% =========================================================================
% 函数功能：为叉车式AGV的瓶颈转移操作选择最优的转移任务。
%           从高负载AGV的末尾任务中挑选一个，将其指派给低负载目标AGV，
%           并实际评估转移后的目标函数值，以字典序（时间 > 距离 > 能耗）
%           选出能带来最大改善的任务索引。
%
% 输入参数：
%   chrom           - 当前染色体（总长度 2*num_tasks）
%   num_tasks       - 任务总数
%   heavy_tasks_idx - 高负载AGV所承担任务在任务序列中的位置索引（向量）
%   target_agv      - 目标低负载AGV的编号（整数，1..num_agvs）
%   eval_func       - 评估函数句柄，调用格式：[~, obj] = eval_func(chromosome)
%                     返回 obj = [总距离, 最大完工时间, 总能耗]
%
% 输出参数：
%   transfer_idx    - 被选中进行转移的任务在任务序列中的索引（标量）
%
% 选择策略：
%   1. 只考虑高负载AGV末尾的至多最后3个任务。
%      因为末尾任务直接决定该AGV的完工时间，将其移走最有利于降低最大完工时间。
%   2. 对每个候选任务，临时修改染色体的AGV分配（将该任务指派给目标AGV），
%      调用 eval_func 获取完整的三维目标值。
%   3. 将目标值重新排列为 [时间, 距离, 能耗]，使用字典序比较
%      （lexicographic_less）挑出最优的转移方案。
%      - 第一优先级：最大完工时间（越小越好）
%      - 第二优先级：总行驶距离
%      - 第三优先级：总能耗
%   4. 返回带来最优目标值（按字典序）的候选任务索引。
%
% 设计优点：
%   - 只评估末尾少量任务，避免对所有高载任务进行全量评估，节省计算开销。
%   - 基于实际评估的决策保证了转移的有效性和靶向性。
% =========================================================================

    % 取候选任务位置：从 heavy_tasks_idx 的末尾开始，最多取 3 个
    % 当 heavy_tasks_idx 长度 ≥3 时，取最后 3 个；长度=2 时取后 2 个；长度=1 时取唯一一个
    candidate_positions = heavy_tasks_idx(max(1, end - min(2, length(heavy_tasks_idx) - 1)):end);
    
    % 默认选择最后一个候选任务作为初始最优转移
    transfer_idx = candidate_positions(end);
    
    % 初始化最优评分为 [inf, inf, inf]，表示尚未找到任何有效方案
    best_score = [inf, inf, inf];

    % 遍历所有候选任务位置
    for i = 1:length(candidate_positions)
        % 创建试算染色体副本，避免修改原始染色体
        trial = chrom;
        trial_idx = candidate_positions(i);
        
        % 将该任务的 AGV 分配改为目标低负载 AGV
        trial(num_tasks + trial_idx) = target_agv;
        
        % 评估试算染色体的目标值
        [~, trial_obj] = eval_func(trial);
        
        % 按照时间优先、距离次之、能耗最后的顺序构造评分向量
        trial_score = [trial_obj(2), trial_obj(1), trial_obj(3)];
        
        % 若当前试算的评分字典序优于目前最优，则更新最优记录
        if lexicographic_less(trial_score, best_score)
            best_score = trial_score;
            transfer_idx = trial_idx;
        end
    end
end