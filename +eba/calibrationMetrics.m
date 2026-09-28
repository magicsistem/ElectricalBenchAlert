function r = calibrationMetrics(model,X,y)
%CALIBRATIONMETRICS Multiclass Brier and ten equal-width reliability bins on supplied held-out rows.
[labels,confidence,p]=eba.predict(model,X);y=double(y(:));
[ok,col]=ismember(y,model.classes);assert(all(ok),'eba:CalibrationClass','Unknown held-out class.');
truth=zeros(size(p));truth(sub2ind(size(p),(1:numel(y)).',col))=1;
correct=labels==y;bins=zeros(10,4);ece=0;
for b=1:10
    mask=confidence>=(b-1)/10 & (confidence<b/10 | (b==10 & confidence<=1));
    n=sum(mask);bins(b,1)=n;
    if n>0,bins(b,2)=mean(confidence(mask));bins(b,3)=mean(correct(mask));bins(b,4)=abs(bins(b,2)-bins(b,3));ece=ece+n/numel(y)*bins(b,4);end
end
r=struct('brier',mean(sum((p-truth).^2,2)),'ece_10_bins',ece,'reliability_bins',bins,'n_records',numel(y), ...
    'temperature',model.temperature,'calibrated',model.calibrated);
end
