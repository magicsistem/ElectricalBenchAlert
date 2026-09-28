function mask=pareto(X,directions)
%PARETO Non-dominated finite rows; 1 maximizes, -1 minimizes each objective.
assert(isnumeric(X) && isreal(X) && ismatrix(X) && size(X,2)>0, ...
    'eba:ParetoData','Objectives must be a real numeric matrix with at least one column.');
assert(isnumeric(directions) && isreal(directions) && isvector(directions) && ...
    numel(directions)==size(X,2) && all(ismember(directions(:),[-1 1])), ...
    'eba:ParetoDirections','Each objective needs one direction, either 1 or -1.');
Z=double(X).*double(directions(:)'); mask=all(isfinite(Z),2); candidates=Z(mask,:);
% ponytail: quadratic scan; replace with a skyline algorithm if method count grows.
for i=find(mask)'
    if any(all(candidates>=Z(i,:),2) & any(candidates>Z(i,:),2)),mask(i)=false;end
end
end
