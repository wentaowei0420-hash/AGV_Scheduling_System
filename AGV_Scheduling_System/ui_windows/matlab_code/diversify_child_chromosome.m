%% ==================== 子代多样化 ====================
function child = diversify_child_chromosome(child, sibling, parent1, parent2, num_tasks, num_agvs)
% =========================================================================
% 函数功能：确保生成的子代染色体与其父代及兄弟染色体存在差异。
%           如果子代与任何一个父代或另一个子代完全相同，则执行强制多样化操作。
%           多样化操作最多执行两次，若首次仍未脱重，则再次尝试。
%
% 输入参数：
%   child   - 第一个子代染色体（长度为 2*num_tasks）
%   sibling - 第二个子代染色体（可选，用于兄弟对比），若无则传入 [] 或不传
%   parent1 - 父代1的染色体
%   parent2 - 父代2的染色体
%   num_tasks - 任务总数
%   num_agvs  - 可用的 AGV 数量
%
% 输出参数：
%   child   - 可能经过多样化修改后的子代染色体
%
% 执行逻辑：
%   1. 若未提供 sibling 参数，则默认设为一个空数组 []。
%   2. 检查 child 是否与 parent1、parent2 或 sibling 完全相同
%      （使用 isequal 逐元素比较）。如果没有任何重复，则直接返回未修改的 child。
%   3. 如果有重复，调用 force_diversify_chromosome 对 child 执行强制多样化操作。
%   4. 再次检查修改后的 child 是否仍与父代或兄弟重复，若仍重复则
%      第二次调用 force_diversify_chromosome，以最大限度地摆脱重复状态。
%
% 设计意图：
%   交叉和变异操作有时会生成与父代完全相同或两个子代彼此相同的染色体，
%   这会导致种群丧失多样性，降低搜索效率。本函数在子代生成后被调用，
%   起到“安全网”的作用，确保每个新个体至少在基因层面是独特的。
% =========================================================================

    % 如果未传入 sibling 参数（如单独的变异调用），则将其设为空数组
    if nargin < 2
        sibling = [];
    end

    % --- 检查是否存在完全相同的个体 ---
    % 与父代1相同？ 与父代2相同？ 与兄弟子代相同？（sibling 非空时才检查）
    is_duplicate = isequal(child, parent1) || isequal(child, parent2) || ...
                   (~isempty(sibling) && isequal(child, sibling));
    
    % 如果没有重复，直接返回原 child
    if ~is_duplicate
        return;
    end

    % --- 存在重复：执行第一次强制多样化 ---
    child = force_diversify_chromosome(child, num_tasks, num_agvs);
    
    % --- 再次检查是否仍重复 ---
    % 由于多样化操作可能因巧合未改变实质差异，故进行二次确认
    if isequal(child, parent1) || isequal(child, parent2) || ...
       (~isempty(sibling) && isequal(child, sibling))
        % 如果仍然重复，执行第二次强制多样化
        child = force_diversify_chromosome(child, num_tasks, num_agvs);
    end
end