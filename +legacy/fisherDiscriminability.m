function score = fisherDiscriminability(X,labels)
%FISHERDISCRIMINABILITY Robust multiclass Fisher separation score.
X = double(X);
labels = string(labels(:));
if size(X,1) ~= numel(labels), error('legacy:Shape','X/labels mismatch.'); end
validCols = all(isfinite(X),1) & std(X,0,1)>eps;
X = X(:,validCols);
if isempty(X), score = 0; return; end
classes = unique(labels);
mu = mean(X,1);
between = zeros(1,size(X,2));
within = zeros(1,size(X,2));
for k=1:numel(classes)
    idx = labels==classes(k);
    nk = sum(idx);
    if nk==0, continue; end
    muk = mean(X(idx,:),1);
    between = between + nk*(muk-mu).^2;
    if nk>1
        within = within + sum((X(idx,:)-muk).^2,1);
    end
end
f = between ./ max(within,eps);
f = f(isfinite(f));
if isempty(f), score=0; return; end
f = sort(f,'descend');
score = median(f(1:min(5,numel(f))));
end
