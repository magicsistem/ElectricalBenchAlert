function test_dwt()
cfg=legacy.defaultConfig(); T=legacy.loadMetadata(cfg); rec=legacy.loadRecord(T(find(T.label=="oscillatory_transient",1),:),cfg);
out=legacy.dwtFeatures(rec.samples,rec.Fs,'db4',min(5,wmaxlev(numel(rec.samples),'db4')),cfg);
assert(isfield(out.features,'dwt_entropy_norm')); assert(out.representation_bytes>0); assert(numel(out.local_score)==numel(rec.samples));
end
