function [front_levels, front_sizes_str] = summarize_front_layers(fronts)
% =========================================================================
% 函数功能：汇总非支配前沿面的层次结构信息
%
% 输入参数：
%   fronts       - 元胞数组，每个元胞 fronts{i} 存储属于第 i 层前沿的个体索引向量
%
% 输出参数：
%   front_levels    - 非支配前沿的总层数（即 fronts 的长度）
%   front_sizes_str - 字符串，描述各层前沿包含的个体数量，例如 '[15 8 3]'
%                     如果 fronts 为空（0层），则返回 '[]'
% =========================================================================
    % 获取前沿的总层数
    front_levels = numel(fronts);   
    % 如果没有前沿层（fronts 为空），直接返回 '[]'
    if front_levels == 0
        front_sizes_str = '[]';
        return;
    end
    % 预分配一个向量，用于存储各层前沿的个体数量
    front_sizes = zeros(1, front_levels);
    
    % 遍历每一层前沿，统计该层包含的个体数量
    for i = 1:front_levels
        front_sizes(i) = numel(fronts{i});
    end   
    % 将数值向量转换为字符串表示，例如 [15, 8, 3] 会被转换为 '[15 8 3]'
    front_sizes_str = mat2str(front_sizes);
end