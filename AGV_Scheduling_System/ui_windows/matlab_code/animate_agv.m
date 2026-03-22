% --- 简单的AGV移动动画 ---
function animate_agv(full_path)
    agv = rectangle('Position', [0,0,1,1], 'Curvature', 0.2, 'FaceColor', 'm', 'EdgeColor', 'k');
    for i = 1:1:size(full_path, 1) % 步长为2，加速播放
        x = full_path(i, 2);
        y = full_path(i, 1);
        set(agv, 'Position', [x-0.9, y-0.9, 0.8, 0.8]);
        drawnow;
    end
end