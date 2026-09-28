function run_all_tests()
startup;
tests={@test_signals,@test_transforms,@test_classifiers,@test_statistics,@test_pipeline};
if exist('test_raw','file'),tests{end+1}=@test_raw;end
if exist('test_streaming','file'),tests{end+1}=@test_streaming;end
if exist('test_runtime','file'),tests{end+1}=@test_runtime;end
for k=1:numel(tests)
    fprintf('RUN %s ... ',func2str(tests{k})); feval(tests{k}); fprintf('OK\n');
end
fprintf('ALL_MATLAB_TESTS_PASSED suites=%d\n',numel(tests));
end
