function out = stftAdapter(x,Fs,cfg)
%STFTADAPTER Use Source configuration 45: Blackman 512, 50% overlap.
x = double(x(:));
usedSource = false;
if exist('pq.computeSTFT','file') == 2
    r = pq.computeSTFT(x,Fs,cfg.stft.window_size,cfg.stft.overlap,cfg.stft.window_type);
    usedSource = true;
else
    n=numel(x); W=cfg.stft.window_size; O=cfg.stft.overlap;
    kk=(0:W-1)';
    switch lower(string(cfg.stft.window_type))
        case "hann"
            win=0.5-0.5*cos(2*pi*kk/(W-1));
        case "hamming"
            win=0.54-0.46*cos(2*pi*kk/(W-1));
        case "blackman"
            win=0.42-0.5*cos(2*pi*kk/(W-1))+0.08*cos(4*pi*kk/(W-1));
        otherwise
            error('legacy:Window','Unknown STFT window.');
    end
    step=W-O; starts=1:step:(n-W+1);
    half=floor(W/2)+1; mag=zeros(half,numel(starts));
    for q=1:numel(starts)
        seg=x(starts(q):starts(q)+W-1).*win;
        z=fft(seg); z=z(1:half);
        mag(:,q)=2*abs(z)/sum(win);
    end
    r=struct('frequencies_hz',(0:half-1)'*Fs/W, ...
        'times_s',((starts-1)+W/2)/Fs,'magnitude',mag, ...
        'window_size',W,'overlap',O,'window_type',char(cfg.stft.window_type));
end
power=double(r.magnitude).^2;
[feat,frameScore]=legacy.tfSummaryFeatures(power,r.frequencies_hz,'stft');

% Interpolate frame novelty to sample grid for common interval detector.
if numel(r.times_s) >= 2
    t=(0:numel(x)-1)'/Fs;
    sampleScore=interp1(double(r.times_s(:)),frameScore(:),t,'linear','extrap');
else
    sampleScore=repmat(frameScore(1),numel(x),1);
end
sampleScore=sampleScore+0.35*legacy.timeDomainNovelty(x,Fs,cfg.nominal_frequency_hz);
tmp=r.magnitude; %#ok<NASGU>
w=whos('tmp');
out=struct('features',feat,'local_score',sampleScore,'representation_bytes',w.bytes, ...
    'used_source',usedSource);
end
