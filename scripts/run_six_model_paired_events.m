function T=run_six_model_paired_events()
%RUN_SIX_MODEL_PAIRED_EVENTS Family-paired bootstrap and swap tests for event F1.
cfg=eba.config();folder=fullfile(cfg.output,'six_model_stream');
S=readtable(fullfile(folder,'six_model_stream_validation.csv'),'TextType','string');
methods=S.method+"_"+S.classifier;K=864;B=10000;Y=zeros(K,3,height(S));families=strings(K,1);inputs=strings(height(S)+1,1);
inputs(1)=fullfile(folder,'six_model_stream_validation.csv');
for m=1:height(S)
    if S.classifier(m)=="SVM",name="details_svm_"+lower(S.method(m))+".mat";
    else,name="details_rf_"+lower(S.method(m))+".mat";end
    detailPath=fullfile(folder,name);inputs(m+1)=detailPath;D=load(detailPath,'details');C=D.details.clusters;
    assert(height(C)==K && numel(unique(C.independent_cluster_id))==K, ...
        'eba:PairedEventsClusters','Expected one independent family/sequence cluster per row.');
    [ok,loc]=ismember(string(C.sequence_id),string(D.details.exposure.sequence_id));
    assert(all(ok),'eba:PairedEventsIdentity','Cluster sequence is missing exposure metadata.');
    f=string(D.details.exposure.family_id(loc));
    if m==1,families=f;else,assert(isequal(f,families),'eba:PairedEventsPairing','Family order differs across candidates.');end
    Y(:,:,m)=[C.true_positives,C.false_positives,C.false_negatives];
end
assert(numel(unique(families))==K,'eba:PairedEventsIndependence','Families must be independent and unique.');
master=cfg.master_seed;rb=RandStream('mt19937ar','Seed',mod(double(master)+81001,2^32));
draws=zeros(B,height(S));
for b=1:B
    n=accumarray(randi(rb,K,[K 1]),1,[K 1]);
    for m=1:height(S),z=n'*Y(:,:,m);draws(b,m)=2*z(1)/max(2*z(1)+z(2)+z(3),1);end
end
pairs=nchoosek(1:height(S),2);nPairs=size(pairs,1);delta=zeros(nPairs,1);lo=delta;hi=delta;
praw=ones(nPairs,1);mcse=delta;permutations=10000;rp=RandStream('mt19937ar','Seed',mod(double(master)+82001,2^32));
for q=1:nPairs
    a=pairs(q,1);b=pairs(q,2);delta(q)=S.event_f1(a)-S.event_f1(b);
    d=draws(:,a)-draws(:,b);ci=quantile(d,[.025 .975]);lo(q)=ci(1);hi(q)=ci(2);
    xa=Y(:,:,a);xb=Y(:,:,b);exceed=0;
    for r=1:permutations
        sw=rand(rp,K,1)<.5;u=sum(xa(~sw,:),1)+sum(xb(sw,:),1);v=sum(xb(~sw,:),1)+sum(xa(sw,:),1);
        da=2*u(1)/max(2*u(1)+u(2)+u(3),1);db=2*v(1)/max(2*v(1)+v(2)+v(3),1);
        exceed=exceed+(abs(da-db)>=abs(delta(q)));
    end
    praw(q)=(exceed+1)/(permutations+1);mcse(q)=sqrt(praw(q)*(1-praw(q))/(permutations+1));
end
[sortedP,order]=sort(praw);sortedHolm=zeros(nPairs,1);
for j=1:nPairs
    previous=0;if j>1,previous=sortedHolm(j-1);end
    sortedHolm(j)=min(1,max(previous,(nPairs-j+1)*sortedP(j)));
end
holm(order)=sortedHolm;
methodA=methods(pairs(:,1));methodB=methods(pairs(:,2));
methodA=methodA(:);methodB=methodB(:);delta=delta(:);lo=lo(:);hi=hi(:);praw=praw(:);holm=holm(:);mcse=mcse(:);
assert(all([numel(methodA),numel(methodB),numel(delta),numel(lo),numel(hi),numel(praw),numel(holm),numel(mcse)]==nPairs), ...
    'eba:PairedEventsShape','Pairwise result vectors have inconsistent lengths.');
T=table(methodA,methodB,delta,lo,hi,praw,holm,mcse, ...
    repmat(K,nPairs,1),repmat(B,nPairs,1),repmat(permutations,nPairs,1), ...
    'VariableNames',{'method_a','method_b','delta_f1_a_minus_b','delta_ci_low','delta_ci_high', ...
    'p_raw','p_holm','permutation_mc_se','independent_families','bootstrap_replicates','permutation_replicates'});
assert(all(T.delta_ci_low<=T.delta_f1_a_minus_b & T.delta_f1_a_minus_b<=T.delta_ci_high) && ...
    all(T.p_holm>=T.p_raw & T.p_holm<=1),'eba:PairedEventsInference','Paired inference invariant failed.');
out=fullfile(folder,'six_model_paired_event_f1.csv');writetable(T,out);
eba.manifest('six_model_paired_event_f1',cfg,struct('scope','all 15 paired event-F1 contrasts; shared family bootstrap and family-level model-label swaps; validation only; test not accessed', ...
    'families',K,'bootstrap_replicates',B,'permutation_replicates',permutations, ...
    'master_seed',master,'test_accessed',false),[string(out);inputs]);
fprintf('SIX_MODEL_PAIRED_EVENTS_PASS pairs=%d families=%d bootstrap=%d permutation=%d test_accessed=0\n',nPairs,K,B,permutations);
end
