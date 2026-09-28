function [labels,confidence,probabilities,raw_scores] = predict(model,X)
%PREDICT Explicit feature schema; calibrated confidence is defined by the recorded temperature.
X=double(X);assert(size(X,2)==numel(model.mean) && all(isfinite(X),'all'),'eba:PredictInput','Feature matrix violates fitted schema.');
Z=(X(:,model.keep)-model.mean(model.keep))./model.scale(model.keep);
[~,scores]=predict(model.fitted,Z);scores=double(scores);
if model.kind=="RF", scores=log(max(scores,1e-12)); end
raw_scores=scores;
a=scores/model.temperature;a=a-max(a,[],2);probabilities=exp(a);probabilities=probabilities./sum(probabilities,2);
[confidence,k]=max(probabilities,[],2);labels=model.classes(k);
end
