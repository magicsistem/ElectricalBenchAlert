function [X,P,info] = extract(F,method,parameters,cfg,mode,snrs,realizations)
%EXTRACT Same explicitly chosen family derivatives; immutable data/config/source-bound feature cache.
if nargin<6,snrs=[Inf cfg.snr_db(:).'];end;if nargin<7,realizations=1:cfg.noise_realizations;end
assert(all(F.split~="test") || string(mode)=="final",'eba:TestFirewall','Feature extraction cannot inspect test before final freeze.');
if string(mode)=="final",eba.requireFrozen(cfg);end
assert(~isempty(F),'eba:ExtractEmpty','No families requested.');
[key,famDigest]=eba.featureCacheKey(F,method,parameters,cfg,mode,snrs,realizations);
folder=fullfile(cfg.output,'feature_cache');if ~isfolder(folder),mkdir(folder);end
path=fullfile(folder,[key '.mat']);
if isfile(path)
    S=load(path,'X','P','info');X=S.X;P=S.P;info=S.info;
    assert(isstruct(info) && all(isfield(info,{'signature','numeric_sha256','record_metadata_sha256'})) && ...
        strcmp(info.signature,key) && all(isfinite(X),'all') && ...
        strcmp(info.numeric_sha256,eba.hash(X,'numeric')) && ...
        strcmp(info.record_metadata_sha256,eba.hash(jsonencode(table2struct(P)))), ...
        'eba:FeatureCacheMutation','Cached features or prediction metadata differ from their stored content hashes.');
    return;
end
vcount=sum(isinf(snrs))+sum(isfinite(snrs))*numel(realizations);n=height(F)*vcount;
P=table('Size',[n 9],'VariableTypes',{'string','string','string','double','double','double','double','double','string'}, ...
    'VariableNames',{'record_id','family_id','split','class_id','SNR_db','realization_id','requested_snr_db','measured_snr_db','waveform_sha256'});
X=[];timings=zeros(n,1);representation_bytes=zeros(n,1);r=0;
for i=1:height(F)
    for snr=snrs
        reps=realizations;if isinf(snr),reps=1;end
        for rep=reps
            [x,meta]=eba.record(F(i,:),snr,rep,cfg,mode);
            timer=tic;[features,names,bytes]=eba.features(x,cfg.Fs,method,parameters);timings(r+1)=toc(timer);
            if isempty(X),X=zeros(n,numel(features));feature_names=string(names);end
            assert(isequal(string(names),feature_names),'eba:FeatureSchema','Feature names changed during experiment.');
            r=r+1;X(r,:)=features;representation_bytes(r)=bytes;
            P.record_id(r)=string(meta.record_id);P.family_id(r)=F.family_id(i);P.split(r)=F.split(i);P.class_id(r)=F.class_id(i);
            P.SNR_db(r)=snr;P.realization_id(r)=meta.noise_realization;
            P.requested_snr_db(r)=snr;P.measured_snr_db(r)=meta.measured_snr_db;P.waveform_sha256(r)=meta.waveform_sha256;
        end
    end
    if mod(i,50)==0 || i==height(F),fprintf('%s %s features families %d/%d\n',method,mode,i,height(F));end
end
assert(r==n && all(isfinite(X),'all'),'eba:ExtractInvariant','Invalid feature extraction output.');
info=struct('signature',key,'family_hash',famDigest,'method',string(method),'parameters',parameters, ...
    'feature_names',feature_names,'feature_schema_version',cfg.feature_schema_version, ...
    'n_families',height(F),'n_records',n,'snrs',snrs,'realizations',realizations, ...
    'feature_time_s',timings,'representation_bytes',representation_bytes);
info.numeric_sha256=eba.hash(X,'numeric');info.record_metadata_sha256=eba.hash(jsonencode(table2struct(P)));
save(path,'X','P','info','-v7');
end
