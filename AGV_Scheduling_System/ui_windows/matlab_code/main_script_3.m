style = agv_plot_theme();
init_agv_plot_defaults(style);
% 鍦板浘灏哄
map_size = 40;
mapSize = [map_size, map_size];          
% 闅忔満闅滅鐗╂鐜?
p_obstacle = 0.3;             % 30% 鐨勬牸瀛愪负闅滅
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
[path, gScore, turn_count, expanded_nodes, path_length, gScore_matrix]      = astar_planner(map, start, goal,0 );
[path1, gScore1, turn_count1, expanded_nodes1, path_length1, gScore_matrix1]  = astar_planner(map, start, goal, 0.8);
[path2, gScore2, turn_count2, expanded_nodes2, path_length2, gScore_matrix2]  = astar_planner(map, start, goal, 1);
[path3, gScore3, turn_count3, expanded_nodes3, path_length3, gScore_matrix3]  = astar_planner(map, start, goal, 5);
% [path4, gScore4, turn_count4, expanded_nodes4, path_length4, gScore_matrix4]  = astar_planner_turn3(map, start, goal, 170);
% [path5, gScore5, turn_count5, expanded_nodes5, path_length5, gScore_matrix5]  = astar_planner_turn3(map, start, goal, 40);
% 鍒涘缓澶у浘
figure('Name', '璺緞瑙勫垝绠楁硶瀵规瘮 (鐑姏鍥剧増)', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 900]);

% 瀛愬浘1: A* 浼犵粺
subplot(2,2,1);
if ~isempty(path)
    plot_path_result(map, path, start, goal, path_length, turn_count, expanded_nodes, 'A*绠楁硶(w=0)', gca, gScore_matrix);
else
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (浼犵粺绠楁硶)');
end
subplot(2,2,2);
if ~isempty(path1)
    plot_path_result(map, path1, start, goal, path_length1, turn_count1, expanded_nodes1, 'A*绠楁硶(w=0.8)', gca, gScore_matrix1);
else
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (浼犵粺绠楁硶)');
end
subplot(2,2,3);
if ~isempty(path2)
    plot_path_result(map, path2, start, goal, path_length2, turn_count2, expanded_nodes2, 'A*绠楁硶(w=1)', gca, gScore_matrix2);
else
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (浼犵粺绠楁硶)');
end
subplot(2,2,4);
if ~isempty(path3)
    plot_path_result(map, path3, start, goal, path_length3, turn_count3, expanded_nodes3, 'A*绠楁硶(w=2)', gca, gScore_matrix3);
else
    text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (浼犵粺绠楁硶)');
end
% % 瀛愬浘2: A* 杞集鎯╃綒 1
% subplot(2,3,2);
% if ~isempty(path1)
%     plot_path_result(map, path1, start, goal, path_length1, turn_count1, expanded_nodes1, ...
%                      sprintf('A* (杞集鎯╃綒: %.2f)', turnPenalty1), gca, gScore_matrix1);
% else
%     text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (杞集鎯╃綒 1)');
% end
% 
% % 瀛愬浘3: Dijkstra
% subplot(2,3,3);
% if ~isempty(path2)
%     plot_path_result(map, path2, start, goal, path_length2, turn_count2, expanded_nodes2, 'Dijkstra', gca, gScore_matrix2);
% else
%     text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('Dijkstra');
% end
% 
% % 瀛愬浘4: A* 闅滅鐜?
% subplot(2,3,4);
% if ~isempty(path3)
%     plot_path_result(map, path3, start, goal, path_length3, turn_count3, expanded_nodes3, ...
%                      sprintf('A* (杞集鎯╃綒: %.2f)', turnPenalty2), gca, gScore_matrix3);
% else
%     text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (杞集鎯╃綒 2)');
% end
% % 瀛愬浘5: A* 闅滅鐜?鍔ㄦ€佽浆寮儵缃?
% subplot(2,3,5);
% if ~isempty(path4)
%     plot_path_result(map, path4, start, goal, path_length4, turn_count4, expanded_nodes4, ...
%                      sprintf('A* (鍙夎溅寮忚礋杞? %.2f)', 170), gca, gScore_matrix4);
% else
%     text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (闅滅鐜?鍔ㄦ€佽浆寮儵缃?');
% end
% % 瀛愬浘6: A* 鍔ㄦ€佽浆寮儵缃?
% subplot(2,3,6);
% if ~isempty(path5)
%     plot_path_result(map, path5, start, goal, path_length5, turn_count5, expanded_nodes5, ...
%                      sprintf('A* (鎵樹妇寮忚礋杞? %.2f)', 40), gca, gScore_matrix5);
% else
%     text(0.5,0.5,'鏃犳硶鍒拌揪鐩爣','HorizontalAlignment','center','FontSize',12); axis off; title('A* (鍔ㄦ€佽浆寮儵缃?');
% end

