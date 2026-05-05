function varargout = region_distance_oracle(action, varargin)
    % =========================================================================
    % 函数名: region_distance_oracle
    % 作用:   区域距离计算预言机（缓存管理器）。
    %         用于预计算并缓存地图上任意节点到各个任务目标区域（取货、卸货、充电）
    %         的最短路径距离和代价值，极大加速后续 GA (遗传算法) 的个体评估过程。
    %
    % 输入参数:
    %   - action: 字符串，支持的操作指令：
    %             'build'  - 构建缓存（如果已有合法缓存则直接加载）
    %             'query'  - 查询某个起点到目标区域的最佳落点坐标和代价值
    %             'clearcache' - 清除内存和磁盘上的所有相关缓存
    %   - varargin: 针对不同 action 的附加选项参数结构体
    %
    % 输出参数:
    %   - 依据 action 不同而不同（详见内部 case 处理）
    % =========================================================================

    % persistent 变量在 MATLAB 函数多次调用之间保留其值，用于构建内存级的高速缓存，避免重复读盘
    persistent oracle_cache
    % global 变量可以在其他脚本中直接访问，作为备用或跨文件共享的全局缓存
    global region_distance_cache
    
    % --- 1. 输入参数合法性检查 ---
    if nargin < 1 || isempty(action)
        error('region_distance_oracle:MissingAction', ...
            'Action is required. Use "build", "query", or "clearcache".');
    end
    
    switch lower(action)
        case 'build'
            % -----------------------------------------------------
            % 操作模式 1: 构建或加载 Oracle 预言机缓存
            % 返回值: oracle (包含所有预计算场数据的结构体)
            % -----------------------------------------------------
            if nargin >= 2
                options = varargin{1};
            else
                options = struct();
            end
            
            % 规范化构建选项（补充未提供的默认参数，确保后续逻辑安全）
            options = normalize_build_options(options);
            % 构建当前地图和任务设定的“元数据签名”（用于比对缓存是否过期/污染）
            cache_meta = build_cache_meta(options);
            
            oracle = [];
            
            % 步骤 A: 尝试从 Persistent 内存加载（速度最快）
            if ~options.force_rebuild && options.use_persistent_cache && is_valid_cached_oracle(oracle_cache, cache_meta)
                oracle = oracle_cache;
                oracle.cache_source = 'persistent'; % 标记缓存来源，方便调试
            end
            
            % 步骤 B: 尝试从 Global 内存加载（次快）
            if isempty(oracle) && ~options.force_rebuild && options.use_global_cache && is_valid_cached_oracle(region_distance_cache, cache_meta)
                oracle = region_distance_cache;
                oracle.cache_source = 'global';
            end
            
            % 步骤 C: 尝试从磁盘文件 (.mat) 加载（适用于重启 MATLAB 后的首次运行）
            if isempty(oracle) && ~options.force_rebuild && options.use_disk_cache
                [oracle_from_disk, loaded] = try_load_oracle_from_disk(options.cache_file, cache_meta);
                if loaded
                    oracle = oracle_from_disk;
                    oracle.cache_source = 'disk';
                end
            end
            
            % 步骤 D: 如果上述缓存全都没命中（或用户要求强制重建），则开始漫长的预计算过程
            if isempty(oracle)
                % 核心计算函数，执行耗时的全图多源路径搜索
                oracle = build_oracle(options); 
                oracle.cache_meta = cache_meta; % 绑定刚刚生成的元数据签名，用于以后的校验
                oracle.cache_source = 'built';
                
                % 计算完成后，将宝贵的结果存入磁盘，造福下次运行
                if options.use_disk_cache
                    try_save_oracle_to_disk(options.cache_file, oracle);
                end
            end
            
            % 步骤 E: 将本次加载/计算的结果刷新回内存缓存，方便下一次极速读取
            if options.use_persistent_cache
                oracle_cache = oracle;
            end
            if options.use_global_cache
                region_distance_cache = oracle;
            end
            
            % 返回构建好的 oracle 结构体
            varargout{1} = oracle;
            
        case 'query'
            % -----------------------------------------------------
            % 操作模式 2: $O(1)$ 极速查询
            % 用法: [best_rc, best_dist, best_cost, feasible] = region_distance_oracle('query', oracle, curr_pos, target_id, phase, agv_type)
            % -----------------------------------------------------
            % 将传入的查询参数解包传递给内部查询函数
            [best_rc, best_dist, best_cost, feasible] = query_oracle(varargin{:});
            varargout = {best_rc, best_dist, best_cost, feasible};
            
        case 'clearcache'
            % -----------------------------------------------------
            % 操作模式 3: 清除缓存
            % 适用场景: 修改了地图栅格、改变了 AGV 参数或更换了工位坐标后必须调用，否则会读到脏数据
            % -----------------------------------------------------
            if nargin >= 2
                options = varargin{1};
            else
                options = struct();
            end
            options = normalize_build_options(options);
            
            % 1. 清空内存级缓存
            oracle_cache = [];
            clear options; % 释放不必要的内存
            region_distance_cache = [];
            
            % 2. 尝试删除磁盘上的缓存文件
            if options.clear_disk_cache && exist(options.cache_file, 'file') == 2
                delete(options.cache_file);
            end
            % 返回 true 表示清理成功
            varargout{1} = true;
            
        otherwise
            % 容错处理：拦截拼写错误的 action 指令
            error('region_distance_oracle:UnknownAction', ...
                'Unsupported action "%s". Use "build", "query", or "clearcache".', action);
    end
