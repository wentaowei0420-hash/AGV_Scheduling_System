%% ==================== 叉车妥协解选择器（加权TOPSIS+负载均衡） ====================
function idx = select_fork_compromise_index(front_objs, front_pop, num_tasks, num_agvs)
% =========================================================================
% 函数功能：叉车AGV专用的妥协解选择函数。
%           在标准 TOPSIS 基础上，针对三个目标（距离、时间、能耗）赋予
%           不同权重，使时间目标得到最多关注；同时结合各个解的AGV任务分配
%           均衡程度进行微调，优先选择负载更均匀的解作为最终妥协解。
%
% 输入参数：
%   front_objs - 第一前沿个体的目标值矩阵（N × 3），列为 [距离, 时间, 能耗]
%   front_pop  - 第一前沿个体的染色体矩阵（N × 2*num_tasks），
%                如果未提供或为空，则退化为纯 TOPSIS 选择（不考虑负载均衡）
%   num_tasks  - 任务总数
%   num_agvs   - AGV 数量
%
% 输出参数：
%   idx - 在第一前沿中选出的妥协解的局部索引（整数，1..N）
%
% 方法说明：
%   【第一步：加权 TOPSIS】
%     1. 将前沿各目标归一化到 [0,1] 区间。
%     2. 应用权重向量 [0.28, 0.50, 0.22] （距离、时间、能耗），
%        使时间获得最高权重（50%），保证排序结果优先改善最大完工时间。
%     3. 计算每个解到理想最优解和理想最劣解的欧氏距离，得到相对贴近度 closeness。
%
%   【第二步：负载均衡评分（仅在提供 front_pop 时启用）】
%     1. 从每个解的染色体后半部分提取AGV分配向量。
%     2. 统计每个AGV分配到的任务数量，计算两个负载不均度指标：
%        - count_span： 最大任务数 - 最小任务数（负载极差）
%        - count_std：  各AGV任务数的标准差
%     3. 将极差和标准差分别归一化到 [0,1]。
%     4. 组合得到“均衡得分”：balance_score = 1 - 0.7*span_norm - 0.3*std_norm
%        （极差权重更大，均衡性越好得分越接近1）。
%
%   【第三步：综合得分】
%     combined_score = 0.985 * closeness + 0.015 * balance_score
%     这样以 TOPSIS 优化目标为主（98.5%），负载均衡仅在新解目标值极接近时
%     起轻微调节作用。
%
%   最后返回 combined_score 最高的前沿个体局部索引。
% =========================================================================

    % 空前沿防护：若前沿为空，则返回索引 1（由调用方保证有效性）
    if isempty(front_objs)
        idx = 1;
        return;
    end

    % ===== 第一步：加权 TOPSIS =====
    % 各目标的最小值与最大值（用于归一化）
    min_objs = min(front_objs, [], 1);
    max_objs = max(front_objs, [], 1);
    % 归一化至 [0,1]，分母加小量 1e-9 防止除零
    obj_norm = (front_objs - min_objs) ./ (max_objs - min_objs + 1e-9);

    % 目标权重：侧重时间（makespan），其次是距离，能耗权重最低
    obj_weights = [0.28, 0.50, 0.22];

    % 确定加权归一化后的理想最优解和理想最劣解
    ideal_best = min(obj_norm, [], 1);    % 所有解在每个目标上的最小值
    ideal_worst = max(obj_norm, [], 1);   % 所有解在每个目标上的最大值

    % 计算各解到理想最优和理想最劣的加权欧氏距离
    d_best = sqrt(sum(((obj_norm - ideal_best) .* obj_weights).^2, 2));
    d_worst = sqrt(sum(((obj_norm - ideal_worst) .* obj_weights).^2, 2));

    % 计算 TOPSIS 相对贴近度（越接近 1 越好）
    closeness = d_worst ./ (d_best + d_worst + 1e-9);

    % 若未提供染色体矩阵或其为空，则仅用 TOPSIS 选出最优解
    if nargin < 4 || isempty(front_pop)
        [~, idx] = max(closeness);
        return;
    end

    % ===== 第二步：计算负载均衡评分 =====
    % 提取每个解的 AGV 分配矩阵（位于染色体后半部分）
    assign_mat = front_pop(:, num_tasks+1:end);

    count_span = zeros(size(assign_mat, 1), 1);  % 负载极差
    count_std  = zeros(size(assign_mat, 1), 1);  % 负载标准差

    for i = 1:size(assign_mat, 1)
        % 统计各AGV被分配的任务数（AGV编号为 1..num_agvs）
        counts = histcounts(assign_mat(i, :), 1:num_agvs+1);
        count_span(i) = max(counts) - min(counts);
        count_std(i)  = std(counts);
    end

    % 归一化极差到 [0,1]，若所有解极差相同则用 0 填充
    if max(count_span) > min(count_span)
        span_norm = (count_span - min(count_span)) ./ (max(count_span) - min(count_span));
    else
        span_norm = zeros(size(count_span));
    end

    % 归一化标准差到 [0,1]
    if max(count_std) > min(count_std)
        std_norm = (count_std - min(count_std)) ./ (max(count_std) - min(count_std));
    else
        std_norm = zeros(size(count_std));
    end

    % 均衡性得分：极差和标准差越小，得分越高（1 为完全均匀分配）
    balance_score = 1 - 0.7 * span_norm - 0.3 * std_norm;

    % ===== 第三步：综合得分 =====
    % 主目标（closeness）占 98.5%，负载均衡只作为微弱偏置
    combined_score = 0.985 * closeness + 0.015 * balance_score;

    % 返回综合得分最高的解的局部索引
    [~, idx] = max(combined_score);
end