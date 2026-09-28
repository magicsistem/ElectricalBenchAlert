function run_all_tests()
startup;
tests={@test_dataset_contract,@test_feature_schema,@test_dwt,@test_cwt,@test_s_transform,@test_metrics};
for k=1:numel(tests)
    fprintf('RUN %s ... ',func2str(tests{k})); feval(tests{k}); fprintf('OK\n');
end
fprintf('ALL_MATLAB_TESTS_PASSED\n');
end
