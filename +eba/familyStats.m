function [summary,pairs,robustness,details] = familyStats(P,predictions,method_names,cfg)
%FAMILYSTATS Paired, class-stratified family inference conditional on fitted models.
% P: record_id, family_id, class_id, SNR_db, realization_id. Predictions: N-by-M.
% All methods must supply every identical row; all families have equal condition cells.
required={'record_id','family_id','class_id','SNR_db','realization_id'};
assert(istable(P) && height(P)>0 && all(ismember(required,P.Properties.VariableNames)), ...
    'eba:StatisticsTable','Prediction metadata must contain the declared columns.');
assert(isstruct(cfg) && isfield(cfg,'classes') && ~isempty(cfg.classes), ...
    'eba:StatisticsConfig','The frozen class list is required.');
assert((isstring(cfg.classes) || iscellstr(cfg.classes)) && isvector(cfg.classes), ...
    'eba:StatisticsConfig','Class names must be a declared string vector.');
class_names=string(cfg.classes(:));
assert(all(~ismissing(class_names) & strlength(strtrim(class_names))>0) && ...
    numel(unique(class_names))==numel(class_names),'eba:StatisticsConfig','Class names must be nonempty and unique.');
K=numel(class_names); N=height(P); names=string(method_names(:)); M=numel(names);
assert(M>0 && all(~ismissing(names) & strlength(strtrim(names))>0) && numel(unique(names))==M, ...
    'eba:StatisticsMethods','Method names must be nonempty and unique.');
assert(isnumeric(predictions) && isreal(predictions) && isequal(size(predictions),[N M]), ...
    'eba:StatisticsShape','Every method must predict the same metadata rows.');
assert(isnumeric(P.class_id) && isreal(P.class_id) && numel(P.class_id)==N, ...
    'eba:StatisticsLabels','Class IDs must be a numeric vector.');
y=double(P.class_id(:)); predictions=double(predictions);
labels=[y;predictions(:)];
assert(all(isfinite(labels) & labels>=1 & labels<=K & mod(labels,1)==0), ...
    'eba:StatisticsLabels','Missing predictions and undeclared class IDs are forbidden.');
record=string(P.record_id(:)); family=string(P.family_id(:));
assert(numel(record)==N && numel(family)==N && ...
    all(~ismissing(record) & strlength(strtrim(record))>0) && numel(unique(record))==N, ...
    'eba:StatisticsRecords','Record IDs must be nonempty and unique.');
assert(all(~ismissing(family) & strlength(strtrim(family))>0), ...
    'eba:StatisticsFamilies','Family IDs must be nonempty.');
assert(isnumeric(P.SNR_db) && isreal(P.SNR_db) && numel(P.SNR_db)==N && ...
    isnumeric(P.realization_id) && isreal(P.realization_id) && numel(P.realization_id)==N, ...
    'eba:StatisticsConditions','SNR and realization must be numeric vectors.');
snr=double(P.SNR_db(:)); realization=double(P.realization_id(:));
assert(all(~isnan(snr) & snr~=-Inf) && all(isfinite(realization) & realization>=0 & mod(realization,1)==0) && ...
    all(realization(snr==Inf)==0) && all(realization(isfinite(snr))>=1), ...
    'eba:StatisticsConditions','Clean is (Inf,0); noisy realizations are positive integers.');
[families,~,f]=unique(family,'sorted'); F=numel(families);
family_class=accumarray(f,y,[F 1],@min);
assert(all(family_class==accumarray(f,y,[F 1],@max)), ...
    'eba:StatisticsFamilyClass','A family cannot belong to multiple classes.');
[conditions,~,condition_id]=unique([snr realization],'rows','sorted');
cells=full(sparse(f,condition_id,1,F,size(conditions,1)));
assert(all(cells(:)==1),'eba:StatisticsDesign', ...
    'Every family must have exactly one record in every observed SNR/realization cell.');
