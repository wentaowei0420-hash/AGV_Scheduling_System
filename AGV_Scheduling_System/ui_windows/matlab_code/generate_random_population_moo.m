%% ==================== 随机移民种群生成 ====================
function [rand_pop, rand_objs, rand_violation] = generate_random_population_moo(count, num_tasks, num_agvs, eval_func)
% =========================================================================
% 函数功能：随机生成指定数量的新个体，作为移民注入到主种群中，
%           以增强遗传多样性、缓解早熟收敛。
%
% 输入参数：
%   count     - 需要生成的移民个体数量（整数标量）
%   num_tasks - 任务总数
%   num_agvs  - 可用的AGV数量
%   eval_func - 评估函数句柄，用于计算新个体的目标值和约束违反量
%               调用格式：[~, obj, violation] = eval_func(chromosome)
%
% 输出参数：
%   rand_pop       - 随机生成的移民种群矩阵（count × 2*num_tasks）
%                    每一行是一个个体的染色体编码
%   rand_objs      - 移民种群的目标值矩阵（count × 3）
%                    列为 [总距离, 最大完工时间, 总能耗]
%   rand_violation - 移民种群的约束违反向量（count × 1）
%                    用于约束感知的支配判断和选择
%
% 实现说明：
%   每个移民个体按标准初始化方式生成：
%     前 num_tasks 个基因为 1..num_tasks 的随机排列（任务执行顺序）
%     后 num_tasks 个基因为 1..num_agvs 的随机整数（任务分配的AGV编号）
%   然后立即通过 eval_func 进行评估，获得目标值和约束违反量。
%   这批移民随后会并入合并种群，参与非支配排序和环境选择。
% =========================================================================

    % 预分配内存以提升效率
    rand_pop = zeros(count, num_tasks * 2);
    rand_objs = zeros(count, 3);
    rand_violation = zeros(count, 1);

    % 逐个生成随机个体并进行评估
    for i = 1:count
        % 随机生成任务顺序（1..num_tasks 的排列）
        rand_pop(i, 1:num_tasks) = randperm(num_tasks);
        % 随机为每个任务分配 AGV（1 到 num_agvs 之间的整数）
        rand_pop(i, num_tasks+1:end) = randi([1, num_agvs], 1, num_tasks);

        % 调用外部评估函数，获取目标值及约束违反量
        [~, obj, violation] = eval_func(rand_pop(i, :));
        rand_objs(i, :) = obj;
        rand_violation(i) = violation;
    end
end