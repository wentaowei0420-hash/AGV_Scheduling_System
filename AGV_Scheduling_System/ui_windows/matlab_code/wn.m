% =========================================================================
% 动态自适应权重系数可视化分析 (学术纯净版)
% 本脚本提取了改进 A* 算法中的动态权重计算逻辑，并绘制其随距离衰减的曲线
% =========================================================================
clear; clc; close all;

%% 1. 模拟场景参数设置
start_point = [5, 5];       % 假设起点坐标
goal_point  = [45, 45];     % 假设终点坐标

% 计算起点到终点的总距离 (作为归一化基准)
dist_start_to_goal = sqrt((start_point(1) - goal_point(1))^2 + ...
                          (start_point(2) - goal_point(2))^2);

if dist_start_to_goal == 0
    dist_start_to_goal = 1e-6; % 防止除零
end

% 压缩系数
compression_factor = 0.4; 

%% 2. 生成模拟距离数据
dist_current_to_goal = linspace(dist_start_to_goal, 0, 100);

%% 3. 调用核心权重函数进行计算
w_n = calculate_dynamic_weight(dist_current_to_goal, dist_start_to_goal, compression_factor);

%% 4. 绘图可视化 (符合学术期刊/顶级答辩规范)
% 创建白底图形
figure('Name', '自适应动态权重系数衰减曲线', 'Color', 'w', 'Position', [100, 100, 600, 450]);

% 绘制主曲线 (标准学术蓝)
plot(dist_current_to_goal, w_n, '-', 'Color', '#0072BD', 'LineWidth', 2, 'DisplayName', '动态权重 w(n)');
hold on;

% 绘制基准线 (标准 A* 权重)
yline(1.0, '--', 'Color', '#7E2F8E', 'LineWidth', 1.5, 'DisplayName', '标准 A* 权重 (w=1)');

% 绘制关键节点 (采用空心标记，稳重不花哨)
plot(dist_start_to_goal, w_n(1), 's', 'MarkerSize', 7, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', '#D95319', 'LineWidth', 1.5, 'DisplayName', '起点 (偏向贪婪搜索)');
plot(0, w_n(end), 'o', 'MarkerSize', 7, 'MarkerFaceColor', 'w', 'MarkerEdgeColor', '#0072BD', 'LineWidth', 1.5, 'DisplayName', '终点 (回归精确寻优)');

% 图表基础修饰
grid on;
box on; % 加上全封闭边框，符合论文规范
set(gca, 'XDir', 'reverse'); % X轴反向：模拟车辆从远到近靠近目标

% 动态调整 X 轴显示范围 (留出一点边缘空白，不要顶格)
xlim([0, ceil(dist_start_to_goal/10)*10]); 
ylim([0.8, max(w_n) + 0.1]);

% 字体与标签规范化 (中英文字体分离)
xlabel('当前节点距离目标的距离 D (m)', 'FontSize', 11, 'FontName', 'SimSun');
ylabel('启发函数权重系数 w(n)', 'FontSize', 11, 'FontName', 'SimSun');

% 坐标轴刻度字体设置
ax = gca;
ax.FontSize = 11;
ax.FontName = 'Times New Roman'; 
ax.LineWidth = 1.0;

% 图例修饰
lgd = legend('Location', 'northwest');
lgd.FontSize = 10;
lgd.FontName = 'SimSun';
legend('boxoff'); % 去除图例边框，画面更干净

%% =========================================================================
% 核心函数提取：计算动态权重 w(n)
% =========================================================================
function w = calculate_dynamic_weight(dist_curr, dist_total, compress_factor)
    % 1. 计算距离占比 (归一化距离)
    dist_ratio = dist_curr ./ dist_total;
    
    % 2. 计算原始指数因子 (a_raw)
    a_raw = exp(dist_ratio)-1 ;
    
    % 3. 应用压缩系数 (a_compressed)
    a_compressed = a_raw * compress_factor;
    
    % 4. 计算最终的总权重 w(n)
    w = a_compressed+1;
end