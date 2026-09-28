function test_dataset_contract()
cfg=legacy.defaultConfig(); r=legacy.validateDataset(cfg,false);
assert(r.ok); assert(r.n_records>0); assert(r.n_classes>=2); assert(isempty(r.family_split_leaks));
end
