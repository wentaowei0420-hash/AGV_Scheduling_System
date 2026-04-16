function values = generate_monotone_random_decimals(range_vals, count)
%GENERATE_MONOTONE_RANDOM_DECIMALS Generate strictly decreasing random decimals.
%   values = generate_monotone_random_decimals([min_val, max_val], count)
%   returns a row vector of length count with values in [min_val, max_val],
%   rounded to 9 decimal places and sorted in strictly decreasing order.
%
%   Example:
%       values = generate_monotone_random_decimals([0.12, 0.35], 8);

    if nargin < 2
        error('Usage: values = generate_monotone_random_decimals([min_val, max_val], count)');
    end

    if numel(range_vals) ~= 2
        error('range_vals must be a 2-element vector: [min_val, max_val].');
    end

    min_val = range_vals(1);
    max_val = range_vals(2);

    if ~isscalar(count) || count <= 0 || floor(count) ~= count
        error('count must be a positive integer.');
    end

    if min_val >= max_val
        error('range_vals must satisfy min_val < max_val.');
    end

    scale = 1e9;
    min_int = ceil(min_val * scale);
    max_int = floor(max_val * scale);

    if (max_int - min_int + 1) < count
        error('The range is too small to generate %d unique 9-decimal values.', count);
    end

    int_values = randperm(max_int - min_int + 1, count) + min_int - 1;
    int_values = sort(int_values, 'descend');
    values = int_values / scale;

    fprintf('Generated %d strictly decreasing values in [%.9f, %.9f]:\n', count, min_val, max_val);
    disp(values);
end
