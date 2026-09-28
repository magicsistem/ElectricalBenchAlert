function [v,names] = structToFeatureVector(s)
%STRUCTTOFEATUREVECTOR Deterministically flatten scalar numeric struct fields.
fn = sort(fieldnames(s));
v = [];
names = {};
for k = 1:numel(fn)
    value = s.(fn{k});
    if isnumeric(value) && isscalar(value)
        v(end+1) = double(value); %#ok<AGROW>
        names{end+1} = fn{k}; %#ok<AGROW>
    end
end
v = reshape(v,1,[]);
end
