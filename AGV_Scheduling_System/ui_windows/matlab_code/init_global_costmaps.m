function init_global_costmaps()
        % 声明全局变量，供全局调用
        global mapW mapH;
        global costmap_type1 costmap_type2;
        
        disp('>> [系统] 正在离线预计算异构 AGV 静态代价地图 (Costmaps)...');
        
        % 1. 获取纯静态障碍物地图 (传入 0 表示不需要动态目标)
        % 这里借助你原本的 create_binary_grid_map 生成没有任何车辆的空地图
        staticMap = create_binary_grid_map(mapW, mapH, 0);
        obs_map = (staticMap == 1);
        [map_rows, map_cols] = size(staticMap);
        
        % 2. 执行距离变换 (全图每个格子离最近障碍物的距离)
        dist_map = bwdist(obs_map); 
        
        % 3. 初始化代价矩阵
        costmap_type1 = ones(map_rows, map_cols); % 托举车代价图
        costmap_type2 = ones(map_rows, map_cols); % 叉车代价图
        
        % 4. 一次性生成非对称势场
        for r = 1:map_rows
            for c = 1:map_cols
                if dist_map(r,c) > 0
                    % 【叉车 (Type 2)】：庞大笨重，害怕障碍物，距离越近惩罚呈指数级爆炸
                    repulsive_penalty = 15.0 / (dist_map(r,c)^2); 
                    costmap_type2(r,c) = 1.0 + repulsive_penalty;
                    
                    % 【托举车 (Type 1)】：灵活小巧，鼓励走边缘，路越宽惩罚稍微增大
                    edge_preference_penalty = 0.5 * dist_map(r,c); 
                    costmap_type1(r,c) = 1.0 + edge_preference_penalty;
                end
            end
        end
        disp('>> [系统] 静态代价地图预计算完毕，已载入内存！');
    end
