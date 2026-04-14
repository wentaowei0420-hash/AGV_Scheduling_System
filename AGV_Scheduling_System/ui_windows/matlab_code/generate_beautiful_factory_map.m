function generate_beautiful_factory_map()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);


    % --- 1. 地图与网格参数设置 ---
    mapWidth = 60;      % 地图总宽度
    mapHeight = 50;     % 地图总高度
    gridSize = 1;       % 网格大小
    
    % 创建窗口 (调整分辨率和背景色)
    figure('Name', 'Factory Visualization', 'Color', [0.98 0.98 0.98], 'Position', [100, 100, 1200, 850]);
    ax = gca;
    hold on;
    axis equal;
    axis([-2 mapWidth+15 -2 mapHeight+2]); % 稍微扩大视野以容纳图例
    % 【新增】：强制消除坐标轴周围的空白边距 (Tight Inset)
    set(ax, 'LooseInset', [0, 0, 0, 0]);
    % 让坐标轴尽可能填满整个画布
    set(ax, 'Position', [0.02 0.02 0.96 0.96]);
    % --- 2. 绘制网格 (优化样式) ---
    xticks(0:gridSize:mapWidth);
    yticks(0:gridSize:mapHeight);
    grid on;
    set(ax, 'GridColor', [0.7 0.7 0.7]);  % 浅灰色网格
    set(ax, 'GridAlpha', 0.5);            % 半透明
    set(ax, 'GridLineStyle', '-');        % 虚线网格，更精致
    set(ax, 'LineWidth', 1);
    set(ax, 'XTickLabel', {});
    set(ax, 'YTickLabel', {});
    set(ax, 'Layer', 'top');           % 网格在最底层
    
    % 画一个白色的画布背景区，突出工厂区域
    rectangle('Position', [0, 0, mapWidth, mapHeight], 'FaceColor', 'w', 'EdgeColor', 'none');

    % --- 颜色定义 (专业配色方案) ---
    % 生产线/墙体 (深灰色)
    c_wall = [0.2 0.2 0.2];    
    % 生产线/墙体 (黑)
    c_bark = [0 0 0];  
    % 配件工位 (天际蓝)
    c_blue_light = [0.53 0.81 0.92]; 
    % 转向架/缓存区 (普鲁士蓝)
    c_blue_dark = [0.12 0.29 0.49];  
    % 托举AGV充电 (活力绿)
    c_green_charge = [0.2 0.8 0.6];  
    % 托举AGV车库 (抹茶绿)
    c_green_park = [0.6 0.8 0.5];    
    % 叉车AGV充电 (青色)
    c_cyan_charge = [0.0 0.6 0.7];   
    % 叉车AGV车库 (森林绿)
    c_green_dark = [0.25 0.4 0.25];  

    % --- 3. 绘制生产线/墙体 (双弧形改造) ---
    
    % 参数设置
    line_thick = 2;   % 统一生产线宽度
    r_in = 4;         % 内半径
    r_out = 6;        % 外半径
    
    % === 关键坐标计算 ===
    % 为了保持 U 型结构对称：
    % 1. 右上角圆心 (44, 42)
    % 2. 右下角圆心 (44, 36) -> 这样两个圆心垂直距离为6
    
    top_center = [44, 42];
    bot_center = [44, 36];
    % 直线段数据 [x, y, w, h]
    project_straight = [
        2, 32, 1, 17;                 % 左上垂直墙(不变        
        % A. 上横梁 (Top Beam)
        % 从 X=16 到 X=44 (接右上圆弧), Y=46(内沿), 厚度2
        16, 46, (top_center(1) - 16), line_thick;   
        % B. 右竖梁 (Right Vertical Beam) - 变短了，仅连接两个圆弧
        % X=48(内沿), Y从 36(下圆心) 到 42(上圆心), 宽
        (top_center(1) + r_in), bot_center(2), line_thick, (top_center(2) - bot_center(2)); 
        % C. 下横梁 (Bottom Beam) - 调整以接右下圆弧
        % 从 X=16 到 X=44 (接右下圆弧), Y=30(外沿,因为内沿是32), 厚度2
        % 注意：这里Y用30是因为内沿是32 (36-4)，厚度2，所以外底边是30
        16, 30, (bot_center(1) - 16), line_thick;
        % 其他墙体
        2, 21, 24, 1;                 
        2, 8, 24, 1;                  
        44, 9, 2, 19;                
    ];
    draw_styled_rects(project_straight, c_wall, 0, 'none'); 

    % 绘制圆弧
    % 1. 右上角圆弧 (0度到90度)
    draw_arc_wall(top_center, r_in, r_out, 0, 90, c_wall);
    
    % 2. 右下角圆弧 (-90度到0度)
    % 这里是从竖直向下的线(-90度/270度)连接到水平向右的线(0度)
    draw_arc_wall(bot_center, r_in, r_out, -90, 0, c_wall);

    % 外部围墙
    walls = [0, 0, 1, 51; 0, 0, 51, 1; 51,0,1,51; 0, 51, 52, 1];
    draw_styled_rects(walls, c_bark, 0, 'none');

    % --- 4. 绘制功能区域 ---
    
    % 4.1 大件仓库区域 (分散式布局 - 取货区) 坐标深度监控
    fprintf('\n>> [地图监控] 正在展开分散式大件仓库(ID:13-16)对应的9个格子详细坐标：\n');
    block_w = 3; block_h = 3;
    % 定义仓库基准坐标：[13:左上, 14:左下, 15:右上, 16:右下]
    w_bases = [4, 42; 18, 4; 40, 23; 47, 11]; 
    
    for i = 1:4
        station_id = i + 12; 
        base_x = w_bases(i, 1);
        base_y = w_bases(i, 2);
        pos = [base_x, base_y, block_w, block_h];
        
        fprintf('   [仓库 ID %d]: 区域起始(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('      └─ 包含的9个小格子坐标: \n');
        
        % 嵌套循环打印9个格点
        for dx = 0:block_w-1
            row_str = '      ';
            for dy = 0:block_h-1
                row_str = [row_str, sprintf('(%d, %d)  ', base_x + dx, base_y + dy)];
            end
            fprintf('%s\n', row_str);
        end
        
        % 绘图：统一使用深蓝色表示仓库
        draw_styled_rects(pos, c_blue_dark, 0.2, 'w'); 
        label_txt = ['仓', num2str(station_id)];
        add_styled_label(pos, label_txt, 'w', 9);
        fprintf('\n'); 
    end
    fprintf('--------------------------------------------------\n');
    % 4.2 中间 U 型区域内的配件 (ID: 1-12) 坐标深度监控
    fprintf('\n>> [地图监控] 正在展开中间 U 型配件工位(ID:1-12)对应的详细格子坐标：\n');
    box_w = 2; box_h = 2; gap_x = 3; 
    u_start_x = 17; u_top_y = 43;
    u_bot_y = 33;
    
    % --- 第一行：工位 P1 - P6 ---
    for i = 1:6
        station_id = i;
        base_x = u_start_x + (i-1)*(box_w+gap_x);
        base_y = u_top_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [工位 ID %d]: 区域起始(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('      └─ 包含的格子坐标: \n');
        
        % 嵌套循环打印 2x2 格点
        for dx = 0:box_w-1
            row_str = '      ';
            for dy = 0:box_h-1
                fprintf('%s(%d, %d)  ', row_str, base_x + dx, base_y + dy);
                row_str = ''; % 仅首点缩进
            end
            fprintf('\n');
        end
        
        draw_styled_rects(pos, c_blue_light, 0.3, 'k');
        add_styled_label(pos, ['P' num2str(station_id)], 'k', 7);
        fprintf('\n');
    end
    
    % --- 第二行：工位 P7 - P12 ---
    for i = 7:12
        station_id = i;
        base_x = u_start_x + (i-7)*(box_w+gap_x);
        base_y = u_bot_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [工位 ID %d]: 区域起始(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('      └─ 包含的格子坐标: \n');
        
        % 嵌套循环打印 2x2 格点
        for dx = 0:box_w-1
            row_str = '      ';
            for dy = 0:box_h-1
                fprintf('%s(%d, %d)  ', row_str, base_x + dx, base_y + dy);
                row_str = '';
            end
            fprintf('\n');
        end
        
        draw_styled_rects(pos, c_blue_light, 0.3, 'k');
        add_styled_label(pos, ['P' num2str(station_id)], 'k', 7);
        fprintf('\n');
    end
    fprintf('--------------------------------------------------\n');


    % 4.3 左下角区域配件 (ID: 1-12) 坐标深度监控
    fprintf('\n>> [地图监控] 正在展开左下配件仓库(ID:1-12)对应的详细格子坐标：\n');
    lb_start_x = 3; lb_top_y = 18;
    lb_bot_y = 10;
    % 假设 box_w 和 box_h 已在外部定义，通常为2
    
    % --- 第一行：工位 P1 - P6 ---
    for i = 1:6
        station_id = i;
        base_x = lb_start_x + (i-1)*(box_w+2);
        base_y = lb_top_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [工位 ID %d]: 区域起始(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('      └─ 包含的格子坐标: \n');
        
        % 嵌套循环打印格点
        for dx = 0:box_w-1
            row_str = '      ';
            for dy = 0:box_h-1
                fprintf('%s(%d, %d)  ', row_str, base_x + dx, base_y + dy);
                row_str = ''; % 仅首点缩进
            end
            fprintf('\n');
        end
        
        draw_styled_rects(pos, c_blue_dark, 0.3, 'none');
        add_styled_label(pos, ['P' num2str(station_id)], 'w', 7);
        fprintf('\n');
    end
    
    % --- 第二行：工位 P7 - P12 ---
    for i = 7:12
        station_id = i;
        base_x = lb_start_x + (i-7)*(box_w+2);
        base_y = lb_bot_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [工位 ID %d]: 区域起始(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('      └─ 包含的格子坐标: \n');
        
        % 嵌套循环打印格点
        for dx = 0:box_w-1
            row_str = '      ';
            for dy = 0:box_h-1
                fprintf('%s(%d, %d)  ', row_str, base_x + dx, base_y + dy);
                row_str = '';
            end
            fprintf('\n');
        end
        
        draw_styled_rects(pos, c_blue_dark, 0.3, 'none');
        add_styled_label(pos, ['P' num2str(station_id)], 'w', 7);
        fprintf('\n');
    end
    fprintf('--------------------------------------------------\n');

    % 4.4 大件工位区域 (分散式布局 - 送货区) 坐标深度监控
    fprintf('\n>> [地图监控] 正在展开分散式大件工位(ID:13-16)对应的9个格子详细坐标：\n');
    block_w = 3; block_h = 3;
    % 定义工位基准坐标：[13:中下, 14:中上, 15:中左, 16:中右]
    s_bases = [40, 11; 4, 36; 5, 23; 47, 23]; 
    
    for i = 1:4
        station_id = i + 12; 
        base_x = s_bases(i, 1);
        base_y = s_bases(i, 2);
        pos = [base_x, base_y, block_w, block_h];
        
        fprintf('   [工位 ID %d]: 区域起始(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('      └─ 包含的9个小格子坐标: \n');
        
        % 嵌套循环打印 9 个格点
        for dx = 0:block_w-1
            row_str = '      ';
            for dy = 0:block_h-1
                row_str = [row_str, sprintf('(%d, %d)  ', base_x + dx, base_y + dy)];
            end
            fprintf('%s\n', row_str);
        end
        
        % 绘图：统一使用浅蓝色表示工位
        draw_styled_rects(pos, c_blue_light, 0.2, 'k');
        % 根据 ID 判断标签内容
        if station_id == 16
            label_txt = '架16';
        else
            label_txt = ['架', num2str(station_id)];
        end
        
        % 调用绘图函数
        add_styled_label(pos, label_txt, 'k', 8);
        add_styled_label(pos, char(label_txt), 'k', 8);
        fprintf('\n'); 
    end
    fprintf('--------------------------------------------------\n');
    
    % 4.5 底部充电/车库区域
    % 左侧充电区
    draw_styled_rects([2, 2, 2, 2], c_green_charge, 0.5, 'none'); % 圆形效果
    add_styled_label([2, 2, 2, 2], '⚡', 'w', 10);
    
    draw_styled_rects([6, 2, 2, 2], c_green_park, 0.2, 'none');
    draw_styled_rects([10, 2, 2, 2], c_green_park, 0.2, 'none');
    
    % 右侧充电区
    draw_styled_rects([39, 2, 3, 3], c_cyan_charge, 0.5, 'none');
    add_styled_label([39, 2, 3, 3], '⚡', 'w', 12);
    
    draw_styled_rects([46, 2, 3, 3], c_green_dark, 0.2, 'none');

    % --- 5. 美化图例面板 ---
    draw_legend_panel(53, 5, ...
        {c_blue_light, c_blue_dark, c_wall, c_green_charge, c_green_park, c_cyan_charge, c_green_dark}, ...
        {'生产线工位', '配件仓库/缓存', '转向架生产线', '托举AGV充电桩', '托举AGV车库', '叉车AGV充电桩', '叉车AGV车库'});

    % 标题
    title('转向架组装生产工厂网格图', 'FontSize', 14, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2]);
end

% --- 辅助函数：绘制带样式的矩形 ---
function draw_styled_rects(rects, color, curve, edgeColor)
    % curve: 圆角程度 (0-1), 0为直角, 1为最圆
    for i = 1:size(rects, 1)
        rectangle('Position', rects(i,:), ...
            'FaceColor', color, ...
            'EdgeColor', edgeColor, ...
            'LineWidth', 1, ...
            'Curvature', [curve curve]); % 设置圆角
    end
end
% --- 核心辅助函数：绘制弧形 ---
function draw_arc_wall(center, r_in, r_out, angle_start_deg, angle_end_deg, color)
    % 1. 生成角度序列 (分辨率越高越平滑)
    theta = linspace(deg2rad(angle_start_deg), deg2rad(angle_end_deg), 50);
    
    % 2. 计算外弧坐标 (Outer Arc)
    x_out = center(1) + r_out * cos(theta);
    y_out = center(2) + r_out * sin(theta);
    
    % 3. 计算内弧坐标 (Inner Arc)
    x_in = center(1) + r_in * cos(theta);
    y_in = center(2) + r_in * sin(theta);
    
    % 4. 闭合多边形路径: 外弧 -> 内弧(反向) -> 闭合
    X = [x_out, fliplr(x_in)];
    Y = [y_out, fliplr(y_in)];
    
    % 5. 填充颜色
    patch(X, Y, color, 'EdgeColor', 'none');
end

% --- 辅助函数：添加美化标签 ---
function add_styled_label(pos, str, textColor, fontSize)
    text(pos(1)+pos(3)/2, pos(2)+pos(4)/2, str, ...
        'Color', textColor, ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', fontSize, ...
        'FontName', 'Helvetica', ... % 使用清晰的无衬线字体
        'FontWeight', 'bold');
end

% --- 辅助函数：绘制整合图例 ---
function draw_legend_panel(x, y, colors, labels)
    % 计算图例框的高度
    num_items = length(labels);
    box_h = num_items * 3 + 2;
    box_w = 16;
    
    % 绘制图例背景板 (带阴影效果)
    % 阴影
    rectangle('Position', [x+0.5, y-0.5, box_w, box_h], 'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none', 'Curvature', 0.1);
    % 主板
    rectangle('Position', [x, y, box_w, box_h], 'FaceColor', 'w', 'EdgeColor', [0.8 0.8 0.8], 'LineWidth', 1, 'Curvature', 0.1);
    
    text(x + box_w/2, y + box_h - 1.5, '图例 / Legend', 'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    % 绘制每一项
    start_y = y + box_h - 4;
    for i = 1:num_items
        % 色块
        rectangle('Position', [x+1, start_y, 2, 1.5], 'FaceColor', colors{i}, 'EdgeColor', 'none', 'Curvature', 0.2);
        % 文字
        text(x + 4, start_y + 0.75, labels{i}, 'FontSize', 9, 'Color', [0.2 0.2 0.2]);
        start_y = start_y - 3;
    end
end