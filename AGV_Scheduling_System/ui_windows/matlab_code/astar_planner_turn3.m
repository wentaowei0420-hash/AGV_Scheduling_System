function [path, gScore_goal, turn_count, expanded_nodes, path_length, gScore_matrix, turnPenalty] = astar_planner_turn3(map, start, goal, payload_weight, cost_map, agv_type)
%% 初始化转向惩罚
    if nargin < 5
        cost_map = [];
    end
    if nargin < 6 || isempty(agv_type)
        agv_type = 1;
    end

    if agv_type == 2
        base_penalty = 1.35;      % 叉车式AGV空载时转向惩罚更大
    else
        base_penalty = 0.90;      % 托举式AGV空载时机动性更好
    end
    linear_factor = 0.00001;      % 线性载荷因子
    inertia_factor = 3/640000;    % 二阶惯性因子
    turnPenalty = base_penalty + linear_factor * payload_weight + inertia_factor * (payload_weight^2);
    [rows, cols] = size(map);
%% 璧风偣鎴栫粓鐐逛綅浜庨殰纰嶇墿鍐?--->鐩存帴杩斿洖绌鸿矾寰?
    if map(start(1), start(2)) == 1 || map(goal(1), goal(2)) == 1
        path = []; 
        gScore_goal = inf; 
        turn_count = 0; 
        expanded_nodes = 0; 
        path_length = 0; 
        gScore_matrix = []; return; % 杩斿洖绌虹粨鏋?
    end
%% 棰勮绠楀叏灞€鑷€傚簲鍙傛暟
    dist_start_to_goal = sqrt((start(1) - goal(1))^2 + (start(2) - goal(2))^2); % 璧风偣鍒扮粓鐐圭殑娆у嚑閲屽緱璺濈
    if dist_start_to_goal == 0
        dist_start_to_goal = 1e-6; % 閬垮厤闄ら浂锛屽綋璧风偣绛変簬缁堢偣鏃惰涓烘瀬灏忓€?
    end
    
    % --- 3. 寤虹珛 3D 鐘舵€佺┖闂寸煩闃?[Row, Col, Direction] ---
    % 缁村害3琛ㄧず椹跺叆璇ユ爡鏍肩殑鏂瑰悜: 1=鍖?-1,0), 2=鍗?1,0), 3=瑗?0,-1), 4=涓?0,1)
    numNodes3D = rows * cols * 4; % 涓夌淮鐘舵€佺┖闂寸殑鎬昏妭鐐规暟
    gScore = inf(rows, cols, 4);  % 浠庤捣鐐瑰埌姣忎釜鐘舵€?(r,c,d) 鐨勫疄闄呬唬浠凤紝鍒濆涓烘棤绌峰ぇ
    fScore = inf(rows, cols, 4);  % 浼拌鎬讳唬浠?g + h锛屽垵濮嬩负鏃犵┓澶?
    parent_idx = zeros(rows, cols, 4); % 璁板綍姣忎釜鐘舵€佺殑鍓嶉┍鑺傜偣锛堜笁缁寸储寮曪級
    
    openList = [];                 % 寮€鏀惧垪琛紝瀛樻斁寰呮墿灞曡妭鐐圭殑涓夌淮绾挎€х储寮?
    openMask = false(numNodes3D, 1); % 甯冨皵鎺╃爜锛屾爣璁版煇涓笁缁寸储寮曟槸鍚﹀湪寮€鏀惧垪琛ㄤ腑
    