end

% =========================================================================
% 内部子函数区：负责预计算逻辑与底层实现
% =========================================================================

function oracle = build_oracle(options)
    % ---------------------------------------------------------
    % 函数：构建完整的预言机结构体
    % 逻辑：它会遍历用户指定的所有车型、所有任务点，逐一调用底层算法生成“势能场”
    % ---------------------------------------------------------
    options = normalize_build_options(options);
    
    % field_map 是一个哈希表 (containers.Map)，通过字符串 Key 来存储每个特定场景的计算矩阵
    % 例如 Key = '1|5|pickup' 对应的值就是 1号车型去5号任务点取货的全图代价矩阵
    field_map = containers.Map('KeyType', 'char', 'ValueType', 'any');
    
    % 外层循环：遍历不同车型 (通常 1代表托举车, 2代表叉车)
    for agv_type = options.agv_types
        task_target_ids = options.task_target_ids;
        
        % 内层循环：遍历该车型需要去的所有任务点 (工位/仓库 ID)
        for target_id = task_target_ids
            % 为“取货 (pickup)”动作生成场地图并存入 Map
            field_map = build_single_field_into_map(field_map, agv_type, target_id, 'pickup');
            % 为“卸货 (dropoff)”动作生成场地图并存入 Map
            field_map = build_single_field_into_map(field_map, agv_type, target_id, 'dropoff');
        end
        
        % 如果选项开启了充电区计算，则额外为该车型对应的充电站生成场地图
        if options.include_charge_regions
            charge_target_id = get_charge_target_id(agv_type);
            field_map = build_single_field_into_map(field_map, agv_type, charge_target_id, 'charge');
        end
    end
    
    % 开始组装返回的 oracle 整体结构体
    oracle = struct();
    oracle.schema_version = 2; % 内部版本号，用于应对未来数据结构的升级
    oracle.mode = 'region_distance_precompute';
    oracle.created_at = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
    oracle.field_map = field_map; % 挂载核心数据体
    oracle.options = options;
    oracle.notes = [
        "Static region-distance oracle for GA evaluation";
        "Uses reverse multi-source shortest-path search";
        "Same obstacle map and terrain costmap as GA/execution static layer";
        "Turn-state penalty is not explicitly modeled in the field"
    ];
end

