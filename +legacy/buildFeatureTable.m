function F = buildFeatureTable(method,cfg,varargin)
%BUILDFEATURETABLE Extract one method for all selected metadata rows.
% Optional Name-Value: 'Splits', ["train","validation","test"]
p=inputParser;
addParameter(p,'Splits',["train","validation","test"]);
parse(p,varargin{:});
splits=string(p.Results.Splits);

cfg=legacy.loadSelectedConfig(cfg);
T=legacy.loadMetadata(cfg);
T=T(ismember(T.split,splits),:);
method=upper(string(method));

metaNames={'signal_id','label','severity','Fs','duration_s','n_samples','SNR_db', ...
    'event_start_s','event_end_s','seed','split','family_id','file'};
base=T(:,metaNames);
base.detected_start_s=nan(height(T),1);
base.detected_end_s=nan(height(T),1);
base.processing_time_s=nan(height(T),1);
base.representation_bytes=nan(height(T),1);

X=[]; featureNames={};
for i=1:height(T)
    rec=legacy.loadRecord(T(i,:),cfg);
    out=legacy.runMethod(method,rec.samples,rec.Fs,rec,cfg);
    if isempty(featureNames)
        featureNames=out.feature_names;
        X=nan(height(T),numel(featureNames));
    elseif ~isequal(featureNames,out.feature_names)
        error('legacy:FeatureSchema','Feature schema changed for %s at %s.',method,rec.signal_id);
    end
    X(i,:)=out.feature_vector;
    base.detected_start_s(i)=out.detected_start_s;
    base.detected_end_s(i)=out.detected_end_s;
    base.processing_time_s(i)=out.processing_time_s;
    base.representation_bytes(i)=out.representation_bytes;
    if mod(i,25)==0 || i==height(T)
        fprintf('%s features: %d/%d\n',method,i,height(T));
    end
end

F=base;
for j=1:numel(featureNames)
    vn=matlab.lang.makeValidName(featureNames{j});
    F.(vn)=X(:,j);
end

legacy.ensureDirs(cfg);
tag=lower(char(method));
csvPath=fullfile(cfg.output.features,[tag '_features.csv']);
matPath=fullfile(cfg.output.features,[tag '_features.mat']);
writetable(F,csvPath);
save(matPath,'F','featureNames','method','-v7.3');
end
