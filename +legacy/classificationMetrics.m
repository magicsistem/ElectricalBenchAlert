function out = classificationMetrics(yTrue,yPred,classOrder)
%CLASSIFICATIONMETRICS M7 multiclass metrics.
yTrue=string(yTrue(:)); yPred=string(yPred(:));
if nargin<3 || isempty(classOrder)
    classOrder=unique([yTrue;yPred],'stable');
else
    classOrder=string(classOrder(:));
end
C=confusionmat(categorical(yTrue,classOrder),categorical(yPred,classOrder), ...
    'Order',categorical(classOrder,classOrder));
C=double(C);
K=numel(classOrder);
precision=zeros(K,1); recall=zeros(K,1); specificity=zeros(K,1); f1=zeros(K,1); support=zeros(K,1);
for k=1:K
    TP=C(k,k); FN=sum(C(k,:))-TP; FP=sum(C(:,k))-TP; TN=sum(C(:))-TP-FN-FP;
    precision(k)=TP/max(TP+FP,eps);
    recall(k)=TP/max(TP+FN,eps);
    specificity(k)=TN/max(TN+FP,eps);
    f1(k)=2*precision(k)*recall(k)/max(precision(k)+recall(k),eps);
    support(k)=sum(C(k,:));
end
acc=sum(diag(C))/max(sum(C(:)),eps);
macroF1=mean(f1);
weightedF1=sum(f1.*support)/max(sum(support),eps);
out=struct();
out.accuracy=acc;
out.macro_f1=macroF1;
out.weighted_f1=weightedF1;
out.macro_precision=mean(precision);
out.macro_recall=mean(recall);
out.macro_specificity=mean(specificity);
out.confusion_matrix=C;
out.class_order=cellstr(classOrder);
out.per_class=table(classOrder,precision,recall,specificity,f1,support, ...
    'VariableNames',{'class','precision','recall','specificity','f1','support'});
end