function options = normalize_build_options(options)
    % ---------------------------------------------------------
    % 函数：选项参数规范化
    % 作用：补全缺失的参数，赋予合理的默认值，确保后续逻辑不因缺少字段而崩溃
    % ---------------------------------------------------------
    if nargin < 1 || isempty(options)
        options = struct();
    end
    normalized = struct();
    
    % 设置默认需计算的 AGV 类型 [1, 2]
    if isfield(options, 'agv_types') && ~isempty(options.agv_types)
        normalized.agv_types = reshape(options.agv_types, 1, []);
    else
        normalized.agv_types = [1, 2];
    end
    
    % 设置默认需计算的任务目标 ID (默认 1 到 16)
    if isfield(options, 'task_target_ids') && ~isempty(options.task_target_ids)
        normalized.task_target_ids = reshape(options.task_target_ids, 1, []);
    else
        normalized.task_target_ids = 1:16;
    end
    
    % 是否计算充电区，默认为 true
    if isfield(options, 'include_charge_regions')
        normalized.include_charge_regions = logical(options.include_charge_regions);
    else
        normalized.include_charge_regions = true;
    end
    
    % 缓存开关配置 (全部默认开启以提升性能)
    if isfield(options, 'use_persistent_cache')
        normalized.use_persistent_cache = logical(options.use_persistent_cache);
    else
        normalized.use_persistent_cache = true;
    end
    if isfield(options, 'use_global_cache')
        normalized.use_global_cache = logical(options.use_global_cache);
    else
        normalized.use_global_cache = true;
    end
    if isfield(options, 'use_disk_cache')
        normalized.use_disk_cache = logical(options.use_disk_cache);
    else
        normalized.use_disk_cache = true;
    end
    
    % 是否无视缓存强制重新计算
    if isfield(options, 'force_rebuild')
        normalized.force_rebuild = logical(options.force_rebuild);
    else
        normalized.force_rebuild = false;
    end
    
    % 清除缓存时是否连磁盘文件一起删掉
    if isfield(options, 'clear_disk_cache')
        normalized.clear_disk_cache = logical(options.clear_disk_cache);
    else
        normalized.clear_disk_cache = true;
    end
    
    % 磁盘缓存文件的保存路径设置
    if isfield(options, 'cache_file') && ~isempty(options.cache_file)
        normalized.cache_file = options.cache_file;
    else
        normalized.cache_file = default_cache_file();
    end
    
    options = normalized;
end

function cache_meta = build_cache_meta(options)
    % ---------------------------------------------------------
    % 函数：构建缓存元数据（特征签名）
    % 作用：将地图的宽、高、静态代价地图、选项参数打包成一个校验用的结构体。
    % 为什么要这样做？
    % 如果你修改了地图的尺寸 (mapW, mapH)，或者修改了车型的避障半径导致 costmap 变了，
    % 但磁盘上的旧缓存还在。下次运行时，程序对比当前签名和旧缓存的签名，
    % 发现不一致，就会判定缓存“已过期/作废”，从而安全地触发重新计算。
    % ---------------------------------------------------------
    global mapW mapH;
    global costmap_type1 costmap_type2;
    
    % 确保全局代价地图已初始化
    if isempty(costmap_type1) || isempty(costmap_type2)
        init_global_costmaps();
    end
    
    cache_meta = struct();
    cache_meta.oracle_schema_version = 2;
    cache_meta.mapW = mapW;
    cache_meta.mapH = mapH;
    cache_meta.options = struct( ...
        'agv_types', options.agv_types, ...
        'task_target_ids', options.task_target_ids, ...
        'include_charge_regions', options.include_charge_regions);
    % 绑定静态代价地图（这是判断环境是否改变的核心）
    cache_meta.costmap_type1 = costmap_type1;
    cache_meta.costmap_type2 = costmap_type2;
end

