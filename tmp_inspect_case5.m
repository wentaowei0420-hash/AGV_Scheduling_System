addpath('D:/pycharm_pro/AGV_Scheduling_System/AGV_Scheduling_System/ui_windows/matlab_code');
load('D:/pycharm_pro/AGV_Scheduling_System/AGV_Scheduling_System/ui_windows/matlab_code/smallmap_fixed_20x20.mat','grid_map');
AGV1.pos = [14,4]; AGV1.path = [14,5;14,6;14,7;14,8]; AGV1.path_idx = 3; AGV1.target_node=[14,8]; AGV1.payload_weight=0; AGV1.type=1; AGV1.step_dur=2; AGV1.next_event_t=16;
AGV2.pos = [14,4]; AGV2.target_node=[14,10]; AGV2.payload_weight=0; AGV2.type=1; AGV2.step_dur=1;
dynamic_map = grid_map;
winner_nodes = [14 7; 14 8];
for i = 1:size(winner_nodes,1)
    node = winner_nodes(i,:);
    if isequal(node, AGV2.pos) || isequal(node, AGV2.target_node)
        continue;
    end
    dynamic_map(node(1), node(2)) = 1;
end
[path,cost] = astar_planner_turn3(dynamic_map, AGV2.pos, AGV2.target_node, AGV2.payload_weight, [], AGV2.type);
disp('PATH'); disp(path);
disp('COST'); disp(cost);
