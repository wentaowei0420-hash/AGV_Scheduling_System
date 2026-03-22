function Final_Thesis_Simulation_Modular_python(external_task_list)
    % =================================================================
    % 毕业设计：基于遗传算法的多AGV配件输送系统调度与仿真 (最终整合版)
    % =================================================================
    
    clc;                        % 清空命令行窗口的内容
    close all;                  % 关闭所有打开的图形窗口
    disp('=================================================================');
    disp('           基于AGV的转向架生产组装线仿真系统 v1.0');
    disp('=================================================================');
    
    %% 1. 定义仿真场景与参数
    disp('>> [1/4] 正在初始化环境与物理参数...');   
    
    global mapW mapH binaryMap   
    mapW = 70;                   
    mapH = 50;                   
    
    binaryMap = create_binary_grid_map(mapW, mapH, 0);
    % 【监控】：打印地图生成结果
    fprintf('   - 栅格地图构建完成: [%d x %d] 区域\n', mapW, mapH);
    
    % --- AGV 动态配置 ---
    % 执行 Python 在后台生成的配置文件
    load_agv_config;
    num_type1 = sum(agv_types == 1);
    num_type2 = sum(agv_types == 2);
    fprintf('   - AGV 车队注册完成: 共 %d 台 (托举式: %d 台, 叉车式: %d 台)\n', num_agvs, num_type1, num_type2);
    
    % =============================================================
    % 【核心适配】：定义真实车库的物理坐标集合
    % 假设托举式车库 (8个) 排布在左下方，叉车车库 (9个) 排布在右下方
    garage_coords_type1 = [
         6, 2; 7, 2; 10, 2; 11, 2; 
         6, 3; 7, 3; 10, 3; 11, 3
    ];
    
    garage_coords_type2 = [
        47, 2; 48, 2; 49, 2;
        47, 3; 48, 3; 49, 3;
        47, 4; 48, 4; 49, 4;
    ];
    
    % 动态提取并生成所有 AGV 的起点矩阵
    depots_xy = zeros(num_agvs, 2);
    disp('   - 正在同步上位机 AGV 物理参数...');
    
    for i = 1:num_agvs
        t = agv_params(i).type;
        pos_id = agv_params(i).initial_position;
        
        % 容错处理：确保读取到的车库 ID 不越界
        if pos_id <= 0, pos_id = 1; end
        
        if t == 1
            if pos_id > 8, pos_id = 1; end
            depots_xy(i, :) = garage_coords_type1(pos_id, :);
        else
            if pos_id > 9, pos_id = 1; end
            depots_xy(i, :) = garage_coords_type2(pos_id, :);
        end
        
        % 打印详细同步结果，方便日志追踪
        fprintf('     [%s] 类型:%d | 车库ID:%d -> 坐标(%d,%d) | 速度:%.1fm/s | 电量:%d%% | 空/负载系数:%.2f/%.2f\n', ...
            agv_params(i).agv_id, t, pos_id, depots_xy(i, 1), depots_xy(i, 2), ...
            agv_params(i).speed, agv_params(i).battery_current, ...
            agv_params(i).e_base, agv_params(i).e_load_factor);
    end
    % =============================================================
    
    % --- 【自动转换模块】 ---
    % 调用转换函数，自动变成矩阵需要的 [Row, Col] 格式
    depots = xy2rc(depots_xy); 
    
    disp('>> 坐标已自动转换:');
    disp(['   车库物理坐标(XY): ', mat2str(depots_xy), ' -> 矩阵索引(RC): ', mat2str(depots)]);
    
    % --- 任务列表加载 ---
    disp('>> [2/4] 正在连接 MES 订单系统获取任务流水...');
    if nargin > 0 && ~isempty(external_task_list)
        task_list = external_task_list;
        disp(['>> 成功接收来自 MySQL 数据库的 ', num2str(size(task_list, 1)), ' 条任务数据！']);
    else
        % 如果没有传参，直接报错停止，强制要求使用数据库
        error('未接收到来自数据库的任务数据，仿真终止。');
    end
    
    if isempty(task_list)               
        error('❌ [致命错误] 传入的任务列表为空，没有需要执行的任务。'); 
    end
    
    % 【监控】：打印提取到的任务数量
    fprintf('   - 成功获取待执行订单: %d 项\n', size(task_list, 1));
    
    % --- GA参数 ---
    ga_params.pop_size = 50;
    ga_params.max_gen = 80;
    
    %% 2. 调用封装好的 GA 调度器
    disp('>> [3/4] 启动 HGA 混合自适应遗传算法进行路径与成本全局优化...');
    disp('   - 正在推演最优解，请稍候...');
    
    tic; % 开始计时
    [sched_exp, batch_exp, metrics_exp, hist_exp, pareto_improved] = ...
        ga_schedule_optimizer_update(task_list, num_agvs, depots, agv_params, ga_params, agv_types);
    opt_time = toc; % 结束计时
    
    agv_schedules = sched_exp;
    batch_details = batch_exp;
    
    fprintf('\n================ AGV 分批调度报告 ================\n');
    for i = 1:length(batch_details)
        % 判断是否为叉车
        if agv_types(i) == 2 
            fprintf('AGV %d (车型: 叉车): 采用单件串行模式，无批次信息，请直接查看 schedules\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        
        % 对于托举车的打印逻辑 (修复了重复判断的BUG)
        if isempty(batch_details{i})
            fprintf('AGV %d (车型: 托举式): [空闲] 无分配任务\n', i);
            fprintf('--------------------------------------------------\n');
            continue;
        end
        
        info = batch_details{i}; % 提取该车的结构体
        fprintf('AGV %d (车型: 托举式): 总计出车 %d 趟\n', i, info.num_batches);
        
        % 遍历每一批次
        for b = 1:info.num_batches
            % 将任务 ID 数组转换为逗号分隔的字符串
            taskListStr = strjoin(arrayfun(@num2str, info.task_batches{b}, 'UniformOutput', false), ', ');
            fprintf('  [第 %d 趟]: 任务清单 [%s], 总重: %.1f kg\n', ...
                    b, taskListStr, info.batch_weights(b));
        end
        fprintf('--------------------------------------------------\n');
    end
    % =================================================================
    % 【架构升级】：通过 HTTP API 将 GA 调度结果实时主动推送给 Python 后端
    disp('>> 正在通过 API 将调度报文推送给上位机...');
    if ~send_schedule_webhook(num_agvs, agv_schedules)
        disp('>> [Webhook] Schedule result send failed and was written to local log.');
    end
    % ================================================================

    
    % 【监控】：打印算法耗时与结果
    disp('-----------------------------------------------------------------');
    fprintf('✅ 优化计算完成！耗时: %.2f 秒\n', opt_time);
    disp('📋 最终最佳任务调度方案矩阵:');
    for k = 1:num_agvs
        fprintf('   AGV-%d (Type %d): %s\n', k, agv_types(k), mat2str(agv_schedules{k}));
    end    
    
    %% 3. 可视化仿真 (Visualization Loop)
    disp('>> [4/4] 正在构建二维数字转向架组装线车间环境...');
    disp('>> 准备就绪！开始进行实时动态仿真动画...');
    pause(2);    
    run_visualization_loop_time(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types);
end