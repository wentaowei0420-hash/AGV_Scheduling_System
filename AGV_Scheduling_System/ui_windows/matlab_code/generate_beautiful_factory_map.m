function generate_beautiful_factory_map()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);


    % --- 1. 鍦板浘涓庣綉鏍煎弬鏁拌缃?---
    mapWidth = 60;      % 鍦板浘鎬诲搴?
    mapHeight = 50;     % 鍦板浘鎬婚珮搴?
    gridSize = 1;       % 缃戞牸澶у皬
    
    % 鍒涘缓绐楀彛 (璋冩暣鍒嗚鲸鐜囧拰鑳屾櫙鑹?
    figure('Name', 'Factory Visualization', 'Color', [0.98 0.98 0.98], 'Position', [100, 100, 1200, 850]);
    ax = gca;
    hold on;
    axis equal;
    axis([-2 mapWidth+15 -2 mapHeight+2]); % 绋嶅井鎵╁ぇ瑙嗛噹浠ュ绾冲浘渚?
    % 銆愭柊澧炪€戯細寮哄埗娑堥櫎鍧愭爣杞村懆鍥寸殑绌虹櫧杈硅窛 (Tight Inset)
    set(ax, 'LooseInset', [0, 0, 0, 0]);
    % 璁╁潗鏍囪酱灏藉彲鑳藉～婊℃暣涓敾甯?
    set(ax, 'Position', [0.02 0.02 0.96 0.96]);
    % --- 2. 缁樺埗缃戞牸 (浼樺寲鏍峰紡) ---
    xticks(0:gridSize:mapWidth);
    yticks(0:gridSize:mapHeight);
    grid on;
    set(ax, 'GridColor', [0.7 0.7 0.7]);  % 娴呯伆鑹茬綉鏍?
    set(ax, 'GridAlpha', 0.5);            % 鍗婇€忔槑
    set(ax, 'GridLineStyle', '-');        % 铏氱嚎缃戞牸锛屾洿绮捐嚧
    set(ax, 'LineWidth', 1);
    set(ax, 'XTickLabel', {});
    set(ax, 'YTickLabel', {});
    set(ax, 'Layer', 'top');           % 缃戞牸鍦ㄦ渶搴曞眰
    
    % 鐢讳竴涓櫧鑹茬殑鐢诲竷鑳屾櫙鍖猴紝绐佸嚭宸ュ巶鍖哄煙
    rectangle('Position', [0, 0, mapWidth, mapHeight], 'FaceColor', 'w', 'EdgeColor', 'none');

    % --- 棰滆壊瀹氫箟 (涓撲笟閰嶈壊鏂规) ---
    % 鐢熶骇绾?澧欎綋 (娣辩偔鐏?
    c_wall = [0.2 0.2 0.2];    
    % 鐢熶骇绾?澧欎綋 (榛?
    c_bark = [0 0 0];  
    % 閰嶄欢宸ヤ綅 (澶╅檯钃?
    c_blue_light = [0.53 0.81 0.92]; 
    % 杞悜鏋?缂撳瓨鍖?(鏅瞾澹摑)
    c_blue_dark = [0.12 0.29 0.49];  
    % 鎵樹妇AGV鍏呯數 (娲诲姏闈?
    c_green_charge = [0.2 0.8 0.6];  
    % 鎵樹妇AGV杞﹀簱 (鎶硅尪缁?
    c_green_park = [0.6 0.8 0.5];    
    % 鍙夎溅AGV鍏呯數 (闈掕壊)
    c_cyan_charge = [0.0 0.6 0.7];   
    % 鍙夎溅AGV杞﹀簱 (妫灄缁?
    c_green_dark = [0.25 0.4 0.25];  

    % --- 3. 缁樺埗鐢熶骇绾?澧欎綋 (鍙屽姬褰㈡敼閫? ---
    
    % 鍙傛暟璁剧疆
    line_thick = 2;   % 缁熶竴鐢熶骇绾垮搴?
    r_in = 4;         % 鍐呭崐寰?
    r_out = 6;        % 澶栧崐寰?
    
    % === 鍏抽敭鍧愭爣璁＄畻 ===
    % 涓轰簡淇濇寔 U 鍨嬬粨鏋勫绉帮細
    % 1. 鍙充笂瑙掑渾蹇? (44, 42)
    % 2. 鍙充笅瑙掑渾蹇? (44, 36) -> 杩欐牱涓や釜鍦嗗績鍨傜洿璺濈涓?6
    
    top_center = [44, 42];
    bot_center = [44, 36];
    % 鐩寸嚎娈垫暟鎹?[x, y, w, h]
    project_straight = [
        2, 32, 1, 17;                 % 宸︿笂鍨傜洿澧?(涓嶅彉        
        % A. 涓婃í姊?(Top Beam)
        % 浠?X=16 鍒?X=44 (鎺ュ彸涓婂渾寮?, Y=46(鍐呮部), 鍘氬害2
        16, 46, (top_center(1) - 16), line_thick;   
        % B. 鍙崇珫姊?(Right Vertical Beam) - 鍙樼煭浜嗭紝浠呰繛鎺ヤ袱涓渾寮?
        % X=48(鍐呮部), Y浠?36(涓嬪渾蹇? 鍒?42(涓婂渾蹇?, 瀹?
        (top_center(1) + r_in), bot_center(2), line_thick, (top_center(2) - bot_center(2)); 
        % C. 涓嬫í姊?(Bottom Beam) - 璋冩暣浠ユ帴鍙充笅鍦嗗姬
        % 浠?X=16 鍒?X=44 (鎺ュ彸涓嬪渾寮?, Y=30(澶栨部,鍥犱负鍐呮部鏄?2), 鍘氬害2
        % 娉ㄦ剰锛氳繖閲孻鐢?0鏄洜涓哄唴娌挎槸32 (36-4)锛屽帤搴?锛屾墍浠ュ搴曡竟鏄?0
        16, 30, (bot_center(1) - 16), line_thick;
        % 鍏朵粬澧欎綋
        2, 21, 24, 1;                 
        2, 8, 24, 1;                  
        44, 9, 2, 19;                
    ];
    draw_styled_rects(project_straight, c_wall, 0, 'none'); 

    % 缁樺埗鍦嗗姬
    % 1. 鍙充笂瑙掑渾寮?(0搴?鍒?90搴?
    draw_arc_wall(top_center, r_in, r_out, 0, 90, c_wall);
    
    % 2. 鍙充笅瑙掑渾寮?(-90搴?鍒?0搴?
    % 杩欓噷鏄粠绔栫洿鍚戜笅鐨勭嚎(-90搴?270搴?杩炴帴鍒版按骞冲悜鍙崇殑绾?0搴?
    draw_arc_wall(bot_center, r_in, r_out, -90, 0, c_wall);

    % 澶栭儴鍥村
    walls = [0, 0, 1, 51; 0, 0, 51, 1; 51,0,1,51; 0, 51, 52, 1];
    draw_styled_rects(walls, c_bark, 0, 'none');

    % --- 4. 缁樺埗鍔熻兘鍖哄煙 ---
    
    % 4.1 澶т欢浠撳簱鍖哄煙 (鍒嗘暎寮忓竷灞€ - 鍙栬揣鍖? 鍧愭爣娣卞害鐩戞帶
    fprintf('\n>> [鍦板浘鐩戞帶] 姝ｅ湪灞曞紑鍒嗘暎寮忓ぇ浠朵粨搴?ID:13-16)瀵瑰簲鐨?9 鏍呮牸璇︾粏鍧愭爣锛歕n');
    block_w = 3; block_h = 3;
    % 瀹氫箟浠撳簱鍩哄噯鍧愭爣锛歔13:宸︿笂, 14:宸︿笅, 15:鍙充笂, 16:鍙充笅]
    w_bases = [4, 42; 18, 4; 40, 23; 47, 11]; 
    
    for i = 1:4
        station_id = i + 12; 
        base_x = w_bases(i, 1);
        base_y = w_bases(i, 2);
        pos = [base_x, base_y, block_w, block_h];
        
        fprintf('   [浠撳簱 ID %d]: 鍖哄煙璧峰(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('     鈹斺攢 鍖呭惈鐨?9 涓皬鏍呮牸鍧愭爣: \n');
        
        % 宓屽寰幆鎵撳嵃 9 涓爡鏍肩偣
        for dx = 0:block_w-1
            row_str = '      ';
            for dy = 0:block_h-1
                row_str = [row_str, sprintf('(%d, %d)  ', base_x + dx, base_y + dy)];
            end
            fprintf('%s\n', row_str);
        end
        
        % 缁樺浘锛氱粺涓€浣跨敤娣辫摑鑹茶〃绀轰粨搴?
        draw_styled_rects(pos, c_blue_dark, 0.2, 'w'); 
        label_txt = ['浠? num2str(station_id)];
        add_styled_label(pos, label_txt, 'w', 9);
        fprintf('\n'); 
    end
    fprintf('--------------------------------------------------\n');
    % 4.2 涓棿 U 鍨嬪尯鍩熷唴鐨勯厤浠?(ID: 1-12) 鍧愭爣娣卞害鐩戞帶
    fprintf('\n>> [鍦板浘鐩戞帶] 姝ｅ湪灞曞紑涓棿 U 鍨嬮厤浠跺伐浣?ID:1-12)瀵瑰簲鐨勮缁嗘爡鏍煎潗鏍囷細\n');
    box_w = 2; box_h = 2; gap_x = 3; 
    u_start_x = 17; u_top_y = 43;
    u_bot_y = 33;
    
    % --- 绗竴琛岋細宸ヤ綅 P1 - P6 ---
    for i = 1:6
        station_id = i;
        base_x = u_start_x + (i-1)*(box_w+gap_x);
        base_y = u_top_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [宸ヤ綅 ID %d]: 鍖哄煙璧峰(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('     鈹斺攢 鍖呭惈鐨勬爡鏍煎潗鏍? \n');
        
        % 宓屽寰幆鎵撳嵃 2x2 鏍呮牸鐐?
        for dx = 0:box_w-1
            row_str = '      ';
            for dy = 0:box_h-1
                fprintf('%s(%d, %d)  ', row_str, base_x + dx, base_y + dy);
                row_str = ''; % 浠呴涓偣缂╄繘
            end
            fprintf('\n');
        end
        
        draw_styled_rects(pos, c_blue_light, 0.3, 'k');
        add_styled_label(pos, ['P' num2str(station_id)], 'k', 7);
        fprintf('\n');
    end
    
    % --- 绗簩琛岋細宸ヤ綅 P7 - P12 ---
    for i = 7:12
        station_id = i;
        base_x = u_start_x + (i-7)*(box_w+gap_x);
        base_y = u_bot_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [宸ヤ綅 ID %d]: 鍖哄煙璧峰(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('     鈹斺攢 鍖呭惈鐨勬爡鏍煎潗鏍? \n');
        
        % 宓屽寰幆鎵撳嵃 2x2 鏍呮牸鐐?
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


    % 4.3 宸︿笅瑙掑尯鍩熼厤浠?(ID: 1-12) 鍧愭爣娣卞害鐩戞帶
    fprintf('\n>> [鍦板浘鐩戞帶] 姝ｅ湪灞曞紑宸︿笅閰嶄欢   浠撳簱(ID:1-12)瀵瑰簲鐨勮缁嗘爡鏍煎潗鏍囷細\n');
    lb_start_x = 3; lb_top_y = 18;
    lb_bot_y = 10;
    % 鍋囪 box_w 鍜?box_h 宸插湪澶栭儴瀹氫箟锛岄€氬父涓?2
    
    % --- 绗竴琛岋細宸ヤ綅 P1 - P6 ---
    for i = 1:6
        station_id = i;
        base_x = lb_start_x + (i-1)*(box_w+2);
        base_y = lb_top_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [宸ヤ綅 ID %d]: 鍖哄煙璧峰(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('     鈹斺攢 鍖呭惈鐨勬爡鏍煎潗鏍? \n');
        
        % 宓屽寰幆鎵撳嵃鏍呮牸鐐?
        for dx = 0:box_w-1
            row_str = '      ';
            for dy = 0:box_h-1
                fprintf('%s(%d, %d)  ', row_str, base_x + dx, base_y + dy);
                row_str = ''; % 浠呴涓偣缂╄繘
            end
            fprintf('\n');
        end
        
        draw_styled_rects(pos, c_blue_dark, 0.3, 'none');
        add_styled_label(pos, ['P' num2str(station_id)], 'w', 7);
        fprintf('\n');
    end
    
    % --- 绗簩琛岋細宸ヤ綅 P7 - P12 ---
    for i = 7:12
        station_id = i;
        base_x = lb_start_x + (i-7)*(box_w+2);
        base_y = lb_bot_y;
        pos = [base_x, base_y, box_w, box_h];
        
        fprintf('   [宸ヤ綅 ID %d]: 鍖哄煙璧峰(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('     鈹斺攢 鍖呭惈鐨勬爡鏍煎潗鏍? \n');
        
        % 宓屽寰幆鎵撳嵃鏍呮牸鐐?
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

    % 4.4 澶т欢宸ヤ綅鍖哄煙 (鍒嗘暎寮忓竷灞€ - 閫佽揣鍖? 鍧愭爣娣卞害鐩戞帶
    fprintf('\n>> [鍦板浘鐩戞帶] 姝ｅ湪灞曞紑鍒嗘暎寮忓ぇ浠跺伐浣?ID:13-16)瀵瑰簲鐨?9 鏍呮牸璇︾粏鍧愭爣锛歕n');
    block_w = 3; block_h = 3;
    % 瀹氫箟宸ヤ綅鍩哄噯鍧愭爣锛歔13:涓笅, 14:涓笂, 15:涓乏, 16:涓彸]
    s_bases = [40, 11; 4, 36; 5, 23; 47, 23]; 
    
    for i = 1:4
        station_id = i + 12; 
        base_x = s_bases(i, 1);
        base_y = s_bases(i, 2);
        pos = [base_x, base_y, block_w, block_h];
        
        fprintf('   [宸ヤ綅 ID %d]: 鍖哄煙璧峰(X:%d, Y:%d)\n', station_id, base_x, base_y);
        fprintf('     鈹斺攢 鍖呭惈鐨?9 涓皬鏍呮牸鍧愭爣: \n');
        
        % 宓屽寰幆鎵撳嵃 9 涓爡鏍肩偣
        for dx = 0:block_w-1
            row_str = '      ';
            for dy = 0:block_h-1
                row_str = [row_str, sprintf('(%d, %d)  ', base_x + dx, base_y + dy)];
            end
            fprintf('%s\n', row_str);
        end
        
        % 缁樺浘锛氱粺涓€浣跨敤娴呰摑鑹茶〃绀哄伐浣?
        draw_styled_rects(pos, c_blue_light, 0.2, 'k');
        % 鏍规嵁 ID 鍒ゆ柇鏍囩鍐呭
        if station_id == 16
            label_txt = '姊?6';
        else
            label_txt = ['鏋? num2str(station_id)];
        end
        
        % 璋冪敤缁樺浘鍑芥暟
        add_styled_label(pos, label_txt, 'k', 8);
        add_styled_label(pos, char(label_txt), 'k', 8);
        fprintf('\n'); 
    end
    fprintf('--------------------------------------------------\n');
    
    % 4.5 搴曢儴鍏呯數/杞﹀簱鍖哄煙
    % 宸︿晶鍏呯數鍖?
    draw_styled_rects([2, 2, 2, 2], c_green_charge, 0.5, 'none'); % 鍦嗗舰鏁堟灉
    add_styled_label([2, 2, 2, 2], '鈿?, 'w', 10);
    
    draw_styled_rects([6, 2, 2, 2], c_green_park, 0.2, 'none');
    draw_styled_rects([10, 2, 2, 2], c_green_park, 0.2, 'none');
    
    % 鍙充晶鍏呯數鍖?
    draw_styled_rects([39, 2, 3, 3], c_cyan_charge, 0.5, 'none');
    add_styled_label([39, 2, 3, 3], '鈿?, 'w', 12);
    
    draw_styled_rects([46, 2, 3, 3], c_green_dark, 0.2, 'none');

    % --- 5. 缇庡寲鍥句緥闈㈡澘 ---
    draw_legend_panel(53, 5, ...
        {c_blue_light, c_blue_dark, c_wall, c_green_charge, c_green_park, c_cyan_charge, c_green_dark}, ...
        {'鐢熶骇绾垮伐浣?, '閰嶄欢浠撳簱/缂撳瓨', '杞悜鏋剁敓浜х嚎', '鎵樹妇AGV鍏呯數妗?, '鎵樹妇AGV杞﹀簱', '鍙夎溅AGV鍏呯數妗?, '鍙夎溅AGV杞﹀簱'});

    % 鏍囬
    title('杞悜鏋剁粍瑁呯敓浜у伐鍘傛爡鏍煎浘', 'FontSize', 14, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2]);
end

% --- 杈呭姪鍑芥暟锛氱粯鍒跺甫鏍峰紡鐨勭煩褰?---
function draw_styled_rects(rects, color, curve, edgeColor)
    % curve: 鍦嗚绋嬪害 (0-1), 0涓虹洿瑙? 1涓烘渶鍦?
    for i = 1:size(rects, 1)
        rectangle('Position', rects(i,:), ...
            'FaceColor', color, ...
            'EdgeColor', edgeColor, ...
            'LineWidth', 1, ...
            'Curvature', [curve curve]); % 璁剧疆鍦嗚
    end
end
% --- 鏍稿績杈呭姪鍑芥暟锛氱粯鍒跺姬褰?---
function draw_arc_wall(center, r_in, r_out, angle_start_deg, angle_end_deg, color)
    % 1. 鐢熸垚瑙掑害搴忓垪 (鍒嗚鲸鐜囪秺楂樿秺骞虫粦)
    theta = linspace(deg2rad(angle_start_deg), deg2rad(angle_end_deg), 50);
    
    % 2. 璁＄畻澶栧姬鍧愭爣 (Outer Arc)
    x_out = center(1) + r_out * cos(theta);
    y_out = center(2) + r_out * sin(theta);
    
    % 3. 璁＄畻鍐呭姬鍧愭爣 (Inner Arc)
    x_in = center(1) + r_in * cos(theta);
    y_in = center(2) + r_in * sin(theta);
    
    % 4. 闂悎澶氳竟褰㈣矾寰? 澶栧姬 -> 鍐呭姬(鍙嶅悜) -> 闂悎
    X = [x_out, fliplr(x_in)];
    Y = [y_out, fliplr(y_in)];
    
    % 5. 濉厖棰滆壊
    patch(X, Y, color, 'EdgeColor', 'none');
end

% --- 杈呭姪鍑芥暟锛氭坊鍔犵編鍖栨爣绛?---
function add_styled_label(pos, str, textColor, fontSize)
    text(pos(1)+pos(3)/2, pos(2)+pos(4)/2, str, ...
        'Color', textColor, ...
        'HorizontalAlignment','center', ...
        'VerticalAlignment', 'middle', ...
        'FontSize', fontSize, ...
        'FontName', 'Helvetica', ... % 浣跨敤娓呮櫚鐨勬棤琛嚎瀛椾綋
        'FontWeight', 'bold');
end

% --- 杈呭姪鍑芥暟锛氱粯鍒舵暣鍚堝浘渚?---
function draw_legend_panel(x, y, colors, labels)
    % 璁＄畻鍥句緥妗嗙殑楂樺害
    num_items = length(labels);
    box_h = num_items * 3 + 2;
    box_w = 16;
    
    % 缁樺埗鍥句緥鑳屾櫙鏉?(甯﹂槾褰辨晥鏋?
    % 闃村奖
    rectangle('Position', [x+0.5, y-0.5, box_w, box_h], 'FaceColor', [0.8 0.8 0.8], 'EdgeColor', 'none', 'Curvature', 0.1);
    % 涓绘澘
    rectangle('Position', [x, y, box_w, box_h], 'FaceColor', 'w', 'EdgeColor', [0.8 0.8 0.8], 'LineWidth', 1, 'Curvature', 0.1);
    
    text(x + box_w/2, y + box_h - 1.5, '鍥?渚?/ Legend', 'FontSize', 11, 'FontWeight', 'bold', 'HorizontalAlignment', 'center');

    % 缁樺埗姣忎竴椤?
    start_y = y + box_h - 4;
    for i = 1:num_items
        % 鑹插潡
        rectangle('Position', [x+1, start_y, 2, 1.5], 'FaceColor', colors{i}, 'EdgeColor', 'none', 'Curvature', 0.2);
        % 鏂囧瓧
        text(x + 4, start_y + 0.75, labels{i}, 'FontSize', 9, 'Color', [0.2 0.2 0.2]);
        start_y = start_y - 3;
    end
end