records_per_family=sum(cells,2); levels=unique(snr,'sorted'); L=numel(levels);
B=replicateCount(cfg,'bootstrap_replicates'); R=replicateCount(cfg,'permutation_replicates');
assert(isfield(cfg,'master_seed') && isnumeric(cfg.master_seed) && isreal(cfg.master_seed) && isscalar(cfg.master_seed) && ...
    isfinite(cfg.master_seed) && cfg.master_seed>=0 && cfg.master_seed<2^32 && mod(cfg.master_seed,1)==0, ...
    'eba:StatisticsSeed','master_seed must be a uint32-compatible integer.');
bootstrap_seed=mod(double(cfg.master_seed)+3201,2^32);
permutation_seed=mod(double(cfg.master_seed)+3202,2^32);

% Sparse family confusion blocks retain every derivative without copying records.
blocks=cell(1,M*(L+1)); point=cell(M,1); point_snr=cell(M,L);
for m=1:M
    blocks{m}=sparse(f,y+(predictions(:,m)-1)*K,1,F,K*K);
    point{m}=eba.metrics(y,predictions(:,m),K);
    for l=1:L
        take=snr==levels(l);
        blocks{M+l*M-M+m}=sparse(f(take),y(take)+(predictions(take,m)-1)*K,1,F,K*K);
        point_snr{m,l}=eba.metrics(y(take),predictions(take,m),K);
    end
end
A=horzcat(blocks{:});
metric_names=["accuracy","balanced_accuracy","macro_precision","macro_recall", ...
    "macro_f1","weighted_f1","macro_specificity"];
