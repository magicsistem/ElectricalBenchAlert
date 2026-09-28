function s = summaryStats(x)
%SUMMARYSTATS Mean, median, SD and normal-approximation 95% CI for descriptive use.
x=double(x(:)); x=x(isfinite(x));
if isempty(x)
    s=struct('n',0,'mean',NaN,'median',NaN,'std',NaN,'ci95_low',NaN,'ci95_high',NaN); return;
end
mu=mean(x); sd=std(x); se=sd/sqrt(numel(x));
s=struct('n',numel(x),'mean',mu,'median',median(x),'std',sd, ...
    'ci95_low',mu-1.96*se,'ci95_high',mu+1.96*se);
end
