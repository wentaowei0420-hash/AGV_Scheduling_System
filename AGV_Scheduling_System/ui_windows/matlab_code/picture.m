% 定义数据
C1 = [4 14 10 9 1 11 5 2 10 3 7 4 7 11];
P1 = [8 14 3 9 1 6 5 12 10 2 7 4 13 11];
P2 = [4 12 10 5 9 11 6 2 13 3 14 1 7 8];
C2 = [8 12 3 5 9 6 6 12 13 2 14 1 13 8];

% 将所有数据组合成一个矩阵
data = [C1; P1; P2; C2];

% 创建热图或表格（这里使用图像方式显示）
figure;
imagesc(data); % 用颜色深浅表示数字大小，作为底层参考
colormap(gca, 'parula'); % 设置颜色
colorbar; % 显示颜色条

% 在每个单元格上叠加显示数字
[r, c] = size(data);
for i = 1:r
    for j = 1:c
        text(j, i, num2str(data(i, j)), 'HorizontalAlignment', 'center', 'FontWeight', 'bold', 'Color', 'white');
    end
end

% 添加标签
yticks(1:4);
yticklabels({'C₁', 'P₁', 'P₂', 'C₂'});
xlabel('基因位点');
title('图 3.5 任务基因串交叉过程 (示意图框架)');

% 注意：这种方式只能生成表格底图，
% 那些红色的交叉箭头和花括号仍然需要在 MATLAB 的绘图编辑器中手动添加，
% 或者在 PowerPoint 中打开生成的图片继续编辑。