%% 鍒濆鍖栬捣鐐癸紙璧锋鏃舵湞鍚戞湭鐭ワ紝鍥犳灏?涓柟鍚戝叏濉炲叆寮€鏀惧垪琛紝浠ｄ环涓?锛?
    for d = 1:4
        gScore(start(1), start(2), d) = 0; % 璧风偣鍥涗釜鏂瑰悜鐨刧浠ｄ环鍧囦负0
        fScore(start(1), start(2), d) = abs(start(1)-goal(1)) + abs(start(2)-goal(2)); % 鍚彂寮忥細鏇煎搱椤胯窛绂?
        idx3D = start(1) + (start(2)-1)*rows + (d-1)*(rows*cols); % 灏嗕笁缁村潗鏍囪浆鎹负绾挎€х储寮?
        openList(end+1) = idx3D;   % 灏嗙储寮曞姞鍏ュ紑鏀惧垪琛?
        openMask(idx3D) = true;    % 鏍囪璇ョ储寮曞湪寮€鏀惧垪琛ㄤ腑
    end
    
    dirVecs = [-1, 0; 1, 0; 0, -1; 0, 1]; % 鍥涗釜鏂瑰悜瀵瑰簲鐨勮銆佸垪鍙樺寲锛氬寳銆佸崡銆佽タ銆佷笢
    
    pathFound = false;               % 鏄惁鎵惧埌璺緞鐨勬爣蹇?
    expanded_nodes = 0;               % 璁板綍鎵╁睍鐨勮妭鐐规暟锛堜笁缁寸姸鎬佽鏁帮級
    bestGoalIdx3D = -1;               % 鍒拌揪鐩爣鏃跺搴旂殑鏈€浣充笁缁寸储寮?
    
    while ~isempty(openList)
        [~, minPos] = min(fScore(openList)); % 鍦ㄥ紑鏀惧垪琛ㄤ腑鎵惧嚭fScore鏈€灏忕殑浣嶇疆
        curr3D = openList(minPos);      % 鑾峰彇璇ヨ妭鐐圭殑涓夌淮绾挎€х储寮?
        expanded_nodes = expanded_nodes + 1; % 鎵╁睍鑺傜偣鏁板姞1
        
        openList(minPos) = [];               % 浠庡紑鏀惧垪琛ㄤ腑绉婚櫎璇ヨ妭鐐?
        openMask(curr3D) = false;            % 鏇存柊鎺╃爜锛屾爣璁颁笉鍦ㄥ紑鏀惧垪琛?
        
        % 灏嗕笁缁寸嚎鎬х储寮曡浆鎹㈠洖 (r,c,d)
        rem_idx = curr3D - 1;                % 杞负0鍩虹储寮曟柟渚胯绠?
        currD = floor(rem_idx / (rows * cols)) + 1; % 鏂瑰悜鍒嗛噺锛?~4
        rem_idx = mod(rem_idx, rows * cols);       % 鍓╀綑閮ㄥ垎
        currC = floor(rem_idx / rows) + 1;         % 鍒楀潗鏍?
        currR = mod(rem_idx, rows) + 1;             % 琛屽潗鏍?
        
        % 濡傛灉褰撳墠鑺傜偣浣嶇疆灏辨槸鐩爣鐐癸紝鍒欐垚鍔熸壘鍒拌矾寰勶紝璺冲嚭寰幆
        if currR == goal(1) && currC == goal(2)
            pathFound = true;
            bestGoalIdx3D = curr3D; % 璁板綍鍒拌揪鐩爣鐨勪笁缁寸储寮?
            break;
        end
        
        % 閬嶅巻鍥涗釜鍙兘鐨勫墠杩涙柟鍚戯紙閭诲眳锛?
        for nD = 1:4
            nR = currR + dirVecs(nD, 1);       % 閭诲眳鐨勮鍧愭爣
            nC = currC + dirVecs(nD, 2);       % 閭诲眳鐨勫垪鍧愭爣
            
            % 妫€鏌ユ槸鍚﹀湪鍦板浘鑼冨洿鍐呬笖涓嶆槸闅滅鐗?
            if nR < 1 || nR > rows || nC < 1 || nC > cols || map(nR, nC) == 1
                continue; % 鏃犳晥閭诲眳锛岃烦杩?
            end
            
            % 鍦板舰浠ｄ环锛氶粯璁?.0锛屽鏋滄彁渚涗簡cost_map鍒欎娇鐢ㄥ搴旀爡鏍肩殑浠ｄ环
            terrain_cost = 1.0; 
            if nargin >= 5 && ~isempty(cost_map)
                if nR <= size(cost_map, 1) && nC <= size(cost_map, 2)
                    terrain_cost = cost_map(nR, nC);
                end
            end
            
            % 鍒濇璁＄畻鍒拌揪閭诲眳鐨刧浠ｄ环锛氬綋鍓峠 + 绉诲姩浠ｄ环锛堝熀纭€1.0 * 鍦板舰浠ｄ环锛?
            tentative_gScore = gScore(currR, currC, currD) + 1.0 * terrain_cost;
            
            % 鍒ゆ柇鏄惁鏄捣濮嬭妭鐐癸紙璧风偣涓嶈€冭檻杞集鎯╃綒锛屽洜涓哄垰鍑哄彂娌℃湁鏂瑰悜锛?
            isStartNode = (currR == start(1) && currC == start(2));
            if ~isStartNode && nD ~= currD
                % 濡傛灉涓嶆槸璧风偣涓旀柟鍚戞敼鍙橈紝鍒欏姞涓婅浆鍚戞儵缃?
                tentative_gScore = tentative_gScore + turnPenalty; 
            end
            
            % 鐘舵€佹洿鏂帮細濡傛灉鏂扮殑g鍊兼瘮鍘熸潵璁板綍鐨勬洿灏忥紝鍒欐洿鏂拌鐘舵€?
            if tentative_gScore < gScore(nR, nC, nD)
                gScore(nR, nC, nD) = tentative_gScore;          % 鏇存柊g鍊?
                parent_idx(nR, nC, nD) = curr3D;                % 璁板綍鍓嶉┍绱㈠紩
                
                % 璁＄畻鍚彂寮廻锛堟浖鍝堥】璺濈锛?
                h_base = abs(nR - goal(1)) + abs(nC - goal(2));
                
                % 鑷€傚簲鏉冮噸鍥犲瓙锛氭牴鎹綋鍓嶇偣鍒扮洰鏍囩殑璺濈涓庤捣鐐瑰埌鐩爣璺濈鐨勬瘮鍊肩敓鎴愪竴涓帇缂╃殑鎸囨暟椤?
                dist_current_to_goal = sqrt((nR - goal(1))^2 + (nC - goal(2))^2); % 褰撳墠鐐瑰埌鐩爣鐨勬姘忚窛绂?
                a_raw = exp(dist_current_to_goal / dist_start_to_goal) - 1.0;    % 鍘熷鎸囨暟鍥犲瓙
                a_compressed = a_raw * 0.4;                                      % 鍘嬬缉绯绘暟0.4
                
                % 鏈€缁堢殑fScore = g + h * (1 + a_compressed)  鈥斺€?鍚彂寮忔潈閲嶈嚜閫傚簲
                fScore(nR, nC, nD) = tentative_gScore + h_base * (1.0 + a_compressed);
                
                % 璁＄畻閭诲眳鐨勪笁缁寸嚎鎬х储寮?
                neighbor3D = nR + (nC-1)*rows + (nD-1)*(rows*cols);
                
                % 濡傛灉閭诲眳涓嶅湪寮€鏀惧垪琛ㄤ腑锛屽垯鍔犲叆寮€鏀惧垪琛?
                if ~openMask(neighbor3D)
                    openList(end+1) = neighbor3D; %#ok<AGROW> 杩藉姞鍒板紑鏀惧垪琛?
                    openMask(neighbor3D) = true;  % 鏍囪鍦ㄥ紑鏀惧垪琛ㄤ腑
                end
            end
        end
    end

    % 濡傛灉鎵惧埌璺緞锛屽洖婧瀯寤鸿矾寰?
    if pathFound
        curr = bestGoalIdx3D; % 浠庣洰鏍囩姸鎬佺殑涓夌淮绱㈠紩寮€濮嬪洖婧?
        path_list = [];       % 瀛樺偍璺緞鐐圭殑鍒楄〃锛堟寜椤哄簭锛?
        
        while curr ~= 0       % 褰撳墠绱㈠紩闈為浂琛ㄧず杩樻湁鍓嶉┍锛堣捣鐐圭殑鍓嶉┍涓?锛?
            % 灏嗕笁缁寸嚎鎬х储寮曡浆鎹负 (r,c)
            rem_idx = curr - 1;
            rem_idx = mod(rem_idx, rows * cols);
            c = floor(rem_idx / rows) + 1;
            r = mod(rem_idx, rows) + 1;
            
            path_list = [[r, c]; path_list]; % 灏嗙偣鎻掑叆鍒板垪琛ㄥ墠闈紝淇濊瘉浠庤捣鐐瑰埌缁堢偣椤哄簭
            
            % 濡傛灉宸茬粡鍥炴函鍒拌捣鐐癸紝鍒欏仠姝紙璧风偣鐨刾arent_idx涓?锛屼絾杩欓噷闇€瑕佸垽鏂綅缃級
            if r == start(1) && c == start(2)
                break;
            end
            
            % 鑾峰彇褰撳墠鐘舵€佺殑鏂瑰悜锛屼互渚挎壘鍒板搴旂殑鍓嶉┍
            currD = floor((curr - 1) / (rows * cols)) + 1;
            curr = parent_idx(r, c, currD);  % 鏇存柊涓哄墠椹辩殑涓夌淮绱㈠紩
        end
        
        path = path_list; % 鏈€缁堣矾寰勶紝鎸夎捣鐐瑰埌缁堢偣椤哄簭鎺掑垪
        
        % 鍙栫洰鏍囩偣鎵€鏈夋柟鍚戜腑鏈€灏忕殑g鍊间綔涓哄埌杈剧洰鏍囩殑浠ｄ环
        gScore_goal = min(gScore(goal(1), goal(2), :)); 
        
        path_length = size(path, 1); % 璺緞闀垮害锛堟爡鏍肩偣鏁帮級
        
        % 璁＄畻杞悜娆℃暟锛氶€氳繃鐩搁偦绉诲姩鍚戦噺鐨勫彉鍖栨潵妫€娴嬫柟鍚戝彉鍖?
        turn_count = 0;
        if size(path, 1) > 2
            diffs = diff(path);          % 璁＄畻鐩搁偦鐐逛箣闂寸殑浣嶇Щ鍚戦噺
            for i = 2:size(diffs, 1)
                if ~isequal(diffs(i,:), diffs(i-1,:)) % 濡傛灉褰撳墠浣嶇Щ涓庝笂涓€涓笉鍚岋紝璇存槑杞悜
                    turn_count = turn_count + 1;
                end
            end
        end
    else
        % 鏈壘鍒拌矾寰勶紝杩斿洖绌哄€?
        path = []; gScore_goal = inf; turn_count = 0; path_length = 0; 
    end
    
    % 璁＄畻浜岀淮gScore鐭╅樀锛堝彇鍚勬柟鍚戞渶灏忓€硷級锛岀敤浜庡彲瑙嗗寲鎴栫粺璁?
    gScore_matrix = min(gScore, [], 3);
    
    % 璁＄畻鎵╁睍杩囩殑浜岀淮鏍呮牸鏁伴噺锛堝嵆gScore_matrix涓湁闄愬€肩殑涓暟锛?
    explored_2d_mask = (gScore_matrix ~= inf);
    expanded_nodes = sum(explored_2d_mask, 'all');
end
