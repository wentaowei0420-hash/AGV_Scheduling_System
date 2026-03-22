function c_type = identify_conflict(id_a, id_b, AGVs)
    La_t = AGVs(id_a).pos;
    Lb_t = AGVs(id_b).pos;
    
    if ~isempty(AGVs(id_a).path) && AGVs(id_a).path_idx <= size(AGVs(id_a).path, 1)
        La_t1 = AGVs(id_a).path(AGVs(id_a).path_idx, :);
    else
        La_t1 = La_t;
    end
    
    if ~isempty(AGVs(id_b).path) && AGVs(id_b).path_idx <= size(AGVs(id_b).path, 1)
        Lb_t1 = AGVs(id_b).path(AGVs(id_b).path_idx, :);
    else
        Lb_t1 = Lb_t;
    end
    
    if isequal(La_t1, Lb_t) && isequal(Lb_t1, La_t) && ~isequal(La_t1, La_t)
        c_type = 1; return;
    end
    if isequal(La_t1, Lb_t1) && ~isequal(La_t1, La_t) && ~isequal(Lb_t1, Lb_t)
        c_type = 2; return;
    end
    if isequal(La_t1, Lb_t) && isequal(Lb_t1, Lb_t) && ~isequal(La_t1, La_t)
        c_type = 3; return;
    end
    if isequal(La_t1, Lb_t) && ~isequal(Lb_t1, Lb_t) && ~isequal(Lb_t1, La_t) && ~isequal(La_t1, La_t)
        c_type = 4; return;
    end
    c_type = 0;
end