function verify_conflict_resolution_with_3D()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % =========================================================================
    % 鏋佺畝澶?AGV 鍐茬獊娑堣В楠岃瘉浠跨湡 (甯?X-Y-T 涓夌淮鏃剁┖鎶曞奖鍥?- 瀹岀編淇鐗?
    % =========================================================================
    clc; clear; close all;
    
    global mapW mapH;
    mapW = 30; mapH = 30;
    
    disp('====================================================');
    disp('>> 浠跨湡寮€濮嬶細缁忓吀鐩稿悜鍐茬獊楠岃瘉娴嬭瘯');
    disp('====================================================');
    
    % --- 1. 鍒濆鍖?AGV 鍙傛暟 ---
    AGVs(1).id = 1;
    AGVs(1).pos = [15, 1];          % 璧风偣
    AGVs(1).target = [15, 30];      % 缁堢偣
    AGVs(1).battery = 73;           % 鐢甸噺 73%
    AGVs(1).rem_time = 500;         % 鍓╀綑鏃堕棿
    AGVs(1).status = 'Moving_Pick'; % 鐘舵€? 鍙栬揣
    AGVs(1).step_dur = 2;           % 涓ゆ璧颁竴鏍?(蹇溅)
    
    AGVs(2).id = 2;
    AGVs(2).pos = [15, 30];         % 璧风偣
    AGVs(2).target = [15, 1];       % 缁堢偣
    AGVs(2).battery = 86;           % 鐢甸噺 86%
    AGVs(2).rem_time = 230;         % 鍓╀綑鏃堕棿
    AGVs(2).status = 'Moving_Drop'; % 鐘舵€? 閫佽揣
    AGVs(2).step_dur = 3;           % 涓夋璧颁竴鏍?(鎱㈣溅)
    
    for k = 1:2
        AGVs(k).path = [];
        AGVs(k).path_idx = 1;
        AGVs(k).move_timer = 0;
        AGVs(k).finished = false;
        AGVs(k).path = simple_astar(AGVs(k).pos, AGVs(k).target, zeros(mapH, mapW));
    end
    
    % 鐢ㄤ簬璁板綍鏃剁┖杞ㄨ抗鐨勬暟缁?
    traj_1 = []; 
    traj_2 = [];
    
    % --- 2. 鍒濆鍖?2D 鍙鍖栫晫闈?---
    fig_2d = figure('Name', '2D 瀹炴椂闃茬鎾炲姩鐢?, 'Position', [50, 100, 600, 600], 'Color', 'w');
    hold on; grid on; axis equal;
    axis([0.5, mapW+0.5, 0.5, mapH+0.5]);
    set(gca, 'YDir', 'reverse');
    title('AGV 瀹炴椂鍐茬獊鍔ㄦ€佹秷瑙?(2D 淇鍥?', 'FontSize', 14);
    
    colors = lines(2);
    p1 = plot(AGVs(1).pos(2), AGVs(1).pos(1), 's', 'MarkerSize', 15, 'MarkerFaceColor', colors(1,:), 'MarkerEdgeColor', 'k');
    p2 = plot(AGVs(2).pos(2), AGVs(2).pos(1), 'o', 'MarkerSize', 15, 'MarkerFaceColor', colors(2,:), 'MarkerEdgeColor', 'k');
    line1 = plot(AGVs(1).path(:,2), AGVs(1).path(:,1), '--', 'Color', colors(1,:), 'LineWidth', 1);
    line2 = plot(AGVs(2).path(:,2), AGVs(2).path(:,1), '--', 'Color', colors(2,:), 'LineWidth', 1);
    legend([p1, p2], {'AGV 1 (蹇溅)', 'AGV 2 (鎱㈣溅)'}, 'Location', 'northeast');
    
    % --- 3. 浠跨湡涓诲惊鐜?---
    t = 0;
    while ~(AGVs(1).finished && AGVs(2).finished) && t < 300
        t = t + 1;
        
        for k = 1:2
            if AGVs(k).finished
                continue; 
            end
            
            if AGVs(k).move_timer > 0
                AGVs(k).move_timer = AGVs(k).move_timer - 1;
                continue;
            end
            
            if AGVs(k).path_idx >= size(AGVs(k).path, 1)
                AGVs(k).finished = true;
                fprintf('[T=%d] AGV-%d 鍒拌揪缁堢偣锛乗n', t, k);
                continue;
            end
            
            next_node = AGVs(k).path(AGVs(k).path_idx + 1, :);
            other_id = 3 - k;
            other_pos = AGVs(other_id).pos;
            
            if ~AGVs(other_id).finished && AGVs(other_id).path_idx < size(AGVs(other_id).path, 1)
                other_next = AGVs(other_id).path(AGVs(other_id).path_idx + 1, :);
            else
                other_next = other_pos;
            end
            
            % =========================================================
            % [鏍稿績淇鍖篯锛氬崟姝ュ墠鐬讳笌鍐茬獊妫€娴?
            is_conflict = false;
            if isequal(next_node, other_pos) && isequal(other_next, AGVs(k).pos)
                is_conflict = true;
            elseif isequal(next_node, other_pos) || isequal(next_node, other_next)
                is_conflict = true;
            end
            
            will_move = true; % 鐗╃悊绉诲姩鍏佽鏍囧織浣?
            
            if is_conflict
                fprintf('\n[T=%d] 馃毃 鎺㈡祴鍒扮墿鐞嗗共娑?(AGV-%d -> AGV-%d)\n', t, k, other_id);
                score_self = calculate_ahp_score(AGVs(k));
                score_other = calculate_ahp_score(AGVs(other_id));
                
                % 鍔犲叆 ID 浣滀负骞冲眬鍐宠儨鏉′欢 (Tie-breaker)
                if score_self < score_other || (score_self == score_other && k > other_id)
                    fprintf('   -> 鈿栵笍 鍒ゅ喅: AGV-%d 浼樺厛绾т綆锛屾墽琛岄噸瑙勫垝缁曡锛乗n', k);
                    temp_map = zeros(mapH, mapW);
                    temp_map(other_pos(1), other_pos(2)) = 1;
                    temp_map(other_next(1), other_next(2)) = 1;
                    
                    new_path = simple_astar(AGVs(k).pos, AGVs(k).target, temp_map);
                    
                    if ~isempty(new_path)
                        AGVs(k).path = new_path;
                        AGVs(k).path_idx = 1;
                        next_node = AGVs(k).path(2, :);
                        if k == 1, set(line1, 'XData', new_path(:,2), 'YData', new_path(:,1));
                        else, set(line2, 'XData', new_path(:,2), 'YData', new_path(:,1)); end
                        % 缁曡矾鎴愬姛锛屾湰鍥炲悎鍏佽鎸夋柊璺嚎绉诲姩
                    else
                        % 缁曡澶辫触锛屽彇娑堟湰娆＄Щ鍔紝鍘熷湴姝荤瓑
                        fprintf('   -> 鉂?鏃犺矾鍙粫锛屽師鍦版绛夈€俓n');
                        will_move = false; 
                        AGVs(k).move_timer = 2; 
                    end
                else
                    % 楂樹紭鍏堢骇杞﹀彇娑堟湰娆＄Щ鍔紝鍘熷湴鍋滄粸楦ｇ瑳锛岀瓑寰呭鏂归┒绂?
                    fprintf('   -> 鈿栵笍 鍒ゅ喅: AGV-%d 浼樺厛绾ч珮锛屽師鍦伴福绗涚瓑寰呭鏂硅璺€俓n', k);
                    will_move = false; 
                    AGVs(k).move_timer = 1; 
                end
            end
            
            % 鍙湁琚厑璁哥Щ鍔ㄦ椂锛屾墠鎺ㄨ繘鍧愭爣鍜岃矾寰勭储寮?
            if will_move
                AGVs(k).pos = next_node;
                AGVs(k).path_idx = AGVs(k).path_idx + 1;
                AGVs(k).move_timer = AGVs(k).step_dur;
            end
            % =========================================================
        end
        
        % 璁板綍姣忎釜鏃堕棿姝ョ殑鏃剁┖鍧愭爣 X(鍒?, Y(琛?, T
        if ~AGVs(1).finished
            traj_1 = [traj_1; AGVs(1).pos(2), AGVs(1).pos(1), t];
        else
            traj_1 = [traj_1; AGVs(1).target(2), AGVs(1).target(1), t]; % 鍒拌揪缁堢偣鍚庣户缁湪鍘熶綅缃褰曟椂闂存祦閫?
        end
        
        if ~AGVs(2).finished
            traj_2 = [traj_2; AGVs(2).pos(2), AGVs(2).pos(1), t];
        else
            traj_2 = [traj_2; AGVs(2).target(2), AGVs(2).target(1), t];
        end
        
        % 鏇存柊鍔ㄧ敾
        set(p1, 'XData', AGVs(1).pos(2), 'YData', AGVs(1).pos(1));
        set(p2, 'XData', AGVs(2).pos(2), 'YData', AGVs(2).pos(1));
        drawnow;
    end
    disp('====================================================');
    disp('>> 浠跨湡缁撴潫锛屽噯澶囩粯鍒?3D 鏃剁┖杞ㄨ抗鍥?..');
    
    % --- 4. 缁樺埗绗﹀悎楂樿川閲忓鏈爣鍑嗙殑 X-Y-T 鏃剁┖铻烘棆鍥?---
    fig_3d = figure('Name', '鐩稿悜鍐茬獊娑堣В鍚庤矾寰勫叧绯诲浘', 'Position', [700, 100, 700, 700], 'Color', 'w');
    hold on; grid on;
    view(-40, 25); % 璋冩暣涓烘渶浣崇殑鍊炬枩淇閫忚
    
    % 瀹氫箟绾鐨勫鏈厤鑹?(浜豢涓庢鑹?
    color_agv1 = [0.1, 0.9, 0.1]; % 浜豢 (蹇溅/缁曡)
    color_agv2 = [1.0, 0.5, 0.1]; % 姗欒壊 (鎱㈣溅/鐩磋)
    
    % 缁樺埗 AGV 1 鐨?3D 鏃剁┖瀹炵嚎
    p1 = plot3(traj_1(:,1), traj_1(:,2), traj_1(:,3), '-', ...
        'Color', color_agv1, 'LineWidth', 1, 'DisplayName', 'AGV1');
    
    % 缁樺埗 AGV 2 鐨?3D 鏃剁┖瀹炵嚎
    p2 = plot3(traj_2(:,1), traj_2(:,2), traj_2(:,3), '-', ...
        'Color', color_agv2, 'LineWidth', 1, 'DisplayName', 'AGV2');
    
    % 缁樺埗搴曢儴鐨?2D 绌洪棿鎶曞奖铏氱嚎 (灏?Z 杞村己鍒跺綊闆?
    plot3(traj_1(:,1), traj_1(:,2), zeros(size(traj_1(:,3))), '--', ...
        'Color', color_agv1, 'LineWidth', 1, 'HandleVisibility', 'off');
    plot3(traj_2(:,1), traj_2(:,2), zeros(size(traj_2(:,3))), '--', ...
        'Color', color_agv2, 'LineWidth', 1, 'HandleVisibility', 'off');
    
    % 鍧愭爣杞磋寖鍥翠笌鏂瑰悜
    xlim([1, 30]); 
    ylim([1, 30]); 
    zlim([0, max(t) + 10]);
    set(gca, 'YDir', 'reverse'); 
    set(gca, 'XTick', 0:5:30, 'YTick', 0:5:30, 'ZTick', 0:20:max(t)+10);
    
    % 鍏ㄥ眬瀛椾綋涓庤竟妗嗚缃?(瀛︽湳鏍囬厤)
    set(gca, 'FontName', 'Times New Roman', 'FontSize', 12);
    set(gca, 'Box', 'on', 'LineWidth', 1); 
    set(gca, 'GridLineStyle', '-', 'GridColor', [0.7 0.7 0.7], 'GridAlpha', 0.4); 
    
    % 鍧愭爣杞存爣绛?(LaTeX 鏂滀綋瑙勮寖)
    xlabel('\it x', 'FontSize', 16, 'FontWeight', 'bold');
    ylabel('\it y', 'FontSize', 16, 'FontWeight', 'bold');
    zlabel('\it t', 'FontSize', 16, 'FontWeight', 'bold', 'Rotation', 0, 'HorizontalAlignment', 'right');
    
    % 鍥句緥璁剧疆
    lgd = legend([p1, p2], 'Location', 'northeast');
    set(lgd, 'FontName', 'Times New Roman', 'FontSize', 11, 'Box', 'on');
    
    rotate3d on;
    disp('>> [瀹屾垚] 3D 鏃剁┖鍥惧凡鐢熸垚锛屽彲鐩存帴瀵煎嚭鏀惧叆璁烘枃銆?);
end

% =========================================================================
% 杈呭姪鍑芥暟 1锛欰HP 鍔ㄦ€佷紭鍏堢骇璁＄畻
% =========================================================================
function score = calculate_ahp_score(agv)
    w = [0.6370, 0.1047, 0.2583]; 
    s_status = 0;
    if strcmp(agv.status, 'Moving_Drop'), s_status = 0.7; 
    elseif strcmp(agv.status, 'Moving_Pick'), s_status = 0.4; 
    end
    s_battery = (100 - agv.battery) / 100.0;
    s_time = max(0, 1 - (agv.rem_time / 1000));
    score = w(1)*s_status + w(2)*s_battery + w(3)*s_time;
end

% =========================================================================
% 杈呭姪鍑芥暟 2锛氭瀬绠€浜岀淮 A* 璺緞瑙勫垝绠楁硶
% =========================================================================
function path = simple_astar(start_pos, goal_pos, obstacle_map)
    [mapH, mapW] = size(obstacle_map);
    dirs = [-1 0; 1 0; 0 -1; 0 1];
    openList = start_pos;
    gScore = inf(mapH, mapW); gScore(start_pos(1), start_pos(2)) = 0;
    fScore = inf(mapH, mapW); fScore(start_pos(1), start_pos(2)) = sum(abs(start_pos - goal_pos));
    cameFrom_r = zeros(mapH, mapW); cameFrom_c = zeros(mapH, mapW);
    
    while ~isempty(openList)
        [~, min_idx] = min(fScore(sub2ind([mapH, mapW], openList(:,1), openList(:,2))));
        curr = openList(min_idx, :);
        if isequal(curr, goal_pos)
            path = curr;
            while cameFrom_r(curr(1), curr(2)) ~= 0
                pr = cameFrom_r(curr(1), curr(2)); pc = cameFrom_c(curr(1), curr(2));
                curr = [pr, pc]; path = [curr; path]; %#ok<AGROW>
            end
            return;
        end
        openList(min_idx, :) = [];
        for i = 1:4
            neighbor = curr + dirs(i, :); nr = neighbor(1); nc = neighbor(2);
            if nr >= 1 && nr <= mapH && nc >= 1 && nc <= mapW && obstacle_map(nr, nc) == 0
                tentative_gScore = gScore(curr(1), curr(2)) + 1;
                if tentative_gScore < gScore(nr, nc)
                    cameFrom_r(nr, nc) = curr(1); cameFrom_c(nr, nc) = curr(2);
                    gScore(nr, nc) = tentative_gScore; fScore(nr, nc) = tentative_gScore + sum(abs(neighbor - goal_pos));
                    if ~ismember(neighbor, openList, 'rows'), openList = [openList; neighbor]; %#ok<AGROW>
                    end
                end
            end
        end
    end
    path = []; 
end


