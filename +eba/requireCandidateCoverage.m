function requireCandidateCoverage(expected,observed,stage)
%REQUIRECANDIDATECOVERAGE Fail closed when a validation stage omits candidates.
expected=sort(string(expected(:)));observed=sort(string(observed(:)));
assert(~isempty(expected) && numel(unique(expected))==numel(expected) && ...
    numel(unique(observed))==numel(observed) && isequal(expected,observed), ...
    'eba:CandidateCoverage','%s did not evaluate the complete expected candidate set.',stage);
end
