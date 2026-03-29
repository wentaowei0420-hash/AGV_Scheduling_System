% =================================================================
% 妯″潡锛氱數閲忕洃鎺х郴缁熷垵濮嬪寲 (UI浼樺寲鐗?
% =================================================================
function [f_batt, b_handle, t_handles] = init_battery_monitor(num_agvs)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % 1. 鍒涘缓鏇存暣娲佺殑绐楀彛 (鍘婚櫎榛樿鑿滃崟鏍忓拰宸ュ叿鏍忥紝璋冩暣鑳屾櫙鑹?
    f_batt = figure('Name', 'AGV Fleet Energy Monitor', 'NumberTitle', 'off', ...
                    'Position', [1060, 250, 450, 350], ... %绋嶅井璋冨ぇ涓€鐐?
                    'Color', [0.95 0.95 0.95], ... % 娴呯伆鑳屾櫙锛屾洿鏈夎川鎰?
                    'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off');
    
    % 2. 鍒涘缓鍧愭爣杞达紝鐣欏嚭杈硅窛
    ax_batt = axes(f_batt, 'Position', [0.15 0.15 0.78 0.75], 'Color', 'w', ...
                   'Box', 'on', 'LineWidth', 1, 'GridColor', [0.8 0.8 0.8]);
    
    % 3. 鍒濆鍖栨煴鐘跺浘 (瀹藉害绋嶅井鍙樼獎涓€鐐癸紝鏇寸簿鑷?
    b_handle = bar(ax_batt, 1:num_agvs, ones(1,num_agvs)*100, 0.6); 
    
    % 4. 璁剧疆鏍峰紡缇庡寲
    ylim(ax_batt, [0 110]); % Y杞寸暀鍑虹┖闂存樉绀洪《閮ㄧ殑鏁板瓧
    set(ax_batt, 'XTick', 1:num_agvs, 'YGrid', 'on', 'XGrid', 'off', ...
        'FontSize', 10, 'FontWeight', 'bold');
    
    title(ax_batt, '瀹炴椂鐢甸噺鐘舵€佺洃鎺?, 'FontSize', 12, 'FontWeight', 'bold');
    xlabel(ax_batt, 'AGV 缂栧彿', 'FontSize', 11);
    ylabel(ax_batt, '鐢垫睜姘村钩 (%)', 'FontSize', 11);
    
    b_handle.FaceColor = 'flat'; % 鍏佽鐙珛鐫€鑹?
    % 鍒濆棰滆壊璁句负鍋ュ悍鐨勭豢鑹?
    b_handle.CData = repmat([0.1 0.7 0.3], num_agvs, 1);
    
    % 5. 銆愭柊澧炪€戞坊鍔犱綆鐢甸噺璀︽垝绾?(渚嬪 20% 澶?
    hold(ax_batt, 'on');
    yline(ax_batt, 20, '--r', '浣庣數閲忛槇鍊?(20%)', 'LineWidth', 1, ...
        'LabelHorizontalAlignment', 'right', 'FontSize', 9, 'Color', [0.8 0.2 0.2]);
    
    % 6. 銆愭柊澧炪€戝垵濮嬪寲鏌遍《鐨勭櫨鍒嗘瘮鏂囧瓧鏍囩
    t_handles = gobjects(1, num_agvs);
    for i = 1:num_agvs
        % 鍒濆鏄剧ず 100.0%锛屼綅缃湪鏌卞瓙涓婃柟涓€鐐?
        t_handles(i) = text(ax_batt, i, 103, '100.0%', ...
            'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
            'FontSize', 9, 'FontWeight', 'bold', 'Color', [0.2 0.2 0.2]);
    end
    apply_agv_plot_theme(f_batt, style);
end


