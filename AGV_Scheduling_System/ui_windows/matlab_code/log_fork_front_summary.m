function log_fork_front_summary(tag, phase, gen, max_gen, pop, pop_objs, fronts, front_idx, num_tasks, num_agvs, stats)
% =========================================================================
% 函数功能：输出叉车式AGV种群前沿的详细日志信息
%
% 输入参数：
%   tag     - 日志标签字符串，用于区分不同的子问题（如 'EXPSTD-FORK'）
%   phase   - 阶段标识，'init' 表示初始种群，'gen' 表示进化中的某一代，'done' 表示最终结果
%   gen     - 当前代数（init时传0，done时传max_gen）
%   max_gen - 最大进化代数
%   pop     - 当前种群矩阵（大小为 pop_size × (2*num_tasks)）
%   pop_objs- 当前种群的目标值矩阵（pop_size × 3）
%   fronts  - 当前种群的非支配前沿（元胞数组）
%   front_idx - 第一前沿的个体索引向量
%   num_tasks - 任务数量
%   num_agvs  - AGV数量
%   stats   - 结构体，包含以下统计字段（可选，默认全0）
%             .immigrants - 本代引入的移民个体数量
%             .replaced   - 本代被替换的重复个体数量
%             .stall      - 当前停滞代数计数
% =========================================================================

    % 若未提供统计信息或为空，则初始化为默认值（全0）
    if nargin < 11 || isempty(stats)
        stats = struct('immigrants', 0, 'replaced', 0, 'stall', 0);
    end
    
    % 提取第一前沿所有个体的目标值矩阵（N×3）
    front_objs = pop_objs(front_idx, :);
    % 提取第一前沿所有个体的染色体编码（N × 2*num_tasks）
    front_pop = pop(front_idx, :);
    
    % 原始前沿个体数量（包含重复目标值的个体）
    raw_front = size(front_objs, 1);
    % 去除目标值完全相同的重复行后，剩余的唯一解个数
    unique_front = size(unique(front_objs, 'rows'), 1);
    
    % 计算第一前沿中三个目标的各自最小值
    min_objs = min(front_objs, [], 1);

    % 使用叉车专用的妥协解选择函数，获取妥协解在第一前沿中的局部索引
    rep_idx = select_fork_compromise_index(front_objs, front_pop, num_tasks, num_agvs);
    % 获取该妥协解的目标值向量 [距离, 时间, 能耗]
    compromise = front_objs(rep_idx, :);
    
    % 计算该妥协解的AGV负载分布：统计每个AGV分配到的任务数量
    % histcounts 的参数 1:num_agvs+1 定义了区间边界，对应AGV编号 1 到 num_agvs
    compromise_load = histcounts(front_pop(rep_idx, num_tasks+1:end), 1:num_agvs+1);

    % 获取第一前沿中时间目标最小值及其对应的个体索引
    [~, best_time_idx] = min(front_objs(:, 2));
    % 获取时间最优个体的目标值
    best_time = front_objs(best_time_idx, :);
    % 计算时间最优个体的AGV负载分布
    best_time_load = histcounts(front_pop(best_time_idx, num_tasks+1:end), 1:num_agvs+1);
    
    % 汇总前沿面的层次结构：总层数和各层个体数目的字符串描述
    [front_levels, front_sizes_str] = summarize_front_layers(fronts);

    % --- 根据阶段类型输出不同格式的日志 ---
    if strcmp(phase, 'gen')
        % 进化过程中：输出代数信息 gen/max_gen
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        % 初始或结束时：输出阶段名称（init/done），对齐格式
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end
    
    % 输出前沿层次信息：总层数及各层大小
    fprintf('      [%s] %-5s | frontLevels=%d | frontSizes=%s\n', ...
        tag, phase, front_levels, front_sizes_str);

    % 输出妥协解和时间最优解的负载分布，以及时间最优解的目标值
    fprintf('      [%s] %-5s | compromiseLoad=%s | bestTime=[%.1f %.1f %.3f] | bestTimeLoad=%s\n', ...
        tag, phase, mat2str(compromise_load), best_time(1), best_time(2), best_time(3), mat2str(best_time_load));
    
    % 输出算法运行统计：移民数量、替换重复个体数量、停滞代数
    fprintf('      [%s] %-5s | immigrants=%d | replaced=%d | stall=%d\n', ...
        tag, phase, stats.immigrants, stats.replaced, stats.stall);
end