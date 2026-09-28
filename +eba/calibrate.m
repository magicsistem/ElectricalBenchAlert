function model = calibrate(model,X,y,family_ids)
%CALIBRATE Scalar temperature on explicitly disjoint training calibration families.
assert(numel(y)==numel(family_ids) && ~isempty(y),'eba:CalibrationShape','Calibration families required.');
[~,~,~,scores]=eba.predict(model,X);[found,col]=ismember(double(y(:)),model.classes);
assert(all(found),'eba:CalibrationClass','Calibration contains unknown classes.');
objective=@(logT) nll(scores,col,exp(logT));
logT=fminbnd(objective,-5,4);model.temperature=exp(logT);model.calibrated=true;
model.calibration=struct('temperature',model.temperature,'n_records',numel(y), ...
    'n_families',numel(unique(family_ids)),'family_hash',eba.hash(join(sort(unique(string(family_ids))),"\n")), ...
    'nll',objective(logT),'scope','disjoint training calibration families');
end
function value=nll(scores,col,T)
a=scores/T;a=a-max(a,[],2);logp=a-log(sum(exp(a),2));
value=-mean(logp(sub2ind(size(logp),(1:size(logp,1)).',col)));
end
