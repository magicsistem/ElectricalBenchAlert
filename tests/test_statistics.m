function test_statistics()
%TEST_STATISTICS Deterministic mathematical controls, not final scientific results.
cfg=struct('classes',["a";"b";"c"],'bootstrap_replicates',100, ...
    'permutation_replicates',100,'master_seed',84231);
C=[8 2 0;1 6 3;2 1 7]; y=[]; p=[];
for actual=1:3
    for predicted=1:3
        y=[y;repmat(actual,C(actual,predicted),1)]; %#ok<AGROW>
        p=[p;repmat(predicted,C(actual,predicted),1)]; %#ok<AGROW>
    end
end
P=metadata(y,Inf,0);
[s,pairs,r,d]=eba.familyStats(P,p,"known",cfg);
assert(isequal(d.point_metrics{1}.confusion,C));
recall=[.8;.6;.7]; precision=[8/11;6/9;7/10]; f1=[16/21;12/19;14/20];
specificity=[17/20;17/20;17/20];
assert(abs(s.accuracy-.7)<1e-12 && abs(s.balanced_accuracy-mean(recall))<1e-12);
assert(abs(s.macro_precision-mean(precision))<1e-12 && abs(s.macro_recall-mean(recall))<1e-12);
assert(abs(s.macro_f1-mean(f1))<1e-12 && abs(s.weighted_f1-mean(f1))<1e-12);
assert(abs(s.macro_specificity-mean(specificity))<1e-12);
assert(max(abs(d.per_class_recall.recall-recall))<1e-12);
assert(s.n_families==30 && s.n_records==30 && isempty(pairs) && height(r)==1);
assert(d.bootstrap_replicates==100 && ~d.mc_full_checkpoints_available);
assert(all(d.mc_endpoint_checks.replicates==100));
assert(isequal(d.reference_ids,[16 17 18 19]));
assert(isempty(d.permutation_pair_seeds) || all(d.bootstrap_seed~=d.permutation_pair_seeds));
assert(height(d.per_class_recall)==3 && isequal(size(d.per_class_recall.method),[3 1]));

% Unequal class supports distinguish weighted F1 from Macro-F1.
unequal=P(1:end-3,:); unequal_p=p(1:end-3);
[us,~,~,ud]=eba.familyStats(unequal,unequal_p,"unequal",cfg);
unequal_f1=[16/21;12/19;4/7];
assert(isequal(ud.point_metrics{1}.support,[10;10;7]));
assert(abs(us.weighted_f1-sum(unequal_f1.*[10;10;7])/27)<1e-12);
assert(abs(us.weighted_f1-us.macro_f1)>1e-3);

% Identical paired methods have zero difference, zero interval and p=1.
[same,paired,~,same_details]=eba.familyStats(P,repmat(p,1,5),["FFT","STFT","DWT","CWT","ST"],cfg);
assert(height(paired)==10 && all(paired.delta_macro_f1==0));
assert(all(paired.delta_pp_ci_low==0 & paired.delta_pp_ci_high==0));
assert(all(paired.p_raw==1 & paired.p_holm==1 & paired.p_mc_se==0));
assert(all(paired.exceedances==cfg.permutation_replicates));
assert(all(same.macro_f1_ci_low==same.macro_f1_ci_low(1)));
assert(all(same.macro_f1_ci_high==same.macro_f1_ci_high(1)));
assert(height(same_details.mc_permutation_checks)==10);
assert(all(same_details.mc_permutation_checks.p_raw==1));
assert(height(same_details.per_class_recall)==15 && isequal(size(same_details.per_class_recall.method),[15 1]));

