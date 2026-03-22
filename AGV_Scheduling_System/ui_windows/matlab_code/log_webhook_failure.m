function log_webhook_failure(event_type, payload, err)
    log_dir = fileparts(mfilename('fullpath'));
    log_path = fullfile(log_dir, 'webhook_failures.log');

    if nargin < 3 || isempty(err)
        err_message = 'unknown error';
    elseif ischar(err)
        err_message = err;
    elseif isstring(err)
        err_message = char(err);
    elseif isstruct(err) && isfield(err, 'message')
        err_message = err.message;
    else
        try
            err_message = err.message;
        catch
            err_message = 'unknown error';
        end
    end

    try
        payload_text = jsonencode(payload);
    catch
        payload_text = evalc('disp(payload)');
        payload_text = strtrim(payload_text);
    end

    fid = fopen(log_path, 'a', 'n', 'UTF-8');
    if fid == -1
        warning('Webhook failure log file cannot be opened: %s', log_path);
        return;
    end

    fprintf(fid, '[%s] type=%s | error=%s | payload=%s\n', ...
        datestr(now, 'yyyy-mm-dd HH:MM:SS'), event_type, err_message, payload_text);
    fclose(fid);
end