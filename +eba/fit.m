function model = fit(X,y,cfg,kind,hp)
%FIT Fit only the supplied training matrix; standardization and constant filter use it alone.
X=double(X);y=double(y(:));
assert(size(X,1)==numel(y) && all(isfinite(X),'all'),'eba:FitInput','Invalid training matrix.');
assert(all(mod(y,1)==0 & y>=1 & y<=numel(cfg.classes)),'eba:FitLabel','Undeclared training class.');
old=rng; restore=onCleanup(@() rng(old));rng(cfg.model_seed,'twister');
mu=mean(X,1);sigma=std(X,0,1);keep=sigma>1e-12;
assert(any(keep),'eba:FitConstant','All training features are constant.');
Z=(X(:,keep)-mu(keep))./sigma(keep); ticId=tic;solver=struct();
switch upper(string(kind))
    case "SVM"
        solver=struct('solver','SMO','iteration_limit',2e6,'delta_gradient_tolerance',1e-3, ...
            'KKT_tolerance',0,'gap_tolerance',0,'shrinkage_period',0);
        learner=templateSVM('KernelFunction',char(hp.kernel),'BoxConstraint',hp.box_constraint, ...
            'KernelScale',hp.kernel_scale,'Standardize',false,'Solver',solver.solver, ...
            'IterationLimit',solver.iteration_limit,'DeltaGradientTolerance',solver.delta_gradient_tolerance);
        fitted=fitcecoc(Z,y,'Learners',learner,'Coding','onevsone','ClassNames',unique(y));
        classes=double(fitted.ClassNames);
    case "RF"
        fitted=TreeBagger(hp.trees,Z,y,'Method','classification','MinLeafSize',hp.min_leaf, ...
            'NumPredictorsToSample',max(1,floor(sqrt(size(Z,2)))),'OOBPrediction','off');
        classes=str2double(string(fitted.ClassNames));
    otherwise
        error('eba:Classifier','Unknown controlled classifier.');
end
training_time_s=toc(ticId);
model=struct('fitted',fitted,'kind',upper(string(kind)),'hyperparameters',hp,'mean',mu, ...
    'scale',sigma,'keep',keep,'classes',classes(:),'seed',cfg.model_seed, ...
    'training_time_s',training_time_s,'solver_configuration',solver,'temperature',1,'calibrated',false,'feature_schema_version',cfg.feature_schema_version);
end
