function run_visualization_loop_time_explicit_sm_text(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types)
% Event-driven entry wrapper for thesis simulations.
% Keeps the original public function name used by existing scripts while
% delegating execution to the event-driven explicit state-machine core.

    run_visualization_loop_event_sm(num_agvs, depots, agv_schedules, task_list, agv_params, agv_types);
end