V=zeros(B,M,numel(metric_names)); recall_draws=zeros(B,K,M); snr_draws=zeros(B,M,L);
stream=RandStream('mt19937ar','Seed',bootstrap_seed);
by_class=arrayfun(@(k) find(family_class==k),1:K,'UniformOutput',false);
for first=1:128:B
    take=first:min(first+127,B); b=numel(take); weights=sparse(b,F);
    for k=1:K
        ids=by_class{k}; count=numel(ids); if count==0,continue;end
        selected=ids(randi(stream,count,[b count]));
        weights=weights+sparse(repmat((1:b)',count,1),selected(:),1,b,F);
    end
    [values,recalls]=confusionValues(weights*A,K,M*(L+1));
    V(take,:,:)=values(:,1:M,:); recall_draws(take,:,:)=recalls(:,:,1:M);
    snr_draws(take,:,:)=reshape(values(:,M+1:end,5),b,M,L);
end
summary=table(names,repmat(F,M,1),repmat(N,M,1), ...
    'VariableNames',{'method','n_families','n_records'});
for q=1:numel(metric_names)
    field=char(metric_names(q)); summary.(field)=cellfun(@(x) x.(field),point);
    ci=interval(V(:,:,q)); summary.([field '_ci_low'])=ci(1,:)'; summary.([field '_ci_high'])=ci(2,:)';
end
class_ci=interval(reshape(recall_draws,B,K*M));
per_class=table(repelem(names,K,1),repmat((1:K)',M,1),repmat(class_names,M,1), ...
    zeros(K*M,1),zeros(K*M,1),zeros(K*M,1),zeros(K*M,1), ...
    'VariableNames',{'method','class_id','class_name','recall','recall_ci_low','recall_ci_high','n_records'});
for m=1:M
    idx=(m-1)*K+(1:K); per_class.recall(idx)=point{m}.recall;
    per_class.n_records(idx)=point{m}.support;
end
per_class.recall_ci_low=class_ci(1,:)'; per_class.recall_ci_high=class_ci(2,:)';

% Primary family: ten comparisons among the first five DSP/SVM methods.
planned=zeros(0,2); if M>=2,planned=nchoosek(1:min(M,5),2);end
if isfield(cfg,'planned_comparisons')
    planned=double(cfg.planned_comparisons);
    assert(isnumeric(cfg.planned_comparisons) && isreal(planned) && size(planned,2)==2 && ...
        all(isfinite(planned) & planned==fix(planned) & planned>=1 & planned<=M,'all') && ...
        all(planned(:,1)~=planned(:,2)) && size(unique(sort(planned,2),'rows'),1)==size(planned,1), ...
        'eba:StatisticsComparisons','Planned comparisons require distinct unique declared method pairs.');
end
J=size(planned,1);
comparison_family="dsp_svm_primary_first_five";
if M<5,comparison_family="development_first_methods";end
if isfield(cfg,'comparison_family'),comparison_family=string(cfg.comparison_family);end
assert(isscalar(comparison_family) && ~ismissing(comparison_family) && strlength(strtrim(comparison_family))>0, ...
    'eba:StatisticsComparisons','comparison_family must be one nonempty identifier.');
pairs=table(names(planned(:,1)),names(planned(:,2)),repmat(comparison_family,J,1), ...
    repmat(F,J,1),repmat(N,J,1),zeros(J,1),zeros(J,1),zeros(J,1),zeros(J,1), ...
    zeros(J,1),zeros(J,1),zeros(J,1),zeros(J,1), ...
    'VariableNames',{'method_a','method_b','comparison_family','n_families','n_records', ...
    'delta_macro_f1','delta_pp','delta_pp_ci_low','delta_pp_ci_high', ...
    'p_raw','p_holm','p_mc_se','exceedances'});
effect_draws=zeros(B,J); exceed_draws=false(R,J); pair_seeds=zeros(J,1);
for j=1:J
    a=planned(j,1); c=planned(j,2); delta=point{a}.macro_f1-point{c}.macro_f1;
    effect_draws(:,j)=V(:,a,5)-V(:,c,5); ci=100*interval(effect_draws(:,j));
    pairs.delta_macro_f1(j)=delta; pairs.delta_pp(j)=100*delta;
    pairs.delta_pp_ci_low(j)=ci(1); pairs.delta_pp_ci_high(j)=ci(2);
    pair_seeds(j)=mod(permutation_seed+j-1,2^32);
    if all(predictions(:,a)==predictions(:,c))
        exceed_draws(:,j)=true;
    else
        stream=RandStream('mt19937ar','Seed',pair_seeds(j));
        difference=blocks{c}-blocks{a}; ca=full(sum(blocks{a},1)); cc=full(sum(blocks{c},1));
        threshold=max(0,abs(delta)-16*eps(max(abs(delta),1)));
        for first=1:128:R
            take=first:min(first+127,R); b=numel(take);
            swaps=double(rand(stream,b,F)<0.5)*difference;
            va=confusionValues(ca+swaps,K,1); vc=confusionValues(cc-swaps,K,1);
            exceed_draws(take,j)=abs(va(:,1,5)-vc(:,1,5))>=threshold;
        end
    end
    count=sum(exceed_draws(:,j)); pairs.exceedances(j)=count;
    pairs.p_raw(j)=(1+count)/(R+1);
    frequency=count/R; pairs.p_mc_se(j)=sqrt(R*frequency*(1-frequency))/(R+1);
end
pairs.p_holm=holm(pairs.p_raw);

robustness=table(repelem(names,L,1),repmat(levels,M,1),repmat(F,M*L,1),zeros(M*L,1), ...
    zeros(M*L,1),zeros(M*L,1),zeros(M*L,1), ...
    'VariableNames',{'method','SNR_db','n_families','n_records','macro_f1','macro_f1_ci_low','macro_f1_ci_high'});
for m=1:M
    for l=1:L
        idx=(m-1)*L+l; ci=interval(snr_draws(:,m,l));
        robustness.n_records(idx)=sum(snr==levels(l)); robustness.macro_f1(idx)=point_snr{m,l}.macro_f1;
        robustness.macro_f1_ci_low(idx)=ci(1); robustness.macro_f1_ci_high(idx)=ci(2);
    end
end
snr_points=zeros(M,L);
for m=1:M,for l=1:L,snr_points(m,l)=point_snr{m,l}.macro_f1;end,end
[robust_values,robust_draws,auc_status]=robustnessValues(snr_points,snr_draws,levels);
robust_names=["clean_macro_f1","worst_noisy_macro_f1","clean_minus_worst", ...
    "mean_noisy_macro_f1","normalized_snr_auc"];
robust_summary=table(names,'VariableNames',{'method'});
for q=1:numel(robust_names)
    field=char(robust_names(q)); ci=interval(robust_draws(:,:,q));
    robust_summary.(field)=robust_values(:,q);
    robust_summary.([field '_ci_low'])=ci(1,:)'; robust_summary.([field '_ci_high'])=ci(2,:)';
end
robust_summary.auc_status=repmat(auc_status,M,1);

% Check actual Monte Carlo endpoint drift; a replicate budget is not convergence.
counts=unique([min(B,[2500 5000 10000]) B]);
check_values=[reshape(V,B,[]),reshape(recall_draws,B,[]),reshape(snr_draws,B,[]), ...
    reshape(robust_draws,B,[]),100*effect_draws];
check_names=strings(1,size(check_values,2)); position=0;
for q=1:numel(metric_names),for m=1:M,position=position+1;check_names(position)=names(m)+":"+metric_names(q);end,end
for m=1:M,for k=1:K,position=position+1;check_names(position)=names(m)+":recall_class_"+k;end,end
for l=1:L,for m=1:M,position=position+1;check_names(position)=names(m)+":macro_f1_snr_"+levels(l);end,end
for q=1:numel(robust_names),for m=1:M,position=position+1;check_names(position)=names(m)+":"+robust_names(q);end,end
for j=1:J,position=position+1;check_names(position)=pairs.method_a(j)+"-"+pairs.method_b(j)+":delta_pp";end
endpoint_checks=endpointChecks(check_values,check_names,counts);
permutation_checks=permutationChecks(exceed_draws,pairs);
details=struct('class_names',class_names,'declared_class_count',K,'n_families',F,'n_records',N, ...
    'family_counts',table(families,family_class,records_per_family), ...
    'families_per_class',accumarray(family_class,1,[K 1]),'condition_cells',conditions, ...
    'singleton_class_strata',find(accumarray(family_class,1,[K 1])==1), ...
    'singleton_limitation',"one family in a class cannot estimate within-class family variability", ...
    'per_class_recall',per_class,'point_metrics',{point},'robustness_summary',robust_summary, ...
    'bootstrap_replicates',B,'permutation_replicates',R,'master_seed',cfg.master_seed, ...
    'bootstrap_seed',bootstrap_seed,'permutation_pair_seeds',pair_seeds, ...
    'rng_algorithm',"mt19937ar",'bootstrap_unit',"family_id", ...
    'bootstrap_strata',"class_id",'paired_draws_across_methods_and_snr',true, ...
    'uncertainty_scope',"conditional on supplied fitted models; no retraining variability", ...
    'interval_method',"pointwise 95% percentile; ordinary differences are not simultaneous intervals", ...
    'zero_denominator_policy',"zero; all configured classes retained", ...
    'permutation_null',"within each independent family the complete method prediction vectors are exchangeable", ...
    'permutation_tail',"two-sided absolute pooled Macro-F1 difference", ...
    'comparison_family',comparison_family,'planned_comparisons',planned, ...
    'auc_axis',"uniform integral over dB [-5,30], piecewise-linear trapezoids, clean Inf excluded", ...
    'mc_endpoint_checks',endpoint_checks,'mc_permutation_checks',permutation_checks, ...
    'mc_full_checkpoints_available',B>=10000 && R>=10000, ...
    'mc_precision_claim',"inspect computed endpoint changes and p MC SE; count alone is not a stability claim", ...
    'evidence_files',"README.md", ...
    'reference_ids',[16 17 18 19]);
end

function count=replicateCount(cfg,field)
assert(isfield(cfg,field) && isnumeric(cfg.(field)) && isreal(cfg.(field)) && isscalar(cfg.(field)) && ...
    isfinite(cfg.(field)) && cfg.(field)>=2 && mod(cfg.(field),1)==0, ...
    'eba:StatisticsReplicates','Replicate counts must be integers of at least two.');
count=double(cfg.(field));
end

function [values,recall]=confusionValues(rows,K,blocks)
% Each row holds column-major K-by-K confusion blocks, true class in rows.
b=size(rows,1); C=reshape(full(rows),b,K,K,blocks);
support=reshape(sum(C,3),b,K,blocks); predicted=reshape(sum(C,2),b,K,blocks);
tp=zeros(b,K,blocks);
for k=1:K,tp(:,k,:)=reshape(C(:,k,k,:),b,1,blocks);end
total=sum(support,2); recall=tp./max(support,1); precision=tp./max(predicted,1);
f1=2*tp./max(support+predicted,1);
specificity=(total-support-predicted+tp)./max(total-support,1);
values=cat(3,reshape(sum(tp,2)./total,b,blocks),reshape(mean(recall,2),b,blocks), ...
    reshape(mean(precision,2),b,blocks),reshape(mean(recall,2),b,blocks), ...
    reshape(mean(f1,2),b,blocks),reshape(sum(f1.*support,2)./total,b,blocks), ...
    reshape(mean(specificity,2),b,blocks));
end

function ci=interval(values)
% MATLAB prctile uses linear interpolation between empirical order statistics.
ci=prctile(values,[2.5 97.5],1);
end

function adjusted=holm(p)
J=numel(p); adjusted=zeros(size(p)); if J==0,return;end
[sorted,order]=sort(p); corrected=min(1,cummax((J-(1:J)'+1).*sorted));
adjusted(order)=corrected;
end

function [point,draws,status]=robustnessValues(snr_point,snr_draws,levels)
M=size(snr_point,1); B=size(snr_draws,1); point=nan(M,5); draws=nan(B,M,5);
clean=find(levels==Inf); noisy=find(isfinite(levels)); status="unavailable: finite endpoints -5 and 30 required";
if ~isempty(clean),point(:,1)=snr_point(:,clean);draws(:,:,1)=snr_draws(:,:,clean);end
if ~isempty(noisy)
    point(:,2)=min(snr_point(:,noisy),[],2); draws(:,:,2)=min(snr_draws(:,:,noisy),[],3);
    point(:,3)=point(:,1)-point(:,2); draws(:,:,3)=draws(:,:,1)-draws(:,:,2);
    point(:,4)=mean(snr_point(:,noisy),2); draws(:,:,4)=mean(snr_draws(:,:,noisy),3);
end
axis=levels(noisy);
if numel(axis)>=2 && axis(1)==-5 && axis(end)==30
    point(:,5)=trapz(axis,snr_point(:,noisy),2)/35;
    draws(:,:,5)=trapz(axis,snr_draws(:,:,noisy),3)/35;
    status="available: trapezoidal uniform dB integral [-5,30]";
end
end

function checks=endpointChecks(values,names,counts)
Q=numel(names); C=numel(counts); largest=interval(values); rows=zeros(Q*C,5);
for c=1:C
    ci=interval(values(1:counts(c),:)); take=(c-1)*Q+(1:Q);
    rows(take,:)=[repmat(counts(c),Q,1) ci' (ci-largest)'];
end
checks=table(repmat(names(:),C,1),rows(:,1),rows(:,2),rows(:,3),rows(:,4),rows(:,5), ...
    'VariableNames',{'endpoint','replicates','ci_low','ci_high','low_minus_final','high_minus_final'});
end

function checks=permutationChecks(exceed,pairs)
R=size(exceed,1); J=size(exceed,2); counts=unique([min(R,[2500 5000 10000]) R]); C=numel(counts);
checks=table(repmat(pairs.method_a,C,1),repmat(pairs.method_b,C,1), ...
    zeros(J*C,1),zeros(J*C,1),zeros(J*C,1),zeros(J*C,1),zeros(J*C,1), ...
    'VariableNames',{'method_a','method_b','replicates','p_raw','p_holm','p_mc_se','p_minus_final'});
for c=1:C
    count=counts(c); hits=sum(exceed(1:count,:),1)'; p=(1+hits)/(count+1); frequency=hits/count;
    take=(c-1)*J+(1:J); checks.replicates(take)=count;
    checks.p_raw(take)=p; checks.p_holm(take)=holm(p);
    checks.p_mc_se(take)=sqrt(count*frequency.*(1-frequency))/(count+1);
    checks.p_minus_final(take)=p-pairs.p_raw;
end
end
