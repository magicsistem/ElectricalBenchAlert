function R = robustnessBySNR(P)
%ROBUSTNESSBYSNR M10 classification metrics by SNR on supplied rows.
levels=[30 20 10 5 0 -5];
rows={}; r=0;
classes=unique(P.label,'stable');
for s=levels
    idx=P.SNR_db==s;
    if ~any(idx), continue; end
    M=legacy.classificationMetrics(P.label(idx),P.prediction(idx),classes);
    r=r+1;
    rows(r,:)={s,sum(idx),M.accuracy,M.macro_f1,M.weighted_f1}; %#ok<AGROW>
end
% clean separately
idx=isnan(P.SNR_db);
if any(idx)
    M=legacy.classificationMetrics(P.label(idx),P.prediction(idx),classes);
    r=r+1; rows(r,:)={NaN,sum(idx),M.accuracy,M.macro_f1,M.weighted_f1}; %#ok<AGROW>
end
R=cell2table(rows,'VariableNames',{'SNR_db','n','accuracy','macro_f1','weighted_f1'});
end
