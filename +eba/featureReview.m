function [review,pairs]=featureReview(X,P,names,cfg)
%FEATUREREVIEW Training-only redundancy and paired noise sensitivity; no selection.
assert(istable(P) && all(ismember({'split','family_id','SNR_db','realization_id'},P.Properties.VariableNames)) && ...
    all(P.split=="train"),'eba:FeatureReviewSplit','Only training families can enter feature review.');
assert(size(X,1)==height(P) && size(X,2)==24 && all(isfinite(X),'all') && numel(names)==24 && ...
    numel(unique(string(names)))==24,'eba:FeatureReviewSchema','The explicit 24-feature schema is required.');
names=string(names(:));sigma=std(X,0,1);scale=iqr(X,1);constant=sigma<=1e-12;
R=corr(X,'Type','Spearman','Rows','complete');R(constant,:)=0;R(:,constant)=0;
[a,b]=find(triu(abs(R)>.95,1));pairs=table(names(a),names(b),R(sub2ind([24 24],a,b)), ...
    'VariableNames',{'feature_a','feature_b','spearman_rho'});
families=unique(P.family_id);levels=unique(P.SNR_db(isfinite(P.SNR_db)));stability=zeros(numel(levels),24);counts=zeros(numel(levels),1);
for f=1:numel(families)
    clean=find(P.family_id==families(f) & P.SNR_db==Inf);
    assert(numel(clean)==1 && P.realization_id(clean)==0,'eba:FeatureReviewPair','Each family needs one clean control.');
    for l=1:numel(levels)
        noisy=find(P.family_id==families(f) & P.SNR_db==levels(l));assert(~isempty(noisy),'eba:FeatureReviewPair','Matched noisy conditions are incomplete.');
        stability(l,:)=stability(l,:)+mean(abs(X(noisy,:)-X(clean,:)),1);counts(l)=counts(l)+1;
    end
end
stability=stability./max(counts,1);normalized=stability./max(scale,1e-12);
review=struct('scope','training-only diagnostics; no feature selection','feature_schema_version',cfg.feature_schema_version, ...
    'names',names,'n_independent_families',numel(families),'n_derived_records',height(P),'training_std',sigma, ...
    'training_iqr',scale,'constant_features',constant,'spearman_matrix',R,'redundant_pair_threshold',.95, ...
    'snr_db',levels,'paired_family_mean_absolute_change',stability,'change_over_training_iqr',normalized, ...
    'zero_iqr_floor',1e-12,'stability_interpretation','Family means average realizations; diagnostic scale, not independent-record confidence intervals');
end
