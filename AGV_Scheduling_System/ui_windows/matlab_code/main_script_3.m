% 地图尺寸
map_size = 40;
mapSize = [map_size, map_size];          
% 随机障碍物概率
p_obstacle = 0.3;             % 30% 的格子为障碍
% 生成随机地图
randMat = rand(mapSize);      % 生成 [0,1) 均匀随机数矩阵
map = randMat < p_obstacle;   % 小于 p 的为障碍 (1)，其余为自由 (0)
% 此时 map 是一个 logical 矩阵，但 A* 函数要求 double 类型，可以转换：
map = double(map);            % 将 logical 转换为 double (0/1)
start = [2,2];
rows = mapSize(1);
cols = mapSize(2);
goal = [rows-1,cols-2];
% 定义转弯惩罚值（可根据需要调整）
turnPenalty1 = 3.012;
turnPenalty2 = 3;
% 确保起点和终点不是障碍
map(start(1), start(2)) = 0;
map(goal(1), goal(2))   = 0;
% 调用三种算法（获取新增的 gScore_matrix）
[path, gScore, turn_count, expanded_nodes, path_length, gScore_matrix]      = astar_planner(map, start, goal,0 );
[path1, gScore1, turn_count1, expanded_nodes1, path_length1, gScore_matrix1]  = astar_planner(map, start, goal, 0.8);
[path2, gScore2, turn_count2, expanded_nodes2, path_length2, gScore_matrix2]  = astar_planner(map, start, goal, 1);
[path3, gScore3, turn_count3, expanded_nodes3, path_length3, gScore_matrix3]  = astar_planner(map, start, goal, 5);
% [path4, gScore4, turn_count4, expanded_nodes4, path_length4, gScore_matrix4]  = astar_planner_turn3(map, start, goal, 170);
% [path5, gScore5, turn_count5, expanded_nodes5, path_length5, gScore_matrix5]  = astar_planner_turn3(map, start, goal, 40);
% 创建大图
figure('Name', '路径规划算法对比 (热力图版)', 'NumberTitle', 'off', 'Position', [100, 100, 1200, 900]);

% 子图1: A* 传统
subplot(2,2,1);
if ~isempty(path)
    plot_path_result(map, path, start, goal, path_length, turn_count, expanded_nodes, 'A*算法(w=0)', gca, gScore_matrix);
else
    text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (传统算法)');
end
subplot(2,2,2);
if ~isempty(path1)
    plot_path_result(map, path1, start, goal, path_length1, turn_count1, expanded_nodes1, 'A*算法(w=0.8)', gca, gScore_matrix1);
else
    text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (传统算法)');
end
subplot(2,2,3);
if ~isempty(path2)
    plot_path_result(map, path2, start, goal, path_length2, turn_count2, expanded_nodes2, 'A*算法(w=1)', gca, gScore_matrix2);
else
    text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (传统算法)');
end
subplot(2,2,4);
if ~isempty(path3)
    plot_path_result(map, path3, start, goal, path_length3, turn_count3, expanded_nodes3, 'A*算法(w=2)', gca, gScore_matrix3);
else
    text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (传统算法)');
end
% % 子图2: A* 转弯惩罚 1
% subplot(2,3,2);
% if ~isempty(path1)
%     plot_path_result(map, path1, start, goal, path_length1, turn_count1, expanded_nodes1, ...
%                      sprintf('A* (转弯惩罚: %.2f)', turnPenalty1), gca, gScore_matrix1);
% else
%     text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (转弯惩罚 1)');
% end
% 
% % 子图3: Dijkstra
% subplot(2,3,3);
% if ~isempty(path2)
%     plot_path_result(map, path2, start, goal, path_length2, turn_count2, expanded_nodes2, 'Dijkstra', gca, gScore_matrix2);
% else
%     text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('Dijkstra');
% end
% 
% % 子图4: A* 障碍率
% subplot(2,3,4);
% if ~isempty(path3)
%     plot_path_result(map, path3, start, goal, path_length3, turn_count3, expanded_nodes3, ...
%                      sprintf('A* (转弯惩罚: %.2f)', turnPenalty2), gca, gScore_matrix3);
% else
%     text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (转弯惩罚 2)');
% end
% % 子图5: A* 障碍率+动态转弯惩罚
% subplot(2,3,5);
% if ~isempty(path4)
%     plot_path_result(map, path4, start, goal, path_length4, turn_count4, expanded_nodes4, ...
%                      sprintf('A* (叉车式负载: %.2f)', 170), gca, gScore_matrix4);
% else
%     text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (障碍率+动态转弯惩罚)');
% end
% % 子图6: A* 动态转弯惩罚
% subplot(2,3,6);
% if ~isempty(path5)
%     plot_path_result(map, path5, start, goal, path_length5, turn_count5, expanded_nodes5, ...
%                      sprintf('A* (托举式负载: %.2f)', 40), gca, gScore_matrix5);
% else
%     text(0.5,0.5,'无法到达目标','HorizontalAlignment','center','FontSize',12); axis off; title('A* (动态转弯惩罚)');
% end

