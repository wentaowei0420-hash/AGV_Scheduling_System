function immigrants_count = determine_fork_immigrant_count(unique_front, stagnation_counter, pop_size)
% =========================================================================
% 函数功能：根据当前前沿多样性和停滞状态，决定叉车式AGV子种群应引入的
%           随机移民个体数量。
%
% 输入参数：
%   unique_front       - 当前代第一前沿中“实质唯一”的解的数量（量化去重后）
%   stagnation_counter - 停滞计数器，记录连续多少代第一前沿签名未发生变化
%   pop_size           - 种群规模（个体总数）
%
% 输出参数：
%   immigrants_count   - 需要生成的随机移民个体数量（整数，0~ceil(0.12*pop_size)）
%
% 设计思路：
%   叉车式AGV的调度解空间通常比托举式更大且更不连续（单任务顺序+分配），
%   因此需要更强的探索能力以避免早熟收敛。本函数与托举版本采用相同的结构，
%   但在各个触发档位上设置了**更高的移民比例**，并在最终上限上放宽至 12%。
%
%   具体策略分三层：
%   1. 前沿唯一解极少（<=2）→ 探索压力最大，移民频率和数量最高；
%   2. 前沿唯一解较少（<=4）→ 中等探索压力；
%   3. 前沿唯一解较多（>=5）→ 仅极长停滞时少量移民。
%   同一档位内，停滞代数越高，触发移民的比例越大。
%   mod 条件保证移民不是每代都注入，而是间隔若干代触发一次，避免过度扰动。
% =========================================================================

    immigrants_count = 0;  % 默认不引入移民

    % ---------- 情况1：前沿唯一解 <= 2 ----------
    if unique_front <= 2
        % 停滞代数 >= 30 且每10代触发：长时间停滞，强烈移民
        if stagnation_counter >= 30 && mod(stagnation_counter, 10) == 0
            immigrants_count = max(immigrants_count, ceil(0.11 * pop_size));
        % 停滞代数 >= 15 且每5代触发：中等停滞，较强移民
        elseif stagnation_counter >= 15 && mod(stagnation_counter, 5) == 0
            immigrants_count = max(immigrants_count, ceil(0.08 * pop_size));
        % 停滞计数器 == 0（前沿刚发生变化）：轻度移民，保持初始阶段的探索性
        elseif stagnation_counter == 0
            immigrants_count = max(immigrants_count, max(3, ceil(0.05 * pop_size)));
        end

    % ---------- 情况2：前沿唯一解在 3~4 之间 ----------
    elseif unique_front <= 4
        % 停滞代数 >= 30 且每10代触发：较强移民
        if stagnation_counter >= 30 && mod(stagnation_counter, 10) == 0
            immigrants_count = max(immigrants_count, ceil(0.09 * pop_size));
        % 停滞代数 >= 15 且每5代触发：中等移民
        elseif stagnation_counter >= 15 && mod(stagnation_counter, 5) == 0
            immigrants_count = max(immigrants_count, ceil(0.06 * pop_size));
        end

    % ---------- 情况3：前沿唯一解较多（>=5）----------
    % 仅在极长停滞（>=36代且12代一轮）时引入极少量移民
    elseif stagnation_counter >= 36 && mod(stagnation_counter, 12) == 0
        immigrants_count = max(immigrants_count, ceil(0.04 * pop_size));
    end

    % 最终保护：移民数量不能超过种群规模的 12%
    immigrants_count = min(immigrants_count, ceil(0.12 * pop_size));
end