function log_lift_front_summary(tag, phase, gen, max_gen, pop_objs, fronts, front_idx, stats)
% =========================================================================
% 函数功能：输出托举式AGV种群前沿的详细日志信息
%
% 输入参数：
%   tag      - 日志标签字符串，用于区分不同的子问题（如 'EXPSTD-LIFT'）
%   phase    - 阶段标识：'init' 表示初始种群，'gen' 表示进化中的某一代，'done' 表示最终结果
%   gen      - 当前代数（init 时传入 0，done 时传入 max_gen）
%   max_gen  - 最大进化代数
%   pop_objs - 当前种群的目标值矩阵（pop_size × 3），每一列依次为 距离、时间、能耗
%   fronts   - 当前种群的非支配前沿（元胞数组），fronts{1} 为第一前沿
%   front_idx- 第一前沿的个体索引向量
%   stats    - 结构体，包含以下统计字段（可选，若未提供则默认为全0）
%              .immigrants - 本代引入的移民个体数量
%              .replaced   - 本代被替换的重复个体数量
%              .stall      - 当前停滞代数计数
% =========================================================================

    % 若未提供统计信息，或 stats 为空，则初始化为默认值（全0）
    if nargin < 8 || isempty(stats)
        stats = struct('immigrants', 0, 'replaced', 0, 'stall', 0);
    end
    
    % 提取第一前沿所有个体的目标值矩阵（N × 3）
    front_objs = pop_objs(front_idx, :);
    
    % 第一前沿的总个体数量（包含目标值相同的个体）
    raw_front = size(front_objs, 1);
    % 目标量化去重后，唯一解的个数（通过 count_unique_front_objs 统一计数）
    unique_front = count_unique_front_objs(front_objs);
    
    % 第一前沿中每个目标的最小值（作为该前沿的包络参考）
    min_objs = min(front_objs, [], 1);
    
    % 使用标准 TOPSIS 妥协解选择函数，获取妥协解在第一前沿中的局部索引
    rep_idx = select_compromise_index(front_objs);
    % 该妥协解的三维目标值 [距离, 时间, 能耗]
    compromise = front_objs(rep_idx, :);
    
    % 汇总前沿面的层次结构：总层数和各层个体数目的字符串描述
    [front_levels, front_sizes_str] = summarize_front_layers(fronts);

    % --- 根据阶段类型输出不同格式的日志 ---
    if strcmp(phase, 'gen')
        % 进化过程中：输出代数信息 gen/max_gen
        fprintf('      [%s] gen %3d/%d | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, gen, max_gen, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    else
        % 初始或结束时：输出阶段名称（init/done），对齐格式，不显示 gen/max_gen
        fprintf('      [%s] %-5s | rawFront=%d | uniqueFront=%d | min=[%.1f %.1f %.3f] | compromise=[%.1f %.1f %.3f]\n', ...
            tag, phase, raw_front, unique_front, min_objs(1), min_objs(2), min_objs(3), ...
            compromise(1), compromise(2), compromise(3));
    end
    
    % 输出前沿层次信息：总层数及各层大小
    fprintf('      [%s] %-5s | frontLevels=%d | frontSizes=%s\n', ...
        tag, phase, front_levels, front_sizes_str);

    % 输出算法运行统计：移民数量、替换重复个体数量、停滞代数
    fprintf('      [%s] %-5s | immigrants=%d | replaced=%d | stall=%d\n', ...
        tag, phase, stats.immigrants, stats.replaced, stats.stall);
end