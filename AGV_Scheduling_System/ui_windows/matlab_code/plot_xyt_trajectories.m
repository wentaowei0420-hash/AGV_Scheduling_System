function plot_xyt_trajectories(json_file_path)
    % =========================================================
    % 解析 task_paths.json 并绘制 X-Y-T 三维时空轨迹图
    % =========================================================
    
    if nargin < 1
        json_file_path = 'task_paths.json'; % 默认读取当前目录下的文件
    end

    % 1. 读取并解析 JSON 文件
    try
        json_str = fileread(json_file_path);
        data = jsondecode(json_str);
    catch ME
        error('无法读取或解析 %s。请确认仿真已经运行并生成了该文件！\n错误信息: %s', json_file_path, ME.message);
    end

    % 获取所有有轨迹的任务字段名 (如 'task_1', 'task_2')
    task_names = fieldnames(data);
    if isempty(task_names)
        disp('JSON 文件中没有找到有效的轨迹数据！');
        return;
    end

    % 2. 初始化 3D 图形窗口
    figure('Name', 'X-Y-T 三维时空轨迹投影', 'Position', [150, 150, 1000, 800], 'Color', 'w');
    hold on; grid on;
    view(-35, 35); % 设置初始 3D 视角，最佳观测角度
    
    % 设置高级的颜色映射 (区分不同任务/AGV)
    colors = lines(length(task_names));

    % 3. 循环解析每一个任务的轨迹并绘制
    for i = 1:length(task_names)
        t_name = task_names{i};
        path_data = data.(t_name);

        if isempty(path_data)
            continue;
        end

        % 判断数据维度：Nx2 (仅坐标) 还是 Nx3 (包含了时间戳)
        if size(path_data, 2) == 2
            % 如果底层未修改，用序列索引模拟相对时间步
            Y_row = path_data(:, 1);
            X_col = path_data(:, 2);
            T_time = (1:length(X_col))'; 
            z_label_str = '相对时间步 (Relative Step)';
        elseif size(path_data, 2) >= 3
            % 如果包含了真实仿真时间戳 t (强烈推荐)
            Y_row = path_data(:, 1);
            X_col = path_data(:, 2);
            T_time = path_data(:, 3);
            z_label_str = '绝对仿真时间 T (Absolute Time)';
        end

        % 格式化图例名称 (将 'task_1' 变为 'Task 1')
        legend_name = strrep(t_name, 'task_', 'Task ');

        % --- 绘制时空主曲线 ---
        plot3(X_col, Y_row, T_time, '-', ...
            'Color', [colors(i, :), 0.8], ... % 加入少许透明度
            'LineWidth', 2.5, ...
            'DisplayName', legend_name);

        % --- 绘制数据点散点 ---
        scatter3(X_col, Y_row, T_time, 20, colors(i, :), 'filled', ...
            'HandleVisibility', 'off');

        % --- 标记起点 (绿色方块) 与终点 (红色三角) ---
        plot3(X_col(1), Y_row(1), T_time(1), 's', ...
            'MarkerSize', 8, 'MarkerFaceColor', '#77AC30', 'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
        plot3(X_col(end), Y_row(end), T_time(end), '^', ...
            'MarkerSize', 8, 'MarkerFaceColor', '#D95319', 'MarkerEdgeColor', 'k', 'HandleVisibility', 'off');
            
        % --- 绘制在 X-Y 平面上的二维投影 (可选，极大地增强空间立体感) ---
        plot3(X_col, Y_row, zeros(size(T_time)), '--', ...
            'Color', [colors(i, :), 0.3], 'LineWidth', 1, 'HandleVisibility', 'off');
    end

    % 4. 美化坐标轴与视觉效果
    xlabel('空间 X 轴 (栅格列坐标)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel('空间 Y 轴 (栅格行坐标)', 'FontWeight', 'bold', 'FontSize', 11);
    zlabel(z_label_str, 'FontWeight', 'bold', 'FontSize', 11);
    title('多 AGV 任务执行 X-Y-T 三维时空轨迹投影图', 'FontSize', 14, 'FontWeight', 'bold');

    % MATLAB矩阵中行坐标往下是递增的，需要翻转 Y 轴以匹配物理直觉
    set(gca, 'YDir', 'reverse');
    
    % 设置 Z 轴下界为 0 (以便容纳投影)
    zlim([0, max(T_time) + 10]);

    % 添加图例并美化背景
    legend('Location', 'northeastoutside', 'FontSize', 10);
    set(gca, 'Box', 'on', 'LineWidth', 1.2, 'GridAlpha', 0.2);
    
    % 开启三维旋转交互
    rotate3d on;
    disp('>> [绘图完毕] 拖动鼠标可旋转 3D 视角以观察时空避障细节。');
    hold off;
end