function ok = send_schedule_webhook(num_agvs, agv_schedules)
    ok = false;
    webhook_url = 'http://127.0.0.1:5000/api/matlab/webhook';

    schedule_list = {};
    idx = 1;
    for k = 1:num_agvs
        tasks = agv_schedules{k};
        for j = 1:length(tasks)
            schedule_list{idx} = struct('agv_id', k, 'task_id', tasks(j)); %#ok<AGROW>
            idx = idx + 1;
        end
    end

    payload = struct('type', 'schedule_result', 'assignments', {schedule_list});

    try
        options = weboptions('MediaType', 'application/json', 'Timeout', 2.0);
        response = webwrite(webhook_url, payload, options);
        ok = true;

        if isstruct(response) && isfield(response, 'msg')
            response_msg = response.msg;
            if isnumeric(response_msg)
                response_msg = num2str(response_msg);
            elseif isstring(response_msg)
                response_msg = char(response_msg);
            end
            disp(['>> [Webhook] Schedule result delivered: ', response_msg]);
        else
            disp('>> [Webhook] Schedule result delivered.');
        end
    catch ME
        warning('Schedule webhook failed: %s', ME.message);
        log_webhook_failure('schedule_result', payload, ME);
    end
end