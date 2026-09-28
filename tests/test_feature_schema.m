function test_feature_schema()
cfg=legacy.defaultConfig(); T=legacy.loadMetadata(cfg); rec=legacy.loadRecord(T(1,:),cfg);
for method=["FFT","STFT","DWT"]
    out=legacy.runMethod(method,rec.samples,rec.Fs,rec,cfg);
    assert(~isempty(out.feature_vector)); assert(all(isfinite(out.feature_vector)));
end
end