function tf = is_valid_cached_oracle(oracle, expected_meta)
    % ---------------------------------------------------------
    % 函数：校验缓存是否合法且匹配当前的元数据签名
    % 返回: true (合法) / false (作废)
    % ---------------------------------------------------------
    tf = false;
    % 基本结构体校验
    if isempty(oracle) || ~isstruct(oracle) || ~isfield(oracle, 'cache_meta')
        return;
    end
    if ~isfield(oracle, 'field_map')
        return;
    end
    % 核心比对：使用 isequaln (忽略 NaN 差异) 对比两者的签名是否完全一致
    tf = isequaln(oracle.cache_meta, expected_meta);
end

function [oracle, loaded] = try_load_oracle_from_disk(cache_file, expected_meta)
    % ---------------------------------------------------------
    % 函数：尝试从磁盘加载 .mat 缓存文件
    % ---------------------------------------------------------
    oracle = [];
    loaded = false;
    % 检查文件是否存在
    if exist(cache_file, 'file') ~= 2
        return;
    end
    
    try
        % 读取文件中的 'oracle' 变量
        payload = load(cache_file, 'oracle');
    catch
        % 文件损坏则放弃读取
        return;
    end
    
    if ~isfield(payload, 'oracle')
        return;
    end
    
    oracle = payload.oracle;
    % 加载上来后，立刻进行签名校验
    loaded = is_valid_cached_oracle(oracle, expected_meta);
    if ~loaded
        oracle = []; % 校验失败则丢弃，迫使系统重建
    end
end

function try_save_oracle_to_disk(cache_file, oracle)
    % ---------------------------------------------------------
    % 函数：将构建好的预言机持久化保存到磁盘
    % ---------------------------------------------------------
    try
        cache_dir = fileparts(cache_file);
        % 如果文件夹不存在则创建
        if ~isempty(cache_dir) && exist(cache_dir, 'dir') ~= 7
            mkdir(cache_dir);
        end
        % '-v7.3' 格式支持大于 2GB 的文件保存
        save(cache_file, 'oracle', '-v7.3');
    catch ME
        % 捕捉并只发出警告，不让存储失败中断主程序的运行
        warning('region_distance_oracle:DiskCacheSaveFailed', ...
            'Failed to save disk cache: %s', ME.message);
    end
end

function cache_file = default_cache_file()
    % ---------------------------------------------------------
    % 函数：获取默认的缓存文件存放绝对路径 (与本脚本同级目录)
    % ---------------------------------------------------------
    cache_file = fullfile(fileparts(mfilename('fullpath')), 'region_distance_oracle_cache.mat');
end

