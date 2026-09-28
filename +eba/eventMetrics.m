function [report,matched,clusters] = eventMetrics(truth,estimated,normal_exposure,cfg)
%EVENTMETRICS Class-aware interval matching; shared families stay in one uncertainty cluster.
assert(istable(truth) && all(ismember({'sequence_id','family_id','class_id','start_s','end_s'},truth.Properties.VariableNames)), ...
    'eba:EventTruth','Ground truth must contain event identities and complete intervals.');
assert(istable(estimated) && all(ismember({'sequence_id','class_id','estimated_start_s','estimated_end_s','confirmation_time_s'},estimated.Properties.VariableNames)), ...
    'eba:EventEstimate','Estimated intervals must be complete; censored confirmations cannot supply end metrics.');
assert(all(isfinite(truth.start_s) & isfinite(truth.end_s) & truth.start_s>=0 & truth.end_s>truth.start_s), ...
    'eba:EventBoundary','Truth intervals are invalid.');
assert(all(isfinite(estimated.estimated_start_s) & isfinite(estimated.estimated_end_s) & ...
    estimated.estimated_start_s>=0 & estimated.estimated_end_s>estimated.estimated_start_s & ...
    isfinite(estimated.confirmation_time_s) & estimated.confirmation_time_s>=estimated.estimated_start_s), ...
    'eba:EventBoundary','Censored or invalid estimated intervals cannot supply full event metrics.');
assert(isnumeric(truth.class_id) && isnumeric(estimated.class_id) && ...
    all(isfinite(truth.class_id) & truth.class_id==fix(truth.class_id) & truth.class_id>=2 & truth.class_id<=numel(cfg.classes)) && ...
    all(isfinite(estimated.class_id) & estimated.class_id==fix(estimated.class_id) & estimated.class_id>=2 & estimated.class_id<=numel(cfg.classes)), ...
    'eba:EventClass','Event classes must be declared non-normal integer IDs.');
family=string(truth.family_id);truthSequence=string(truth.sequence_id);estimatedSequence=string(estimated.sequence_id);
assert(all(~ismissing(family) & strlength(strtrim(family))>0) && ...
    all(~ismissing(truthSequence) & strlength(strtrim(truthSequence))>0) && ...
    all(~ismissing(estimatedSequence) & strlength(strtrim(estimatedSequence))>0), ...
    'eba:EventIdentity','Family and sequence identities must be nonempty.');
for f=unique(family).'
    assert(numel(unique(truth.class_id(family==f)))==1,'eba:EventIndependence','A repeated family cannot change class.');
end
seq=unique([truthSequence;estimatedSequence],'sorted');linkSequence=truthSequence;linkFamily=family;
if istable(normal_exposure)
    assert(all(ismember({'sequence_id','normal_exposure_s'},normal_exposure.Properties.VariableNames)) && ...
        numel(unique(normal_exposure.sequence_id))==height(normal_exposure),'eba:EventExposure','Invalid exposure table.');
    exposureSequence=string(normal_exposure.sequence_id);
    assert(all(~ismissing(exposureSequence) & strlength(strtrim(exposureSequence))>0),'eba:EventExposure','Empty exposure sequence identity.');
    seq=unique([seq;exposureSequence],'sorted');[ok,where]=ismember(seq,exposureSequence);
    assert(all(ok),'eba:EventExposure','Every sequence needs its normal exposure.');exposure=normal_exposure.normal_exposure_s(where);
    if ismember('family_id',normal_exposure.Properties.VariableNames)
        exposureFamily=string(normal_exposure.family_id);
        assert(all(~ismissing(exposureFamily) & strlength(strtrim(exposureFamily))>0),'eba:EventExposure','Empty exposure family identity.');
        linkSequence=[linkSequence;exposureSequence];linkFamily=[linkFamily;exposureFamily];
    end
else
    exposure=double(normal_exposure(:));
    if isempty(seq) && numel(exposure)==1,seq="empty_sequence";end
    assert(numel(exposure)==numel(seq),'eba:EventExposure','Exposure vector must match sorted sequence identities; a multi-sequence total is insufficient.');
end
assert(~isempty(seq) && all(isfinite(exposure) & exposure>=0),'eba:EventExposure','Normal exposure must be finite and nonnegative.');
threshold=.1;if isfield(cfg,'event_iou_threshold'),threshold=cfg.event_iou_threshold;end
assert(isscalar(threshold) && threshold>0 && threshold<=1,'eba:EventMatch','Invalid IoU matching threshold.');
matched=table('Size',[0 9],'VariableTypes',{'string','string','double','double','double','double','double','double','double'}, ...
    'VariableNames',{'sequence_id','family_id','truth_row','estimated_row','class_id','iou','latency_s','start_error_s','end_error_s'});
clusters=table(seq,zeros(numel(seq),1),zeros(numel(seq),1),zeros(numel(seq),1),exposure, ...
    zeros(numel(seq),1),zeros(numel(seq),1),zeros(numel(seq),1),zeros(numel(seq),1), ...
    'VariableNames',{'sequence_id','true_positives','false_positives','false_negatives','normal_exposure_s', ...
    'iou_sum','latency_sum_s','start_error_sum_s','end_error_sum_s'});
