function m = metrics(y,p,K)
%METRICS Fixed-class confusion-derived metrics, zero division returns zero.
y=double(y(:)); p=double(p(:));
assert(numel(y)==numel(p) && ~isempty(y),'eba:MetricShape','Labels must have equal nonempty length.');
assert(all(isfinite([y;p])) && all([y;p]>=1) && all([y;p]<=K) && all(mod([y;p],1)==0),'eba:MetricLabel','Labels must be declared class IDs.');
C=accumarray([y p],1,[K K]); tp=diag(C); support=sum(C,2); predicted=sum(C,1).';
recall=tp./max(support,1); precision=tp./max(predicted,1);
f1=2*tp./max(support+predicted,1); N=sum(C,'all');
specificity=(N-support-predicted+tp)./max(N-support,1);
m=struct('accuracy',sum(tp)/N,'balanced_accuracy',mean(recall), ...
    'macro_precision',mean(precision),'macro_recall',mean(recall),'macro_f1',mean(f1), ...
    'weighted_f1',sum(f1.*support)/N,'macro_specificity',mean(specificity), ...
    'confusion',C,'precision',precision,'recall',recall,'f1',f1,'specificity',specificity,'support',support,'n_records',N);
end
