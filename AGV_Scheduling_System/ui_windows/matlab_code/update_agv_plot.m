function update_agv_plot(agv)
    style = agv_plot_theme();
    init_agv_plot_defaults(style);
    % 鏇存柊AGV鍦║I涓婄殑浣嶇疆鍜岀姸鎬侀鑹?(甯﹀姩鎬佽浇閲嶄笌澶氫换鍔￠槦鍒楁樉绀?
    
    set(agv.handle, 'Position', [agv.vis_pos(2)-0.9, agv.vis_pos(1)-0.9, 0.8, 0.8]);
    
    % ========================================================
    % 銆愪慨鏀瑰尯銆戯細鍔ㄦ€佹瀯寤烘偓娴枃鏈紝灞曠ず鎵归噺瑁呰浇鐨勫疄鏃堕噸閲忓拰鍓╀綑浠舵暟
    if isfield(agv, 'payload_weight') && agv.payload_weight > 0
        queue_len = length(agv.drop_queue); % 鏌ョ湅鍗歌揣闃熷垪閲岃繕鏈夊嚑浠舵病鍗?
        if queue_len > 0
            % 濡傛灉鏄墭涓捐溅鎵归噺瑁呰浇锛屾樉绀哄綋鍓嶆€婚噸鍜岀畻涓婃鍦ㄨ繍鐨勮繖涓€浠剁殑鍓╀綑鎬讳欢鏁?
            txt = sprintf('AGV%d W:%d(浣?d)\n%s', agv.id, agv.payload_weight, queue_len + 1, agv.status); 
        else
            % 濡傛灉鏄崟浠讹紙鍙夎溅锛夛紝鍙樉绀哄綋鍓嶉噸閲?
            txt = sprintf('AGV%d W:%d\n%s', agv.id, agv.payload_weight, agv.status);
        end
    else
        % 绌鸿浇鐘舵€?
        txt = sprintf('AGV%d 绌鸿浇\n%s', agv.id, agv.status);
    end
    % ========================================================
    
    set(agv.text, 'Position', [agv.vis_pos(2)-0.5, agv.vis_pos(1)-0.5], 'String', txt);
    
    % 鏍规嵁鐘舵€佹洿鏀硅溅韬鑹?
    col=[0.2 0.8 0.2]; 
    if agv.load > 0, col=[1 0.6 0]; end
    if contains(agv.status, 'Charge') || contains(agv.status, 'Low'), col=[1 0.2 0.2]; end 
    
    set(agv.handle, 'FaceColor', col);
end
