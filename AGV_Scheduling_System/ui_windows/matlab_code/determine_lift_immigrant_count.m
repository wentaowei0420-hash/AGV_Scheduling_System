function immigrants_count = determine_lift_immigrant_count(unique_front, stagnation_counter, pop_size)
% =========================================================================
% 函数功能：根据当前前沿多样性和停滞状态，决定托举式AGV子种群应引入的
%           随机移民个体数量。
%
% 输入参数：
%   unique_front       - 当前代第一前沿中“实质唯一”的解的数量（量化去重后）
%   stagnation_counter - 停滞计数器，记录连续多少代第一前沿签名未发生变化
%   pop_size           - 种群规模（个体总数）
%
% 输出参数：
%   immigrants_count   - 需要生成的随机移民个体数量（整数，0~ceil(0.10*pop_size)）
%
% 设计思路：
%   当种群进化陷入停滞（停滞代数较高）且前沿解数量很少时，表明搜索可能
%   陷入局部最优，急需注入新的随机个体来增强探索。本函数根据“前沿唯一解数”
%   和“停滞代数”两个信号，按分段条件输出移民数量，并使用取上界（max）和
%   最终上限（min）来避免移民过少或过多。
%
%   具体策略：
%   1. 前沿唯一解很少（<=2）时，探索压力最大，移民频率和数量相对较高。
%   2. 前沿唯一解较少（<=4）时，探索压力次之。
%   3. 前沿唯一解较多时，仅在极长停滞时才给予少量移民。
%   4. 各种情况下都施加整体上限，防止过多移民破坏精英结构。
% =========================================================================

    immigrants_count = 0;  % 默认不引入移民

    % ---------- 情况1：前沿唯一解 <= 2 ----------
    if unique_front <= 2
        % 停滞代数 >= 30 且每10代触发：较长停滞，较强移民
        if stagnation_counter >= 30 && mod(stagnation_counter, 10) == 0
            immigrants_count = max(immigrants_count, ceil(0.07 * pop_size));
        % 停滞代数 >= 12 且每6代触发：中等停滞，中等移民
        elseif stagnation_counter >= 12 && mod(stagnation_counter, 6) == 0
            immigrants_count = max(immigrants_count, ceil(0.05 * pop_size));
        % 停滞计数器 == 0（即前沿刚刚发生变化）：轻微移民，保持探索
        elseif stagnation_counter == 0
            immigrants_count = max(immigrants_count, max(2, ceil(0.03 * pop_size)));
        end

    % ---------- 情况2：前沿唯一解在 3~4 之间 ----------
    elseif unique_front <= 4
        % 停滞代数 >= 36 且每12代触发：长时间停滞，较多移民
        if stagnation_counter >= 36 && mod(stagnation_counter, 12) == 0
            immigrants_count = max(immigrants_count, ceil(0.06 * pop_size));
        % 停滞代数 >= 18 且每9代触发：中等停滞，中等移民
        elseif stagnation_counter >= 18 && mod(stagnation_counter, 9) == 0
            immigrants_count = max(immigrants_count, ceil(0.04 * pop_size));
        end

    % ---------- 情况3：前沿唯一解较多（>=5）----------
    % 只在极长停滞（>=45代且15代一轮）时引入极少移民
    elseif stagnation_counter >= 45 && mod(stagnation_counter, 15) == 0
        immigrants_count = max(immigrants_count, ceil(0.03 * pop_size));
    end

    % 最终保护：移民数量不能超过种群规模的 10%
    immigrants_count = min(immigrants_count, ceil(0.10 * pop_size));
end