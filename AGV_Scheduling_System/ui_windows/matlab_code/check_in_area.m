function in_area = check_in_area(pos, anchor_pos, area_size)
    % 区域范围判定函数 (锚点+尺寸版)
    r_min = anchor_pos(1);
    r_max = anchor_pos(1) + area_size(1) - 1;
    c_min = anchor_pos(2);
    c_max = anchor_pos(2) + area_size(2) - 1;
    
    in_area = (pos(1) >= r_min) && (pos(1) <= r_max) && ...
              (pos(2) >= c_min) && (pos(2) <= c_max);
end