for s=1:numel(seq)
    gt=find(truthSequence==seq(s));ed=find(estimatedSequence==seq(s));pairs=zeros(0,2);iou=zeros(numel(gt),numel(ed));
    if ~isempty(gt) && ~isempty(ed)
        for i=1:numel(gt)
            for j=1:numel(ed)
                % An alarm preceding the physical onset remains a false alarm, even if its eventual interval overlaps.
                if truth.class_id(gt(i))~=estimated.class_id(ed(j)) || estimated.confirmation_time_s(ed(j))<truth.start_s(gt(i)),continue;end
                intersection=max(0,min(truth.end_s(gt(i)),estimated.estimated_end_s(ed(j)))-max(truth.start_s(gt(i)),estimated.estimated_start_s(ed(j))));
                union=max(truth.end_s(gt(i)),estimated.estimated_end_s(ed(j)))-min(truth.start_s(gt(i)),estimated.estimated_start_s(ed(j)));
                iou(i,j)=intersection/union;
            end
        end
        cost=-iou;cost(iou<threshold)=1e6;pairs=matchpairs(cost,0,'min');
    end
    for p=1:size(pairs,1)
        i=gt(pairs(p,1));j=ed(pairs(p,2));latency=estimated.confirmation_time_s(j)-truth.start_s(i);
        matched(end+1,:)={seq(s),family(i),i,j,truth.class_id(i),iou(pairs(p,1),pairs(p,2)), ...
            latency,abs(estimated.estimated_start_s(j)-truth.start_s(i)),abs(estimated.estimated_end_s(j)-truth.end_s(i))}; %#ok<AGROW>
    end
    rows=matched.sequence_id==seq(s);count=sum(rows);clusters.true_positives(s)=count;
    clusters.false_positives(s)=numel(ed)-count;clusters.false_negatives(s)=numel(gt)-count;
    clusters.iou_sum(s)=sum(matched.iou(rows));clusters.latency_sum_s(s)=sum(matched.latency_s(rows));
    clusters.start_error_sum_s(s)=sum(matched.start_error_s(rows));clusters.end_error_sum_s(s)=sum(matched.end_error_s(rows));
end
% Merge sequence dependencies transitively: noisy derivatives share a family, and events in one sequence share a baseline.
groups=(1:numel(seq))';
for f=unique(linkFamily).'
    [ok,index]=ismember(linkSequence(linkFamily==f),seq);assert(all(ok),'eba:EventIdentity','Missing linked sequence.');
    ids=unique(groups(index));for j=2:numel(ids),groups(groups==ids(j))=ids(1);end
end
[~,~,group]=unique(groups);nGroups=max(group);sufficient=zeros(nGroups,8);
for g=1:nGroups,sufficient(g,:)=sum(clusters{group==g,2:9},1);end
values=totals(sum(sufficient,1));names=["precision","recall","f1","missed_event_rate", ...
    "false_alarms_per_minute","mean_iou","mean_latency_s","mean_absolute_start_error_s","mean_absolute_end_error_s"];
report=struct('n_true_events',height(truth),'n_estimated_events',height(estimated),'n_matched_events',height(matched), ...
    'n_sequences',numel(seq),'n_independent_sequences',nGroups,'n_independent_families',numel(unique(linkFamily)), ...
    'n_independent_clusters',nGroups,'normal_exposure_s',sum(exposure),'false_alarms',sum(clusters.false_positives), ...
    'matching','one-to-one maximum total IoU within sequence and exact class; confirmation at or after true onset', ...
    'iou_threshold',threshold,'latency_scope','conditional on matched completed events; misses reported separately');
for q=1:numel(names),report.(names(q))=values(q);end
B=cfg.bootstrap_replicates;if isfield(cfg,'temporal_bootstrap_replicates'),B=cfg.temporal_bootstrap_replicates;end
assert(isscalar(B) && B>=0 && B==fix(B),'eba:EventBootstrap','Invalid bootstrap count.');
if B>0
    r=RandStream('mt19937ar','Seed',mod(double(cfg.master_seed)+7301,2^32));draws=zeros(B,numel(names));
    for b=1:B,chosen=randi(r,nGroups,[nGroups 1]);draws(b,:)=totals(sum(sufficient(chosen,:),1));end
    for q=1:numel(names)
        valid=draws(:,q);valid=valid(isfinite(valid));ci=[NaN NaN];if ~isempty(valid),ci=quantile(valid,[.025 .975]);end
        report.([char(names(q)) '_ci_low'])=ci(1);report.([char(names(q)) '_ci_high'])=ci(2);
        report.([char(names(q)) '_defined_bootstrap_replicates'])=numel(valid);
    end
end
clusters.independent_cluster_id=group;
report.bootstrap_replicates=B;report.bootstrap_scope='connected family/sequence clusters; all paired noise derivatives remain together';
report.uncertainty_limitation='Intervals condition on the fitted model. One independent cluster yields a degenerate interval; undefined zero-match means are excluded and counted.';
end
function v=totals(s)
tp=s(1);fp=s(2);fn=s(3);exposure=s(4);precision=tp/max(tp+fp,1);recall=tp/max(tp+fn,1);
rate=NaN;if exposure>0,rate=60*fp/exposure;elseif fp>0,rate=Inf;end
means=NaN(1,4);if tp>0,means=s(5:8)/tp;end
v=[precision,recall,2*precision*recall/max(precision+recall,eps),fn/max(tp+fn,1),rate,means];
end
