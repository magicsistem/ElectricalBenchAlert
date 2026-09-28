%% M1: documentation gate
clear; clc; startup;
cfg=legacy.defaultConfig();
root=cfg.project_root;
review=fullfile(root,'docs','legacy','dsp_review.md');
contract=fullfile(root,'docs','legacy','DATASET_CONTRACT.md');
assert(isfile(review),'Missing M1 review.');
assert(isfile(contract),'Missing dataset contract.');
reviewText=fileread(review);
assert(contains(reviewText,'DWT') && contains(reviewText,'CWT') && contains(reviewText,'S-Transform'), ...
    'M1 review is incomplete.');
legacy.makeManifest('01_m1_review',cfg,{review,contract},struct('status','complete'));
fprintf('M1_COMPLETE: %s\n',review);
