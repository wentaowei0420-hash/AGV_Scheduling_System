clc; clear; close all;

% 年份
year = 2015:2025;
% 销售额/市场规模（亿元）
sales = [12, 19, 28.5, 42.5, 61.75, 76.8, 126, 185, 212, 221, 261];
% 增长率（%）
growth = [67.00, 58.30, 50.00, 49.00, 45.20, 24.40, 64.00, 46.83, 14.59, 4.25, 18.10];

% 绘图
figure('Color','w','Position',[200 150 1000 500]);

% 左轴
yyaxis left
plot(year, sales, '-o', 'LineWidth', 2, 'MarkerSize', 7);
ylabel('市场规模（亿元）', 'FontSize', 12);
ylim([0 300]);

% 右轴
yyaxis right
plot(year, growth, '-s', 'LineWidth', 2, 'MarkerSize', 7);
ylabel('增长率（%）', 'FontSize', 12);
ylim([0 80]);

% 坐标轴设置（已取消标题）
xlabel('年份', 'FontSize', 12);
xticks(year);
grid on;

% 设置图例并增大字体大小 (此处将 FontSize 设置为 14)
legend('市场规模（亿元）', '增长率（%）', 'Location', 'northwest', 'FontSize', 18);

% 数据标注 - 左轴
yyaxis left
for i = 1:length(year)
    text(year(i), sales(i)+6, num2str(sales(i)), ...
        'HorizontalAlignment', 'center', 'FontSize', 10);
end

% 数据标注 - 右轴
yyaxis right
for i = 1:length(year)
    text(year(i), growth(i)+2, [num2str(growth(i)) '%'], ...
        'HorizontalAlignment', 'center', 'FontSize', 10);
end