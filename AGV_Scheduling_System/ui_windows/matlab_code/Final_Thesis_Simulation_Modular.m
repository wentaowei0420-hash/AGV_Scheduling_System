function Final_Thesis_Simulation_Modular()
    % =================================================================
    % 毕业设计：基于遗传算法的多AGV配件输送系统调度与仿真 (最终整合版 v3.1)
    % =================================================================
    
    clc;                        % 清空命令行窗口的内容
    close all;                  % 关闭所有打开的图形窗口
    
    % =================================================================
    disp('=================================================================');
    disp('     启动智能车间多 AGV 混合调度与实时仿真系统 v1.00');
    disp('=================================================================');
    
    %% 1. 定义仿真场景与参数
    disp('>> [1/4] 正在初始化环境与物理参数...');   
    
    global mapW mapH binaryMap   
    mapW = 70;                   
    mapH = 50;                   
    
    binaryMap = create_binary_grid_map(mapW, mapH, 0);
    fprintf('   - 栅格地图构建完成: [%d x %d] 区域\n', mapW, mapH);
    
    % --- AGV 配置加载 ---
    load_agv_config;    
    
    num_type1 = sum(agv_types == 1);
    num_type2 = sum(agv_types == 2);
    fprintf('   - AGV 车队注册完成: 共 %d 台 (托举式: %d 台, 叉车式: %d 台)\n', num_agvs, num_type1, num_type2);
    
    % --- 车库物理坐标定义 ---
    garage_coords_type1 = [6, 2; 7, 2; 10, 2; 11, 2; 6, 3; 7, 3; 10, 3; 11, 3];
    garage_coords_type2 = [47, 2; 48, 2; 49, 2; 47, 3; 48, 3; 49, 3; 47, 4; 48, 4; 49, 4];
    
    depots_xy = zeros(num_agvs, 2);
    for i = 1:num_agvs
        t = agv_params(i).type;
        pos_id = agv_params(i).initial_position;
        if pos_id <= 0, pos_id = 1; end
        
        if t == 1
            if pos_id > 8, pos_id = 1; end
            depots_xy(i, :) = garage_coords_type1(pos_id, :);
        else
            if pos_id > 9, pos_id = 1; end
            depots_xy(i, :) = garage_coords_type2(pos_id, :);
        end
    end
    
    % 物理坐标转矩阵索引 (XY -> RC)
    depots = xy2rc(depots_xy);  
   
    % --- 任务流水加载 ---
    disp('>> [2/4] 正在连接 MES 订单系统获取任务流水...');
    [task_list, ~] = MES_Order_System();
    if isempty(task_list)               
        error('❌ [致命错误] 任务列表为空。'); 
    end
    fprintf('   - 成功获取待执行订单: %d 项\n', size(task_list, 1));
    
    % --- 算法参数配置 ---
    weights.w_dist = 1.0;     
    weights.w_energy = 10.0;  
    weights.w_penalty = 20.0; 
    ga_params.pop_size = 50;          
    ga_params.max_gen = 100; % 根据需求调整迭代次数             
    
    %% 2. 调用多目标算法调度器 (NSGA-II + CPO)
    disp('>> [3/4] 启动 HGA 混合自适应多目标优化引擎...');
    disp('   - 正在执行时空轨迹推演与能耗评估，请稍候...');
    
    tic; 

    [sched_exp, batch_exp, metrics_exp, hist_exp, pareto_improved] = ...
        ga_schedule_optimizer_update(task_list, num_agvs, depots, agv_params, ga_params, agv_types);
    opt_time = toc; 
    
    %% 3. 打印精细化调度报告
    fprintf('\n================ 📋 AGV 任务分批调度报告 =================\n');
    for i = 1:num_agvs
        if agv_types(i) == 2 
            fprintf('AGV %02d (车型: 叉车式): 采用单件串行模式 | 任务链: %s\n', i, mat2str(sched_exp{i}));
            fprintf('--------------------------------------------------\n');
            continue;
        end
        
        % 托举车明细打印
        if isempty(batch_exp{i}) || batch_exp{i}.num_batches == 0
            fprintf('AGV %02d (车型: 托举式): [空闲] 无分配任务\n', i);
        else
            info = batch_exp{i}; 
            fprintf('AGV %02d (车型: 托举式): 总计出车 %d 趟\n', i, info.num_batches);
            for b = 1:info.num_batches
                taskListStr = strjoin(arrayfun(@num2str, info.task_batches{b}, 'UniformOutput', false), ', ');
                fprintf('  └─ [第 %d 趟]: 清单 [%s] | 载重: %.1f kg\n', ...
                        b, taskListStr, info.batch_weights(b));
            end
        end
        fprintf('--------------------------------------------------\n');
    end
    
    % --- 宏观多目标指标汇总 ---
    disp('🏆 多目标优化计算完成！系统评估摘要：');
    fprintf('   - 运算耗时: %.2f 秒\n', opt_time);
    fprintf('   - [托举车队] 总距离: %.1f m | 最大时间: %.1f s | 总能耗: %.2f\n', ...
            metrics_exp.lift.dist, metrics_exp.lift.time, metrics_exp.lift.energy);
    fprintf('   - [叉车车队] 总距离: %.1f m | 最大时间: %.1f s | 总能耗: %.2f\n', ...
            metrics_exp.fork.dist, metrics_exp.fork.time, metrics_exp.fork.energy);
    disp('-----------------------------------------------------------------');
    
    %% 4. 可视化仿真运行 (Visualization Loop)
    disp('>> [4/4] 正在构建数字孪生环境进行时空仿真...');
    disp('>> 准备就绪！开始执行动态路径规划与冲突消解方案...');
    pause(0.5);    
    
    % 【适配】：传入优化后的 sched_exp 进行实时动态避障仿真
    run_visualization_loop_time_explicit_sm(num_agvs, depots, sched_exp, task_list, agv_params, agv_types);
    
    disp('>> [系统] 仿真任务全部结束。');
end