function test_s_transform()
cfg=legacy.defaultConfig(); T=legacy.loadMetadata(cfg); rec=legacy.loadRecord(T(find(T.label=="oscillatory_transient",1),:),cfg);
[S,f]=legacy.sTransform(rec.samples,rec.Fs,cfg);
assert(size(S,2)==numel(rec.samples)); assert(size(S,1)==numel(f)); assert(all(diff(f)>0));
end
