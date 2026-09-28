function ci = bootstrapTemporalByFamily(F,reps,alpha,seed)
%BOOTSTRAPTEMPORALBYFAMILY Cluster bootstrap for mean absolute start error.
valid=isfinite(F.event_start_s) & isfinite(F.detected_start_s);
P=F(valid,:);
if isempty(P)
    ci=struct('point',NaN,'lower',NaN,'upper',NaN,'reps',reps,'unit','family_id'); return;
end
err=abs(P.detected_start_s-P.event_start_s);
fams=unique(P.family_id);
rng(seed,'twister'); vals=nan(reps,1);
for b=1:reps
    sampled=fams(randi(numel(fams),numel(fams),1));
    e=[];
    for k=1:numel(sampled)
        e=[e;err(P.family_id==sampled(k))]; %#ok<AGROW>
    end
    vals(b)=mean(e);
end
ci=struct('point',mean(err),'lower',prctile(vals,100*alpha/2), ...
    'upper',prctile(vals,100*(1-alpha/2)),'reps',reps,'unit','family_id');
end
