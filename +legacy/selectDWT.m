function [selected,results] = selectDWT(cfg)
%SELECTDWT M2 wavelet/level selection without touching test split.
T = legacy.loadMetadata(cfg);
T = T(T.split=="train" | T.split=="validation",:);
if any(T.split=="test"), error('legacy:Leakage','Test rows entered DWT selection.'); end

wavelets = cfg.dwt.candidate_wavelets;
levels = cfg.dwt.candidate_levels;
rows = {};
r = 0;
for w=1:numel(wavelets)
    name = string(wavelets{w});
    maxL = wmaxlev(double(T.n_samples(1)),char(name));
    for level=levels
        if level>maxL, continue; end
        X=[]; y=strings(0,1); times=[];
        expectedNames = {};
        for i=1:height(T)
            rec = legacy.loadRecord(T(i,:),cfg);
            t0=tic;
            out=legacy.dwtFeatures(rec.samples,rec.Fs,name,level,cfg);
            times(end+1,1)=toc(t0); %#ok<AGROW>
            [v,names]=legacy.structToFeatureVector(out.features);
            if isempty(expectedNames), expectedNames=names; end
            if ~isequal(names,expectedNames)
                error('legacy:FeatureSchema','DWT feature schema changed within candidate.');
            end
            X(end+1,:)=v; %#ok<AGROW>
            y(end+1,1)=rec.label; %#ok<AGROW>
        end
        discr=legacy.fisherDiscriminability(X,y);
        r=r+1;
        rows(r,:)={char(name),level,discr,median(times),prctile(times,95),size(X,2)}; %#ok<AGROW>
        fprintf('DWT candidate %s L%d: Fisher=%.6g, median=%.4g s\n',name,level,discr,median(times));
    end
end
results=cell2table(rows,'VariableNames',{'wavelet','level','fisher_score','median_runtime_s','p95_runtime_s','n_features'});

% Composite criterion: high discriminability, low runtime. Robust rank-normalization.
[~,ordD]=sort(results.fisher_score,'descend'); rankD=zeros(height(results),1); rankD(ordD)=1:height(results);
[~,ordT]=sort(results.median_runtime_s,'ascend'); rankT=zeros(height(results),1); rankT(ordT)=1:height(results);
if height(results)>1
    nd=(rankD-1)/(height(results)-1);
    nt=(rankT-1)/(height(results)-1);
else
    nd=0; nt=0;
end
results.selection_score = nd + cfg.dwt.selection_runtime_weight*nt;
[~,best]=min(results.selection_score);
selected=struct('wavelet',string(results.wavelet(best)),'level',results.level(best), ...
    'fisher_score',results.fisher_score(best),'median_runtime_s',results.median_runtime_s(best), ...
    'selection_score',results.selection_score(best), ...
    'used_splits',{{'train','validation'}},'test_used',false);

legacy.ensureDirs(cfg);
writetable(results,fullfile(cfg.output.root,'dwt_selection.csv'));
legacy.writeJson(fullfile(cfg.output.root,'dwt_selected.json'),selected);
save(fullfile(cfg.output.root,'dwt_selection.mat'),'results','selected');
end
