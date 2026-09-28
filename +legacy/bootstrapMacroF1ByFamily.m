function ci = bootstrapMacroF1ByFamily(P,reps,alpha,seed)
%BOOTSTRAPMACROF1BYFAMILY Cluster bootstrap using family_id as sampling unit.
rng(seed,'twister');
fams=unique(P.family_id);
classes=unique(P.label,'stable');
vals=nan(reps,1);
for b=1:reps
    sampled=fams(randi(numel(fams),numel(fams),1));
    idxAll=[];
    for k=1:numel(sampled)
        idx=find(P.family_id==sampled(k));
        idxAll=[idxAll;idx]; %#ok<AGROW>
    end
    M=legacy.classificationMetrics(P.label(idxAll),P.prediction(idxAll),classes);
    vals(b)=M.macro_f1;
end
point=legacy.classificationMetrics(P.label,P.prediction,classes);
ci=struct('point',point.macro_f1,'lower',prctile(vals,100*alpha/2), ...
    'upper',prctile(vals,100*(1-alpha/2)),'reps',reps,'unit','family_id');
end
