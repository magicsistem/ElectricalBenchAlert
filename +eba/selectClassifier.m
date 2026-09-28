function [model,results] = selectClassifier(X,P,cfg,kind,calibration_ids)
%SELECTCLASSIFIER Identical hyperparameter search, family-held-out validation and training-only calibration.
assert(all(P.split~="test"),'eba:TestFirewall','Tuning denies final test.');
fitmask=P.split=="train" & ~ismember(P.family_id,calibration_ids);valmask=P.split=="validation";
assert(any(fitmask)&&any(valmask),'eba:SelectionSplit','Training and validation rows are required.');
grid={};
if upper(string(kind))=="SVM"
    for C=cfg.svm_grid.box_constraint(:).'
        grid{end+1}=struct('kernel','linear','box_constraint',C,'kernel_scale',1); %#ok<AGROW>
        for scale=cfg.svm_grid.kernel_scale(:).',grid{end+1}=struct('kernel','gaussian','box_constraint',C,'kernel_scale',scale);end %#ok<AGROW>
    end
else
    for trees=cfg.rf_grid.trees(:).'
        for leaf=cfg.rf_grid.min_leaf(:).',grid{end+1}=struct('trees',trees,'min_leaf',leaf);end %#ok<AGROW>
    end
end
K=max(P.class_id);values=zeros(numel(grid),3);best=-Inf;bestModel=[];
for h=1:numel(grid)
    candidate=eba.fit(X(fitmask,:),P.class_id(fitmask),cfg,kind,grid{h});
    t=tic;pred=eba.predict(candidate,X(valmask,:));latency=toc(t)/sum(valmask);
    met=eba.metrics(P.class_id(valmask),pred,K);values(h,:)=[met.macro_f1,candidate.training_time_s,latency];
    fprintf('%s hyperparameter %d/%d validation MacroF1=%.4f\n',kind,h,numel(grid),met.macro_f1);
    % Frozen deterministic rule: strict validation F1 improvement; ties keep earlier, simpler grid entry.
    if met.macro_f1>best+1e-12,best=met.macro_f1;bestModel=candidate;end
end
model=bestModel;calmask=P.split=="train" & ismember(P.family_id,calibration_ids);
assert(any(calmask) && isempty(intersect(unique(P.family_id(fitmask)),unique(P.family_id(calmask)))),'eba:CalibrationLeakage','Calibration families are not disjoint.');
model=eba.calibrate(model,X(calmask,:),P.class_id(calmask),P.family_id(calmask));
results=table(string(cellfun(@jsonencode,grid,'UniformOutput',false)).',values(:,1),values(:,2),values(:,3), ...
    'VariableNames',{'hyperparameters_json','validation_macro_f1','training_time_s','classification_time_s'});
end
