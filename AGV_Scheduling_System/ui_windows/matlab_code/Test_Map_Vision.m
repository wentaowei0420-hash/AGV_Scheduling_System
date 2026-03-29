function Test_Map_Vision()
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    clc; clear; close all;
    
    % 鍦板浘灏哄
    W = 70; H = 50;
    
    % 鍒涘缓鍥惧舰绐楀彛
    figure('Name', '鐢佃剳鐪间腑鐨勬爡鏍煎湴鍥?(鍚綉鏍艰竟鐣?', 'Color', 'w', 'Position', [100, 200, 1200, 600]);
    
    %% === 鍦烘櫙 1: 鎵樹妇寮?AGV (Target ID = 5, 灏忛厤浠? ===
    target_id_small = 17;
    % 鐢熸垚鍦板浘
    binaryMap1 = create_binary_grid_map(W, H, target_id_small);
    
    % 缁樺浘
    subplot(1, 2, 1);
    show_map(binaryMap1); % 璋冪敤淇敼鍚庣殑鏄剧ず鍑芥暟
    title(['鍦烘櫙A: 鎵樹妇寮?AGV (鍘荤洰鏍?' num2str(target_id_small) ')']);
    subtitle('娉ㄦ剰鍙充笅瑙掞細鍙夎溅鍩哄湴宸茶灏侀攣 (榛戣壊)');
    
    % 鐢ㄧ孩妗嗗湀鍑洪噸鐐归獙璇佸尯鍩?(鍙夎溅鍩哄湴 x=39~49, y=2)
    hold on;
    rectangle('Position', [39, 2, 10, 3], 'EdgeColor', 'r', 'LineWidth', 1, 'LineStyle', '--');
    text(39, 7, '鍙夎溅鍩哄湴 (宸插皝閿?', 'Color', 'r', 'FontSize', 10, 'FontWeight', 'bold');
    
    % 鍦堝嚭鐩爣 (搴旇鍙互鐪嬪埌鐩爣5鍙锋槸鐧界殑)
    rectangle('Position', [19, 18, 2, 2], 'EdgeColor', 'g', 'LineWidth', 1);
    text(19, 22, '鐩爣5寮€鏀?, 'Color', 'g', 'FontSize', 10, 'FontWeight', 'bold');

    %% === 鍦烘櫙 2: 鍙夎溅寮?AGV (Target ID = 14, 澶т欢) ===
    target_id_heavy = 14;
    % 鐢熸垚鍦板浘
    binaryMap2 = create_binary_grid_map(W, H, target_id_heavy);
    
    % 缁樺浘
    subplot(1, 2, 2);
    show_map(binaryMap2); % 璋冪敤淇敼鍚庣殑鏄剧ず鍑芥暟
    title(['鍦烘櫙B: 鍙夎溅寮?AGV (鍘荤洰鏍?' num2str(target_id_heavy) ')']);
    subtitle('娉ㄦ剰宸︿笅瑙掞細鎵樹妇鍩哄湴宸茶灏侀攣 (榛戣壊)');
    
    % 鐢ㄧ孩妗嗗湀鍑洪噸鐐归獙璇佸尯鍩?(鎵樹妇鍩哄湴 x=2~14, y=2)
    hold on;
    rectangle('Position', [2, 2, 14, 3], 'EdgeColor', 'r', 'LineWidth', 1, 'LineStyle', '--');
    text(2, 7, '鎵樹妇鍩哄湴 (宸插皝閿?', 'Color', 'r', 'FontSize', 10, 'FontWeight', 'bold');
    
    % 鍦堝嚭鐩爣
    rectangle('Position', [4, 41, 3, 3], 'EdgeColor', 'g', 'LineWidth', 1);
    text(4, 39, '鐩爣14寮€鏀?, 'Color', 'g', 'FontSize', 10, 'FontWeight', 'bold');
    
end

% === 銆愭牳蹇冧慨鏀广€戣緟鍔╃粯鍥惧嚱鏁?(澧炲姞浜嗙綉鏍肩嚎缁樺埗) ===
function show_map(gridMap)
    % 1. 鏄剧ず鍦板浘鏈韩
    imagesc(1 - gridMap); % 1-gridMap 鏄负浜嗚闅滅鐗╁彉榛?0)锛岃矾鍙樼櫧(1)
    colormap(gray); 
    axis xy;    % 鍧愭爣鍘熺偣鍦ㄥ乏涓嬭
    axis equal; % x杞磞杞存瘮渚嬩竴鑷?
    
    % 鑾峰彇鍦板浘灏哄
    [rows, cols] = size(gridMap);
    
    % 璁剧疆鍧愭爣杞磋寖鍥?(鐣欏嚭涓€鐐硅竟璺?
    xlim([0.5, cols + 0.5]); 
    ylim([0.5, rows + 0.5]);
    xlabel('X 鍧愭爣'); ylabel('Y 鍧愭爣');
    set(gca, 'TickDir', 'out');
    
    hold on; % 淇濇寔鍥惧儚锛屽噯澶囩敾绾?
    
    % === 鏂板浠ｇ爜锛氱粯鍒剁綉鏍艰竟鐣?===
    % imagesc 鐨勫儚绱犱腑蹇冨湪鏁存暟鐐?(1,1), (2,2)...
    % 鍍忕礌鐨勮竟缂樺湪 (0.5, 1.5, 2.5...)
    
    % A. 鐢荤珫绾?(Vertical Lines)
    % 浠?0.5 寮€濮嬶紝姝ラ暱涓?1锛岀敾鍒版渶鍙宠竟
    for x = 0.5 : 1 : cols + 0.5
        line([x, x], [0.5, rows + 0.5], 'Color', [0.6 0.6 0.6], 'LineWidth', 1);
    end
    
    % B. 鐢绘í绾?(Horizontal Lines)
    % 浠?0.5 寮€濮嬶紝姝ラ暱涓?1锛岀敾鍒版渶涓婅竟
    for y = 0.5 : 1 : rows + 0.5
        line([0.5, cols + 0.5], [y, y], 'Color', [0.6 0.6 0.6], 'LineWidth', 1);
    end
end



