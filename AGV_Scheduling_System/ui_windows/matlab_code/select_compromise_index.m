%% ==================== TOPSIS妥协解选择 ====================
function idx = select_compromise_index(front_objs)
% 使用TOPSIS方法从Pareto前沿中选取最接近理想解的妥协解索引
    if isempty(front_objs)
        idx = 1;
        return;
    end

    min_objs = min(front_objs, [], 1);
    max_objs = max(front_objs, [], 1);
    obj_norm = (front_objs - min_objs) ./ (max_objs - min_objs + 1e-9);
    ideal_best = min(obj_norm, [], 1);
    ideal_worst = max(obj_norm, [], 1);
    d_best = sqrt(sum((obj_norm - ideal_best).^2, 2));
    d_worst = sqrt(sum((obj_norm - ideal_worst).^2, 2));
    closeness = d_worst ./ (d_best + d_worst + 1e-9);
    [~, idx] = max(closeness);
end
