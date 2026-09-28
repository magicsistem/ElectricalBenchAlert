function test_cwt()
cfg=legacy.defaultConfig(); T=legacy.loadMetadata(cfg); rec=legacy.loadRecord(T(find(T.label=="impulsive_transient",1),:),cfg);
out=legacy.cwtFeatures(rec.samples,rec.Fs,cfg);
assert(out.representation_bytes>0); assert(numel(out.local_score)==numel(rec.samples)); assert(all(isfinite(out.local_score)));
end
