function model = trainClassifier(F,cfg)
%TRAINCLASSIFIER M6 lightweight classifier using train split only.
featureNames=legacy.featureColumns(F);
train=F(F.split=="train",:);
if isempty(train), error('legacy:NoTrain','No train rows.'); end
X=table2array(train(:,featureNames));
y=categorical(train.label);
if any(~isfinite(X),'all'), error('legacy:NonFiniteFeature','Features contain NaN/Inf.'); end

% Remove constants using train only.
keep=std(X,0,1)>eps;
X=X(:,keep);
featureNames=featureNames(keep);

rng(cfg.seed,'twister');
switch lower(string(cfg.classifier.type))
    case "svm_ecoc"
        learner=templateSVM('KernelFunction','linear','Standardize',cfg.classifier.standardize);
        fitted=fitcecoc(X,y,'Learners',learner,'Coding','onevsone');
    case "tree"
        fitted=fitctree(X,y,'MinLeafSize',5,'Surrogate','off');
    case "lda"
        fitted=fitcdiscr(X,y,'DiscrimType','pseudoLinear');
    otherwise
        error('legacy:Classifier','Unknown classifier type: %s',cfg.classifier.type);
end
model=struct('fitted',fitted,'feature_names',{featureNames}, ...
    'classifier_type',string(cfg.classifier.type),'classes',string(categories(y)), ...
    'seed',cfg.seed);
end