function field_map = build_single_field_into_map(field_map, agv_type, target_id, phase)
    % ---------------------------------------------------------
    % 函数：构建针对某一特定动作的单一场数据，并存入哈希表 Map。
    % 解释：“场(Field)”是一张覆盖全地图的大矩阵，矩阵里每个格子(i,j)的值，
    % 代表了“如果 AGV 站在这个格子出发，走到目标区域的最小代价”。
    % ---------------------------------------------------------
    
    % 1. 生成唯一标识符，例如: '1|12|pickup' (1型车, 去12号工位, 阶段为取货)
    key = build_field_key(agv_type, target_id, phase);
    % 如果之前算过这个 Key，直接跳过节约算力
    if isKey(field_map, key)
        return;
    end
    
    % 2. 获取针对当前车型的静态代价地图 (包含了障碍物膨胀信息)
    [cost_map, map_rows, map_cols] = get_ga_costmap_local(agv_type);
    
    % 3. 生成以目标点为中心的安全规划地图 (临时把目标本身从黑砖变成白地，允许驶入)
    planning_map = create_binary_grid_map(map_cols - 1, map_rows - 1, target_id);
    
    % 4. 提取目标区域(例如某个大件仓库是 3x3 的区域)包含的所有可用格子坐标 (候选点集合)
    candidates = get_region_candidates(target_id, phase, agv_type);
    candidates = normalize_candidates(candidates);
    % 剔除掉那些被判定为绝对死路或障碍物的候选格子
    candidates = filter_valid_candidates(candidates, planning_map); 
    
    % 5. 极端情况防御：如果所有目标格子都被堵死了，生成一个充满无穷大(inf)的空场
    if isempty(candidates)
        field = make_empty_field(agv_type, target_id, phase, planning_map, cost_map, candidates);
        field_map(key) = field;
        return;
    end
    
    % 6. 【最耗时的核心计算】: 调用逆向多源最短路径搜索算法 (类似 Dijkstra 算法扩散)
    % 让目标区域内的所有格子同时作为“原点”，向全地图发散搜索，求出全图每个点到该区域的解。
    [cost_field, step_field, best_r_field, best_c_field] = ...
        run_reverse_multi_source_search(planning_map, cost_map, candidates);
        
    % 7. 将计算产生的多种场矩阵打包存入单个结构体
    field = struct();
    field.agv_type = agv_type;
    field.target_id = target_id;
    field.phase = phase;
    field.planning_map = planning_map;
    field.cost_map = cost_map;
    field.candidates = candidates;         % 最终有效的落点集合
    field.cost_field = cost_field;         % 最核心数据：全图每个点到目标的最小综合代价
    field.step_field = step_field;         % 物理距离场：全图每个点到目标的最小步数
    field.best_r_field = best_r_field;     % 溯源信息：全图每个点最终到达目标的哪个具体的行坐标
    field.best_c_field = best_c_field;     % 溯源信息：全图每个点最终到达目标的哪个具体的列坐标
    
    % 8. 将组装好的结构体存入哈希字典
    field_map(key) = field;
end

function [best_rc, best_dist, best_cost, feasible] = query_oracle(oracle, curr_pos, target_id, phase, agv_type)
    % ---------------------------------------------------------
    % 函数：Oracle 极速查询引擎
    % 作用：供 GA 适应度评估函数反复调用。查表的时间复杂度是 O(1)，无任何递归搜索。
    % ---------------------------------------------------------
    % 根据传入请求组合出哈希键
    key = build_field_key(agv_type, target_id, phase);
    
    % 若缓存未就绪，防御性返回死局状态
    if ~isfield(oracle, 'field_map') || ~isKey(oracle.field_map, key)
        best_rc = [];
        best_dist = inf;
        best_cost = inf;
        feasible = false;
        return;
    end
    
    % 取出对应的预计算场数据
    field = oracle.field_map(key);
    [rows, cols] = size(field.cost_field);
    
    % 坐标防越界保护
    if curr_pos(1) < 1 || curr_pos(1) > rows || curr_pos(2) < 1 || curr_pos(2) > cols
        best_rc = [];
        best_dist = inf;
        best_cost = inf;
        feasible = false;
        return;
    end
    
    % ==========================================
    % 极速查表：直接从 4 个矩阵对应的 (行,列) 抽取预先算好的值
    % ==========================================
    best_cost = field.cost_field(curr_pos(1), curr_pos(2));
    best_dist = field.step_field(curr_pos(1), curr_pos(2));
    best_r = field.best_r_field(curr_pos(1), curr_pos(2));
    best_c = field.best_c_field(curr_pos(1), curr_pos(2));
    
    % 如果读出来的代价是有限值且落点坐标大于0，说明能走通
    feasible = isfinite(best_cost) && best_r > 0 && best_c > 0;
    
    if feasible
        best_rc = [best_r, best_c];
    else
        best_rc = [];
        best_dist = inf;
        best_cost = inf;
    end
end

