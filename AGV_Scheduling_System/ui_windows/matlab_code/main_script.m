style = agv_plot_theme();
init_agv_plot_defaults(style);
% 鍦板浘灏哄
map_size = 50;
mapSize = [map_size, map_size];          
% 闅忔満闅滅鐗╂鐜?
p_obstacle = 0.25;             % 30% 鐨勬牸瀛愪负闅滅
% 鐢熸垚闅忔満鍦板浘
randMat = rand(mapSize);      % 鐢熸垚 [0,1) 鍧囧寑闅忔満鏁扮煩闃?
map = randMat < p_obstacle;   % 灏忎簬 p 鐨勪负闅滅 (1)锛屽叾浣欎负鑷敱 (0)
% 姝ゆ椂 map 鏄竴涓?logical 鐭╅樀锛屼絾 A* 鍑芥暟瑕佹眰 double 绫诲瀷锛屽彲浠ヨ浆鎹細
map = double(map);            % 灏?logical 杞崲涓?double (0/1)
start = [2,2];
rows = mapSize(1);
cols = mapSize(2);
goal = [rows-1,cols-2];
% 瀹氫箟杞集鎯╃綒鍊硷紙鍙牴鎹渶瑕佽皟鏁达級
turnPenalty1 = 3.012;
turnPenalty2 = 3;
% 纭繚璧风偣鍜岀粓鐐逛笉鏄殰纰?
map(start(1), start(2)) = 0;
map(goal(1), goal(2))   = 0;
% 璋冪敤涓夌绠楁硶锛堣幏鍙栨柊澧炵殑 gScore_matrix锛?
[path, gScore, turn_count, expanded_nodes, path_length, gScore_matrix]      = astar_planner(map, start, goal, 1);
%[path1, gScore1, turn_count1, expanded_nodes1, path_length1, gScore_matrix1]  = astar_planner_turn(map, start, goal, turnPenalty1);
[path2, gScore2, turn_count2, expanded_nodes2, path_length2, gScore_matrix2]  = dijkstra_planner(map, start, goal);
[path3, gScore3, turn_count3, expanded_nodes3, path_length3, gScore_matrix3,turnPenalty3]  = astar_planner_turn3(map, start, goal, 0);
[path4, gScore4, turn_count4, expanded_nodes4, path_length4, gScore_matrix4,turnPenalty4]  = astar_planner_turn3(map, start, goal, 80);
[path5, gScore5, turn_count5, expanded_nodes5, path_length5, gScore_matrix5,turnPenalty5] = astar_planner_turn3(map, start, goal, 150);
% 瀛愬浘1: A* 浼犵粺
if ~isempty(path)
    f = figure;  % 鏂板缓鍥惧舰绐楀彛
    ax = gca;    % 鑾峰彇褰撳墠鍧愭爣杞?
    plot_path_result(map, path, start, goal, path_length, turn_count, expanded_nodes, ...
                     sprintf('浼犵粺A*绠楁硶 '), ax, gScore_matrix);
else
    figure;
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12);
    axis off;
    title('A* (鍔ㄦ€佽浆寮儵缃?');
end

% % 瀛愬浘2: A* 杞集鎯╃綒 1
% subplot(2,3,2);
% if ~isempty(path1)
%     plot_path_result(map, path1, start, goal, path_length1, turn_count1, expanded_nodes1, ...
%                      sprintf('A* (杞集鎯╃綒: %.2f)', turnPenalty1), gca, gScore_matrix1);
% else
%     text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (杞集鎯╃綒 1)');
% end

% 瀛愬浘3: Dijkstra
if ~isempty(path2)
    f = figure;  % 鏂板缓鍥惧舰绐楀彛
    ax = gca;    % 鑾峰彇褰撳墠鍧愭爣杞?
    plot_path_result(map, path2, start, goal, path_length2, turn_count2, expanded_nodes2, ...
                     sprintf('Dijkstra绠楁硶'), ax, gScore_matrix2);
else
    figure;
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12);
    axis off;
    title('A* (鍔ㄦ€佽浆寮儵缃?');
end

% 瀛愬浘4: A* 闅滅鐜?
if ~isempty(path3)
    f = figure;  % 鏂板缓鍥惧舰绐楀彛
    ax = gca;    % 鑾峰彇褰撳墠鍧愭爣杞?
    plot_path_result(map, path3, start, goal, path_length3, turn_count3, expanded_nodes3, ...
                     sprintf('鏀硅繘A*绠楁硶 (鏈夋晥璐熻浇: %.2f)', 0), ax, gScore_matrix3);
else
    figure;
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12);
    axis off;
    title('A* (鍔ㄦ€佽浆寮儵缃?');
end
% 瀛愬浘5: A* 闅滅鐜?鍔ㄦ€佽浆寮儵缃?
if ~isempty(path4)
    f = figure;  % 鏂板缓鍥惧舰绐楀彛
    ax = gca;    % 鑾峰彇褰撳墠鍧愭爣杞?
    plot_path_result(map, path4, start, goal, path_length4, turn_count4, expanded_nodes4, ...
                     sprintf('鏀硅繘A*绠楁硶 (鏈夋晥璐熻浇: %.2f)', 40), ax, gScore_matrix4);
else
    figure;
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12);
    axis off;
    title('A* (鍔ㄦ€佽浆寮儵缃?');
end
% 瀛愬浘6: A* 鍔ㄦ€佽浆寮儵缃?
if ~isempty(path5)
    f = figure;  % 鏂板缓鍥惧舰绐楀彛
    ax = gca;    % 鑾峰彇褰撳墠鍧愭爣杞?
    plot_path_result(map, path5, start, goal, path_length5, turn_count5, expanded_nodes5, ...
                     sprintf('鏀硅繘A*绠楁硶 (鏈夋晥璐熻浇: %.2f)', 170), ax, gScore_matrix5);
else
    figure;
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12);
    axis off;
    title('A* (鍔ㄦ€佽浆寮儵缃?');
end
