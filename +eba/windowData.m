function [X,P,info]=windowData(F,method,parameters,N,cfg)
%WINDOWDATA Event-centred and background crops inherit their independent family split.
assert(all(F.split~="test"),'eba:TestFirewall','Window model development denies test families.');
assert(N<=cfg.Fs*cfg.clip_duration_s && N>=4 && N==fix(N),'eba:WindowLength','Invalid training window.');
M=round(cfg.Fs*cfg.clip_duration_s);X=zeros(height(F)*12,24);
P=table('Size',[height(F)*12 6],'VariableTypes',{'string','string','double','double','double','double'}, ...
    'VariableNames',{'family_id','split','class_id','family_class_id','SNR_db','window_start_sample'});k=0;time=zeros(height(F)*12,1);
for i=1:height(F)
    p=jsondecode(F.parameters_json(i));
    if F.class_name(i)=="normal" || any(F.class_name(i)==["harmonics","flicker","notching","harmonics_flicker"])
        centers=round([.2 .4 .6 .8]*M);
    else
        centers=[round((p.start_sample+p.end_sample)/2),p.start_sample,p.end_sample,round(N/2)];
    end
    starts=min(M-N,max(0,centers-floor(N/2)));
    for snr=[Inf 20 5]
        signal=eba.record(F(i,:),snr,1,cfg,'development');
        for start=starts
            idx=start+(0:N-1);label=F.class_id(i);
            if F.class_name(i)~="normal" && ~any(idx>=p.start_sample & idx<p.end_sample),label=1;end
            timer=tic;v=eba.features(signal(idx+1),cfg.Fs,method,parameters);elapsed=toc(timer);
            k=k+1;X(k,:)=v;time(k)=elapsed;
            P(k,:)={F.family_id(i),F.split(i),label,F.class_id(i),snr,start};
        end
    end
end
assert(k==size(X,1) && all(isfinite(X),'all'),'eba:WindowData','Invalid training crops.');
info=struct('family_hash',eba.hash(jsonencode(table2struct(F))),'n_families',height(F),'n_records',k, ...
    'window_samples',N,'snrs',[Inf 20 5],'noise_realization',1,'crop_policy','four fixed event-centred/background positions; any physical overlap labelled as event', ...
    'limitation','Very short events occupy a small fraction of long windows; mixed/edge windows are intentionally retained', ...
    'method',method,'parameters',parameters,'feature_time_s',time);
end
