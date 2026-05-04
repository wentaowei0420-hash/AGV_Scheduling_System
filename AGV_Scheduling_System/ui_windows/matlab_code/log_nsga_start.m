function log_nsga_start(tag, num_tasks, num_agvs, pop_size, max_gen, log_interval)
    fprintf('      [%s] start | tasks=%d | agvs=%d | pop=%d | gen=%d | logInterval=%d\n', ...
        tag, num_tasks, num_agvs, pop_size, max_gen, log_interval);
end