function [cost_field, step_field, best_r_field, best_c_field] = ...
    run_reverse_multi_source_search(planning_map, cost_map, candidates)
    % ---------------------------------------------------------
    % 核心算法：逆向多源最短路径搜索 (Reverse Multi-Source Shortest Path)
    % 实现原理：广度优先搜索(BFS) / Dijkstra 算法的变体
    % 与传统 A* 从单一起点找终点不同，这里是“把所有的可用终点打包作为一个大源头向全图发散蔓延”。
    % ---------------------------------------------------------
    [rows, cols] = size(planning_map);
    
    % 初始化全图代价和步数为无穷大
    cost_field = inf(rows, cols);
    step_field = inf(rows, cols);
    best_r_field = zeros(rows, cols);
    best_c_field = zeros(rows, cols);
    
    % 手动维护一组 Open 列表模拟队列行为，规避 MATLAB 自带对象过慢的问题
    open_r = zeros(0, 1);
    open_c = zeros(0, 1);
    open_cost = zeros(0, 1);
    open_steps = zeros(0, 1);
    open_src_r = zeros(0, 1); % 记录蔓延是从哪个“源头终点”发出来的
    open_src_c = zeros(0, 1);
    
    candidates = normalize_candidates(candidates);
    if isempty(candidates)
        return;
    end
    
    % 第一阶段：灌注源头。将所有合法的目标点装入 Open 队列，代价全部赋 0。
    for i = 1:size(candidates, 1)
        r = candidates(i, 1);
        c = candidates(i, 2);
        if ~is_valid_grid_index(r, c, rows, cols)
            continue;
        end
        % 源头点自身的代价是0
        cost_field(r, c) = 0;
        step_field(r, c) = 0;
        best_r_field(r, c) = r; % 自己到自己的落点就是自己
        best_c_field(r, c) = c;
        
        open_r(end + 1, 1) = r; %#ok<AGROW>
        open_c(end + 1, 1) = c; %#ok<AGROW>
        open_cost(end + 1, 1) = 0; %#ok<AGROW>
        open_steps(end + 1, 1) = 0; %#ok<AGROW>
        open_src_r(end + 1, 1) = r; %#ok<AGROW>
        open_src_c(end + 1, 1) = c; %#ok<AGROW>
    end
    
    % 定义上、下、左、右四个移动方向向量
    dir_vecs = [-1, 0; 1, 0; 0, -1; 0, 1];
    
    % 第二阶段：不断弹出 Open 列表中代价最小的节点，如水波纹般向四周扩散
    while ~isempty(open_cost)
        % 寻找当前已知扩散节点中，累积代价最小的那个点（贪心原则）
        [~, idx] = min(open_cost);
        curr_r = open_r(idx);
        curr_c = open_c(idx);
        curr_cost = open_cost(idx);
        curr_steps = open_steps(idx);
        curr_src_r = open_src_r(idx);
        curr_src_c = open_src_c(idx);
        
        % 弹出选中的节点
        open_r(idx) = []; open_c(idx) = []; open_cost(idx) = [];
        open_steps(idx) = []; open_src_r(idx) = []; open_src_c(idx) = [];
        
        if ~is_valid_grid_index(curr_r, curr_c, rows, cols)
            continue;
        end
        
        % [剪枝优化 1]：如果发现之前已经被其它更快的波纹抢先更新过，说明这条路不是最优，抛弃它
        if curr_cost > cost_field(curr_r, curr_c) + 1e-9
            continue;
        end
        % [剪枝优化 2]：代价一样，但步数更多，抛弃
        if abs(curr_cost - cost_field(curr_r, curr_c)) <= 1e-9 && curr_steps > step_field(curr_r, curr_c)
            continue;
        end
        
        % 尝试向相邻的 4 个方向探索
        for d = 1:4
            nr = curr_r + dir_vecs(d, 1);
            nc = curr_c + dir_vecs(d, 2);
            
            % 1. 防越界与黑砖障碍物碰撞检测
            if nr < 1 || nr > rows || nc < 1 || nc > cols
                continue;
            end
            if planning_map(nr, nc) == 1
                continue;
            end
            
            % 2. 查取代价地图（该格子自身的静态通行难度，受障碍物膨胀影响）
            move_cost = cost_map(nr, nc);
            if ~isfinite(move_cost)
                continue; % 如果是膨胀后的绝对禁区（如贴墙太近）则禁止踏入
            end
            
            % 计算假设走到新邻居格子的累积代价和步数
            tentative_cost = curr_cost + move_cost;
            tentative_steps = curr_steps + 1;
            
            should_update = false;
            
            % ==============================================
            % 核心决策：新路线是否足够优秀值得刷新矩阵记录？
            % ==============================================
            % A. 绝对代价值更小（最强优胜法则）
            if tentative_cost < cost_field(nr, nc) - 1e-9
                should_update = true;
                
            % B. 代价持平，但走的步数更少（更直接的路线）
            elseif abs(tentative_cost - cost_field(nr, nc)) <= 1e-9 && tentative_steps < step_field(nr, nc)
                should_update = true;
                
            % C. 代价持平和步数均持平（遇到了两股波纹交汇）
            %    为确保路径的唯一性和稳定，强制按“字典序较小”的源点坐标获胜（平局断路器）
            elseif abs(tentative_cost - cost_field(nr, nc)) <= 1e-9 && ...
                   tentative_steps == step_field(nr, nc) && ...
                   lexicographically_smaller(curr_src_r, curr_src_c, best_r_field(nr, nc), best_c_field(nr, nc))
                should_update = true;
            end
            
            % 如果判定值得更新，则覆写四个矩阵的值，并将此新边界节点押入队列，供下一轮继续向外发散
            if should_update
                cost_field(nr, nc) = tentative_cost;
                step_field(nr, nc) = tentative_steps;
                % “记录基因”：说明这个格子最终指向的目标落点是哪一个 (溯源作用)
                best_r_field(nr, nc) = curr_src_r;
                best_c_field(nr, nc) = curr_src_c;
                
                open_r(end + 1, 1) = nr; %#ok<AGROW>
                open_c(end + 1, 1) = nc; %#ok<AGROW>
                open_cost(end + 1, 1) = tentative_cost; %#ok<AGROW>
                open_steps(end + 1, 1) = tentative_steps; %#ok<AGROW>
                open_src_r(end + 1, 1) = curr_src_r; %#ok<AGROW>
                open_src_c(end + 1, 1) = curr_src_c; %#ok<AGROW>
            end
        end
    end
