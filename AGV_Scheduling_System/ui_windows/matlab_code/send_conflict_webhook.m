function ok = send_conflict_webhook(current_t, id_self, pos_self, id_blocker, pos_blocker, conflict_name)
    ok = false;
    webhook_url = 'http://127.0.0.1:5000/api/matlab/webhook';
    conflict_name_cn = localize_conflict_type(conflict_name);
    payload = struct( ...
        'type', 'conflict_event', ...
        'sim_step', current_t, ...
        'agv1_id', id_self, ...
        'agv1_pos', sprintf('(%d,%d)', pos_self(1), pos_self(2)), ...
        'agv2_id', id_blocker, ...
        'agv2_pos', sprintf('(%d,%d)', pos_blocker(1), pos_blocker(2)), ...
        'conflict_type', conflict_name_cn ...
    );

    try
        % Local Flask may be concurrently serving UI polling requests; keep
        % webhook timeout slightly higher to avoid dropping conflict events.
        options = weboptions('MediaType', 'application/json', 'Timeout', 8.0);
        response = webwrite(webhook_url, payload, options);
        ok = true;

        if isstruct(response) && isfield(response, 'msg')
            response_msg = response.msg;
            if isnumeric(response_msg)
                response_msg = num2str(response_msg);
            elseif isstring(response_msg)
                response_msg = char(response_msg);
            end
            disp(['[Webhook] Conflict event delivered: ', response_msg]);
        else
            fprintf('[Webhook] Conflict event delivered: T=%d, AGV-%d vs AGV-%d\n', current_t, id_self, id_blocker);
        end
    catch ME
        warning('Conflict webhook failed at T=%d for AGV-%d vs AGV-%d: %s', ...
            current_t, id_self, id_blocker, ME.message);
        log_webhook_failure('conflict_event', payload, ME);
    end
end

function conflict_name_cn = localize_conflict_type(conflict_name)
    switch strtrim(char(conflict_name))
        case 'Node contention'
            conflict_name_cn = '节点冲突';
        case 'Occupied node'
            conflict_name_cn = '占位冲突';
        case 'Rear-end'
            conflict_name_cn = '追尾冲突';
        case 'Head-on swap'
            conflict_name_cn = '相向冲突(交换)';
        case 'Head-on meet'
            conflict_name_cn = '相向冲突(相遇)';
        case 'Three-way interlock'
            conflict_name_cn = '环状互锁';
        otherwise
            conflict_name_cn = conflict_name;
    end
end
