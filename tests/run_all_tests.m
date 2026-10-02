function run_all_tests()
startup;
tests={@test_streaming,@test_firewall};
for k=1:numel(tests)
    fprintf('RUN %s ... ',func2str(tests{k})); feval(tests{k}); fprintf('OK\n');
end
fprintf('ALL_MATLAB_TESTS_PASSED suites=%d\n',numel(tests));
end