end

% -------------------------------------------------------------------------
% 以下全为数据清洗、校验和坐标提取的基础辅助函数，供核心模块调用
% -------------------------------------------------------------------------

function tf = lexicographically_smaller(r1, c1, r2, c2)
    % 字典序比较：判断点 (r1,c1) 是否在空间顺序上先于 (r2,c2)，优先比较行，其次比较列。
    if r2 == 0 && c2 == 0
        tf = true;
        return;
    end
    tf = (r1 < r2) || (r1 == r2 && c1 < c2);
end

function field = make_empty_field(agv_type, target_id, phase, planning_map, cost_map, candidates)
    % 当目标点无路可走时，生成一张充满无限大 (inf) 的占位死场
    [rows, cols] = size(planning_map);
    field = struct();
    field.agv_type = agv_type;
    field.target_id = target_id;
    field.phase = phase;
    field.planning_map = planning_map;
    field.cost_map = cost_map;
    field.candidates = candidates;
    field.cost_field = inf(rows, cols);
    field.step_field = inf(rows, cols);
    field.best_r_field = zeros(rows, cols);
    field.best_c_field = zeros(rows, cols);
end

function key = build_field_key(agv_type, target_id, phase)
    % 拼接哈希字典的专属唯一字符串键名 (如 '1|15|pickup')
    key = sprintf('%d|%d|%s', agv_type, target_id, lower(phase));
end

