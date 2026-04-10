function varargout = main_script(varargin)
% MAIN_SCRIPT
% Thesis-ready single-AGV path-planning benchmark entry point.
%
% This upgraded entry replaces the old random-map demo with a reproducible
% benchmark suite built on fixed obstacle maps and fixed start-goal cases.
%
% Usage:
%   main_script
%   [results, summaryTable, saveDir] = main_script();

[results, summaryTable, saveDir] = exp_single_agv_path_benchmark(varargin{:});

if nargout >= 1
    varargout{1} = results;
end
if nargout >= 2
    varargout{2} = summaryTable;
end
if nargout >= 3
    varargout{3} = saveDir;
end
end
