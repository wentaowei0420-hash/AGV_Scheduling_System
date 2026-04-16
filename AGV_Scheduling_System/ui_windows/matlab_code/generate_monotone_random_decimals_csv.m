function values = generate_monotone_random_decimals_csv(range_vals, count)
%GENERATE_MONOTONE_RANDOM_DECIMALS_CSV Generate decreasing decimals for CSV.
%   values = generate_monotone_random_decimals_csv([min_val, max_val], count)
%   returns strictly decreasing 9-decimal values and prints them one per line,
%   which is convenient for pasting into a single CSV column.
%
%   Example:
%       values = generate_monotone_random_decimals_csv([0.12, 0.35], 8);

    values = generate_monotone_random_decimals(range_vals, count);

    fprintf('CSV column output:\n');
    for i = 1:numel(values)
        fprintf('%.9f\n', values(i));
    end
end