% Controlled superiority checks sign and units without assuming a sampled p.
predictions=[y ones(size(y)) p mod(y,3)+1];
[~,different,~,dd]=eba.familyStats(P,predictions,["perfect","constant","known","wrong"],cfg);
assert(different.delta_macro_f1(1)>0 && different.delta_pp(1)==100*different.delta_macro_f1(1));
assert(different.delta_pp_ci_low(1)>0 && different.delta_pp_ci_high(1)<=100);
assert(all(different.p_raw>0 & different.p_raw<=1 & different.p_holm>=different.p_raw & different.p_holm<=1));
[sorted,order]=sort(different.p_raw);
expected=min(1,cummax((height(different)-(1:height(different))'+1).*sorted));
assert(max(abs(different.p_holm(order)-expected))<1e-12);
assert(all(diff(different.p_holm(order))>=0));
for j=1:height(different)
    frequency=different.exceedances(j)/100;
    assert(abs(different.p_raw(j)-(1+different.exceedances(j))/101)<1e-12);
    assert(abs(different.p_mc_se(j)-sqrt(100*frequency*(1-frequency))/101)<1e-12);
end
assert(all(dd.mc_permutation_checks.replicates==100));

% Sorting the family IDs makes exact seeded inference invariant to row order.
[reordered,reordered_pairs,reordered_r,reordered_d]=eba.familyStats(P(end:-1:1,:), ...
    predictions(end:-1:1,:),["perfect","constant","known","wrong"],cfg);
[original,original_pairs,original_r,original_d]=eba.familyStats(P,predictions,["perfect","constant","known","wrong"],cfg);
assert(isequaln(reordered,original) && isequaln(reordered_pairs,original_pairs));
assert(isequaln(reordered_r,original_r));
assert(isequaln(reordered_d.mc_endpoint_checks,original_d.mc_endpoint_checks));
assert(isequaln(reordered_d.mc_permutation_checks,original_d.mc_permutation_checks));

% Appending all 18 noisy derivatives changes the record count, not independence.
levels=[-5;0;5;10;20;30;Inf];
[fullP,base_index]=derivatives(P,levels,3);
[full_s,full_pairs,full_r,full_d]=eba.familyStats(fullP,repmat(p(base_index),1,2),["one","two"],cfg);
assert(all(full_s.n_families==30 & full_s.n_records==30*19));
assert(all(full_d.family_counts.records_per_family==19));
assert(abs(full_s.macro_f1(1)-s.macro_f1)<1e-12);
assert(abs(full_s.macro_f1_ci_low(1)-s.macro_f1_ci_low)<1e-12);
assert(abs(full_s.macro_f1_ci_high(1)-s.macro_f1_ci_high)<1e-12);
assert(all(full_pairs.delta_pp==0 & full_pairs.p_holm==1));
assert(all(full_r.n_families==30));
clean_counts=full_r.n_records(full_r.SNR_db==Inf);
assert(numel(clean_counts)==2 && all(clean_counts==30));
assert(all(full_r.n_records(isfinite(full_r.SNR_db))==90));
assert(all(full_d.robustness_summary.clean_minus_worst==0));
assert(abs(full_d.robustness_summary.normalized_snr_auc(1)-s.macro_f1)<1e-12);

% Unequal dB spacing means area and the equal-level mean are different estimands.
noise_p=fullP.class_id;
noise_p(fullP.SNR_db<=0)=1;
noise_p(fullP.SNR_db==5)=mod(noise_p(fullP.SNR_db==5),3)+1;
[~,~,curve,curve_d]=eba.familyStats(fullP,noise_p,"noise",cfg);
finite=isfinite(curve.SNR_db); clean=curve.macro_f1(curve.SNR_db==Inf);
expected_auc=trapz(curve.SNR_db(finite),curve.macro_f1(finite))/35;
expected_mean=mean(curve.macro_f1(finite));
rs=curve_d.robustness_summary;
assert(abs(rs.normalized_snr_auc-expected_auc)<1e-12);
assert(abs(rs.mean_noisy_macro_f1-expected_mean)<1e-12 && abs(expected_auc-expected_mean)>1e-3);
assert(abs(rs.clean_minus_worst-(clean-min(curve.macro_f1(finite))))<1e-12);
assert(all(curve.macro_f1_ci_low<=curve.macro_f1_ci_high));
assert(rs.clean_macro_f1==1 && rs.clean_macro_f1_ci_low==1 && rs.clean_macro_f1_ci_high==1);
assert(isnan(d.robustness_summary.normalized_snr_auc));
assert(height(curve)==7 && isequal(size(curve.method),[7 1]));

% RF sensitivity must carry a separately declared comparison-family identifier.
rf_cfg=cfg; rf_cfg.comparison_family="rf_sensitivity";
[~,rf_pairs,~,rf_d]=eba.familyStats(P,repmat(p,1,6),["a","b","c","d","e","extra"],rf_cfg);
assert(height(rf_pairs)==10 && ~any(rf_pairs.method_a=="extra" | rf_pairs.method_b=="extra"));
assert(all(rf_pairs.comparison_family=="rf_sensitivity") && rf_d.comparison_family=="rf_sensitivity");

% Explicit secondary comparison families may reference later methods, with one Holm correction.
custom=cfg;custom.planned_comparisons=[1 6;3 6];custom.comparison_family="planned_secondary";
[~,customPairs]=eba.familyStats(P,repmat(p,1,6),["a","b","c","d","e","f"],custom);
assert(height(customPairs)==2 && all(customPairs.method_b=="f") && customPairs.method_a(2)=="c");
assert(all(customPairs.p_holm==1 & customPairs.comparison_family=="planned_secondary"));
for invalid={[1 1],[1 7],[1 2;2 1],[1 2.5]}
    bad=custom;bad.planned_comparisons=invalid{1};
    fails(@() eba.familyStats(P,repmat(p,1,6),["a","b","c","d","e","f"],bad),'eba:StatisticsComparisons');
end

% Missing observed classes remain in the fixed confusion matrix and Macro-F1.
only=metadata(ones(4,1),Inf,0);
[one,~,~,od]=eba.familyStats(only,ones(4,1),"single-class",cfg);
assert(isequal(size(od.point_metrics{1}.confusion),[3 3]));
assert(one.macro_f1==1/3 && one.balanced_accuracy==1/3);
assert(isequal(od.point_metrics{1}.support,[4;0;0]));
assert(isequal(od.per_class_recall.recall_ci_low,[1;0;0]));
singleton=metadata((1:3)',Inf,0);
[~,~,~,sd]=eba.familyStats(singleton,(1:3)',"singleton",cfg);
assert(isequal(sd.singleton_class_strata,(1:3)'));

% Full taxonomy is 12: primary_class_count=9 never truncates metric classes.
repo=fileparts(fileparts(mfilename('fullpath')));
full_cfg=jsondecode(fileread(fullfile(repo,'config','research_v2.json')));
full_cfg.classes=string(full_cfg.classes(:));
assert(numel(full_cfg.classes)==12 && full_cfg.primary_class_count==9);
full_cfg.bootstrap_replicates=100; full_cfg.permutation_replicates=100;
full_labels=repelem((1:12)',2,1); twelve=metadata(full_labels,Inf,0);
[twelve_s,twelve_pairs,twelve_r,twelve_d]=eba.familyStats(twelve,full_labels,"full",full_cfg);
assert(twelve_d.declared_class_count==12 && isequal(size(twelve_d.point_metrics{1}.confusion),[12 12]));
assert(twelve_s.macro_f1==1 && twelve_s.n_families==24 && isempty(twelve_pairs) && height(twelve_r)==1);
assert(height(twelve_d.per_class_recall)==12 && all(twelve_d.per_class_recall.recall==1));
[absent_s,~,~,absent_d]=eba.familyStats(only,ones(4,1),"absent",full_cfg);
assert(absent_s.macro_f1==1/12 && height(absent_d.per_class_recall)==12);
assert(isequal(absent_d.point_metrics{1}.support,[4;zeros(11,1)]));
assert(isequal(absent_d.per_class_recall.recall_ci_low,[1;zeros(11,1)]));

% Explicit singleton dimensions: one class/method/level and multiple methods/levels.
small_cfg=cfg; small_cfg.classes="only"; small_cfg.primary_class_count=1;
[small_s,small_pairs,small_r,small_d]=eba.familyStats(only,ones(4,1),"one",small_cfg);
assert(height(small_s)==1 && isempty(small_pairs) && height(small_r)==1);
assert(height(small_d.per_class_recall)==1 && small_s.macro_f1==1);
[two_levels,small_index]=derivatives(only,[-5;Inf],1);
[small_s,small_pairs,small_r,small_d]=eba.familyStats(two_levels,ones(numel(small_index),2),["one","two"],small_cfg);
assert(height(small_s)==2 && height(small_pairs)==1 && height(small_r)==4);
assert(isequal(size(small_r.method),[4 1]) && height(small_d.per_class_recall)==2);

% The explicit streams must leave the caller's RNG state untouched.
before=rng;
eba.familyStats(P,predictions,["perfect","constant","known","wrong"],cfg);
assert(isequal(rng,before));

% Trust-boundary negatives must fail with the intended identifier.
bad=P; bad.family_id(2)=bad.family_id(1); bad.class_id(2)=2;
fails(@() eba.familyStats(bad,p,"x",cfg),'eba:StatisticsFamilyClass');
bad=P; bad.record_id(2)=bad.record_id(1);
fails(@() eba.familyStats(bad,p,"x",cfg),'eba:StatisticsRecords');
bad=P; bad.family_id(1)="";
fails(@() eba.familyStats(bad,p,"x",cfg),'eba:StatisticsFamilies');
bad=fullP; bad(end,:)=[];
fails(@() eba.familyStats(bad,p(base_index(1:end-1)),"x",cfg),'eba:StatisticsDesign');
bad=fullP; bad.record_id(end)="new_id"; bad.family_id(end)=bad.family_id(end-1);
fails(@() eba.familyStats(bad,p(base_index),"x",cfg),'eba:StatisticsDesign');
bad=P; bad.SNR_db(1)=NaN;
fails(@() eba.familyStats(bad,p,"x",cfg),'eba:StatisticsConditions');
bad=P; bad.realization_id(1)=1;
fails(@() eba.familyStats(bad,p,"x",cfg),'eba:StatisticsConditions');
bad_p=p; bad_p(1)=NaN;
fails(@() eba.familyStats(P,bad_p,"x",cfg),'eba:StatisticsLabels');
bad_p=p; bad_p(1)=4;
fails(@() eba.familyStats(P,bad_p,"x",cfg),'eba:StatisticsLabels');
fails(@() eba.familyStats(P,[p p],"x",cfg),'eba:StatisticsShape');
fails(@() eba.familyStats(P,[p p],["x","x"],cfg),'eba:StatisticsMethods');
bad_cfg=cfg; bad_cfg.bootstrap_replicates=1;
fails(@() eba.familyStats(P,p,"x",bad_cfg),'eba:StatisticsReplicates');
bad_cfg=cfg; bad_cfg.master_seed=-1;
fails(@() eba.familyStats(P,p,"x",bad_cfg),'eba:StatisticsSeed');
bad_cfg=cfg; bad_cfg.classes=["a";"a";"c"];
fails(@() eba.familyStats(P,p,"x",bad_cfg),'eba:StatisticsConfig');

% Pareto: maximize first, minimize second; retain ties and drop nonfinite rows.
X=[.9 .1;.8 .2;.95 .3;.9 .1;NaN .01;.99 Inf];
assert(isequal(eba.pareto(X,[1 -1]),[true;false;true;true;false;false]));
assert(isequal(eba.pareto([-2 -2;-1 -1;-1 -1],[-1 1]),[true;true;true]));
assert(isequal(eba.pareto([1 1;2 2;2 2],[1 1]),[false;true;true]));
assert(isempty(eba.pareto(zeros(0,2),[1 -1])));
assert(~any(eba.pareto([NaN 1;1 Inf],[1 -1])));
fails(@() eba.pareto(X,[1 0]),'eba:ParetoDirections');
fails(@() eba.pareto(X,1),'eba:ParetoDirections');
fails(@() eba.pareto(X,[1 -1;1 -1]),'eba:ParetoDirections');
fails(@() eba.pareto([1+1i 2],[1 -1]),'eba:ParetoData');
fprintf('STATISTICS_SCIENTIFIC_TESTS_PASS\n');
end

function P=metadata(y,snr,realization)
n=numel(y); record_id="record_"+compose("%04d",(1:n)'); family_id="family_"+compose("%04d",(1:n)');
class_id=y(:); SNR_db=repmat(snr,n,1); realization_id=repmat(realization,n,1);
P=table(record_id,family_id,class_id,SNR_db,realization_id);
end

function [Q,index]=derivatives(P,levels,realizations)
Q=P([],:); index=zeros(0,1);
for l=1:numel(levels)
    ids=1:realizations; if levels(l)==Inf,ids=0;end
    for r=ids
        block=P; block.SNR_db(:)=levels(l); block.realization_id(:)=r;
        block.record_id=block.record_id+"_level_"+l+"_draw_"+r;
        Q=[Q;block]; index=[index;(1:height(P))']; %#ok<AGROW>
    end
end
end

function fails(action,id)
try
    action();
catch exception
    assert(strcmp(exception.identifier,id),'Unexpected error: %s',exception.identifier); return;
end
error('test:MissingError','Expected error %s.',id);
end
