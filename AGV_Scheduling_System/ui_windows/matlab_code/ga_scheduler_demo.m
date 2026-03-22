function ga_scheduler_demo()
    % 1. 初始化环境
    mapW = 70; mapH = 50;
    binaryMap = create_binary_grid_map(mapW, mapH, 0); % 获取完整障碍图
    
    % 2. 模拟 MES 下发的任务列表
    % 格式：{任务ID, 目标工位ID}
    taskList = {
        1, 1;   % 任务1: 去1号工位
        2, 5;   % 任务2: 去5号工位
        3, 8;   % 任务3: 去8号工位
        4, 13;  % 任务4: 去13号架子
        5, 16   % 任务5: 去16号梁
    };
    
    AGV_num = 2; % 设定有 2 台 AGV
    
    % 3. 遗传算法参数
    popSize = 50;       % 种群大小
    maxGen = 100;       % 迭代次数
    
    % 初始化种群 (随机生成调度方案)
    population = init_population(popSize, length(taskList), AGV_num);
    
    % 4. 遗传算法主循环
    for gen = 1:maxGen
        % 计算适应度 (调用 A* 计算距离)
        fitness = calculate_fitness(population, taskList, binaryMap, AGV_num);
        
        % 选择、交叉、变异 (标准 GA 流程)
        new_pop = selection(population, fitness);
        new_pop = crossover(new_pop);
        new_pop = mutation(new_pop);
        
        population = new_pop;
        
        % 记录最优解
        [bestFit, bestIdx] = min(fitness);
        disp(['第 ' num2str(gen) ' 代，最优时间成本: ' num2str(bestFit)]);
    end
    
    % 5. 解析最优方案并仿真
    best_chromosome = population(bestIdx, :);
    visualize_schedule(best_chromosome, taskList, binaryMap);
end

% --- 适应度函数 (核心) ---
function costs = calculate_fitness(pop, tasks, map, agv_count)
    % 这里需要解析染色体，分配给 AGV
    % 然后循环调用 astar_planner_turn 计算总距离
    % Cost = max(所有AGV的行驶距离)
    % ... (此处需要结合之前的 A* 代码)
end