function candidates = filter_valid_candidates(candidates, planning_map)
    % 剔除掉那些压在障碍物 (墙壁或机床) 上的目标格子
    candidates = normalize_candidates(candidates);
    if isempty(candidates)
        return;
    end
    [rows, cols] = size(planning_map);
    keep_mask = false(size(candidates, 1), 1);
    for i = 1:size(candidates, 1)
        r = candidates(i, 1);
        c = candidates(i, 2);
        if r >= 1 && r <= rows && c >= 1 && c <= cols && planning_map(r, c) == 0
            keep_mask(i) = true;
        end
    end
    candidates = candidates(keep_mask, :);
end

function candidates = normalize_candidates(candidates)
    % 保证输入的坐标数组格式整齐：去除无效的 NaN 和 Inf，化零为整，并剔除重复坐标
    if isempty(candidates)
        candidates = zeros(0, 2);
        return;
    end
    if isvector(candidates) && numel(candidates) == 2
        candidates = reshape(candidates, 1, 2);
    end
    if size(candidates, 2) ~= 2
        error('region_distance_oracle:InvalidCandidates', ...
            'Candidates must be an N-by-2 matrix of [row, col] coordinates.');
    end
    candidates = double(candidates);
    finite_mask = all(isfinite(candidates), 2);
    candidates = candidates(finite_mask, :);
    if isempty(candidates)
        candidates = zeros(0, 2);
        return;
    end
    candidates = round(candidates);
    candidates = unique(candidates, 'rows', 'stable');
end

function tf = is_valid_grid_index(r, c, rows, cols)
    % 坐标安全越界检测：是否是非 NaN、是否超出矩阵最大界限、是否是整数
    tf = isfinite(r) && isfinite(c) && ...
         r >= 1 && r <= rows && c >= 1 && c <= cols && ...
         abs(r - round(r)) <= 1e-9 && abs(c - round(c)) <= 1e-9;
end

function [cost_map, map_rows, map_cols] = get_ga_costmap_local(agv_type)
    % 提取外部环境中，该车型专用的携带安全膨胀的静态代价地图矩阵
    global costmap_type1 costmap_type2;
    if isempty(costmap_type1) || isempty(costmap_type2)
        init_global_costmaps();
    end
    if agv_type == 1
        cost_map = costmap_type1;
    else
        cost_map = costmap_type2;
    end
    [map_rows, map_cols] = size(cost_map);
end

function charge_target_id = get_charge_target_id(agv_type)
    % 根据车型提取各自对应的充电站逻辑 ID 号
    if agv_type == 1
        charge_target_id = 17;
    else
        charge_target_id = 18;
    end
end

function candidates = get_region_candidates(target_id, phase, agv_type)
    % 解析特定任务场景下，目标点在物理地图上覆盖的所有格子坐标
    phase = lower(phase);
    switch phase
        case 'pickup'
            [pickup_anchor, ~, pickup_size, ~] = get_task_coordinates(target_id);
            candidates = expand_anchor_area(pickup_anchor, pickup_size);
        case 'dropoff'
            [~, dropoff_anchor, ~, dropoff_size] = get_task_coordinates(target_id);
            candidates = expand_anchor_area(dropoff_anchor, dropoff_size);
        case 'charge'
            if agv_type == 1
                candidates = xy2rc([2, 2; 2, 3; 3, 2; 3, 3]);
            else
                candidates = xy2rc([39, 2]);
            end
        otherwise
            error('region_distance_oracle:UnknownPhase', ...
                'Unsupported phase "%s". Use pickup, dropoff, or charge.', phase);
    end
end

function candidates = expand_anchor_area(anchor, area_size)
    % 面积展开函数：给定目标区的左上角坐标和宽高(例如 3x3)，展开成那 9 个具体格子的矩阵坐标表
    rows = anchor(1):(anchor(1) + area_size(1) - 1);
    cols = anchor(2):(anchor(2) + area_size(2) - 1);
    [grid_cols, grid_rows] = meshgrid(cols, rows);
    candidates = [grid_rows(:), grid_cols(:)];
end