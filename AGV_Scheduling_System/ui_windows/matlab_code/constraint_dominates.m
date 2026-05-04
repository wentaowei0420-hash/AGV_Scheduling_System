function tf = constraint_dominates(obj_a, violation_a, obj_b, violation_b)
% =========================================================================
% 函数功能：约束支配关系判断 —— 判断个体a是否约束支配个体b
%
% 输入参数：
%   obj_a, obj_b         - 分别为个体 a 和个体 b 的目标值向量（长度为3）
%   violation_a, violation_b - 分别为两个个体的约束违反总量（标量）
%
% 输出参数：
%   tf - 逻辑值，true 表示 个体a 约束支配 个体b
%
% 支配规则（按优先级递减）：
%   1. 如果 a 可行（violation <= tol）而 b 不可行 → a 约束支配 b
%   2. 如果 a 不可行 而 b 可行 → a 不支配 b
%   3. 如果两者都不可行 → 违反量更小的个体支配违反量更大的个体
%      （当差异超过容差 tol 时才视为显著优劣）
%   4. 如果两者都可行（或违反量无显著差异，视为同等可行程度）：
%      则采用标准 Pareto 支配：a 所有目标 <= b 的所有目标，且至少有一个严格更小
%
% 容差 tol = 1e-9，用于处理浮点误差和约束检查的数值稳定性。
% =========================================================================
    tol = 1e-9;  % 约束违反和支配比较的数值容差

    % 判断两个个体是否可行（约束违反为有限值且在容差范围内）
    feasible_a = isfinite(violation_a) && violation_a <= tol;
    feasible_b = isfinite(violation_b) && violation_b <= tol;

    % 规则1：可行解 vs 不可行解 → 可行解优先
    if feasible_a && ~feasible_b
        tf = true;
        return;
    elseif ~feasible_a && feasible_b
        tf = false;
        return;
    end

    % 规则3：两个都不可行 → 比较违反量，违反量更小的支配更大的
    if ~feasible_a && ~feasible_b
        if violation_a < violation_b - tol
            tf = true;
            return;
        elseif violation_a > violation_b + tol
            tf = false;
            return;
        end
        % 若违反量差异在容差内，则落入规则4，继续比较目标值
    end

    % 规则4：两者同为可行（或违反量视为等同）→ 标准 Pareto 支配判断
    % all(...) 检查 a 的所有目标是否都 <= b 的对应目标
    % any(...) 检查是否至少存在一个目标 a 严格 < b
    tf = all(obj_a <= obj_b) && any(obj_a < obj_b);
end