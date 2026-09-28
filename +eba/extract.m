function [X,P,info] = extract(F,method,parameters,cfg,mode,snrs,realizations)
%EXTRACT Same explicitly chosen family derivatives; immutable data/config/source-bound feature cache.
if nargin<6,snrs=[Inf cfg.snr_db(:).'];end;if nargin<7,realizations=1:cfg.noise_realizations;end
assert(all(F.split~="test") || string(mode)=="final",'eba:TestFirewall','Feature extraction cannot inspect test before final freeze.');
if string(mode)=="final",eba.requireFrozen(cfg);end
assert(~isempty(F),'eba:ExtractEmpty','No families requested.');
famDigest=eba.hash(jsonencode(table2struct(F)));
key=eba.hash(jsonencode(struct('families',famDigest,'method',method,'parameters',parameters, ...
    'snrs',snrs,'realizations',realizations,'mode',mode,'source',eba.hash(fullfile(cfg.root,'+eba','features.m'),'file'), ...
    'record_source',eba.hash(fullfile(cfg.root,'+eba','record.m'),'file'),'waveform_source',eba.hash(fullfile(cfg.root,'+eba','waveform.m'),'file'), ...
    'noise_source',eba.hash(fullfile(cfg.root,'+eba','noise.m'),'file'),'hash_source',eba.hash(fullfile(cfg.root,'+eba','hash.m'),'file'), ...
    'config',eba.hash(fullfile(cfg.root,'config','research_v2.json'),'file'))));
folder=fullfile(cfg.output,'feature_cache');if ~isfolder(folder),mkdir(folder);end
path=fullfile(folder,[key '.mat']);
if isfile(path),S=load(path,'X','P','info');X=S.X;P=S.P;info=S.info;return;end
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
            variant=sprintf('snr%g_rep%d',snr,meta.noise_realization);
            P.record_id(r)=F.family_id(i)+"_"+variant;P.family_id(r)=F.family_id(i);P.split(r)=F.split(i);P.class_id(r)=F.class_id(i);
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
save(path,'X','P','info','-v7');
end
