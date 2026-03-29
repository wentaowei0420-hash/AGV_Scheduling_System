try
    fprintf('MATLAB version: %s\n', version);
    fprintf('License test: %d\n', license('test','Distrib_Computing_Toolbox'));
    v = ver('parallel');
    if isempty(v)
        fprintf('ver parallel: EMPTY\n');
    else
        fprintf('ver parallel: %s %s\n', v.Name, v.Version);
    end
    try
        fprintf('Default cluster profile: %s\n', parallel.defaultClusterProfile);
    catch ME
        fprintf('Default cluster profile query failed: %s\n', ME.message);
    end
    try
        c = parcluster('local');
        fprintf('Local cluster type: %s\n', c.Type);
        fprintf('Local NumWorkers: %d\n', c.NumWorkers);
        try
            fprintf('JobStorageLocation: %s\n', c.JobStorageLocation);
        catch
        end
    catch ME
        fprintf('parcluster local failed: %s\n', ME.message);
    end

    pool = gcp('nocreate');
    if ~isempty(pool)
        delete(pool);
    end

    try
        fprintf('Trying parpool(''threads'')...\n');
        p = parpool('threads');
        fprintf('threads pool started: %d workers\n', p.NumWorkers);
        delete(p);
    catch ME
        fprintf('threads pool failed: %s\n', ME.message);
    end

    try
        fprintf('Trying parpool()...\n');
        p = parpool();
        fprintf('default pool started: %d workers, cluster=%s\n', p.NumWorkers, p.Cluster.Type);
        delete(p);
    catch ME
        fprintf('default pool failed: %s\n', ME.message);
    end
catch ME
    fprintf(2,'FATAL: %s\n', ME.message);
end
exit
