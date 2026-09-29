function test_classifiers()
cfg=eba.config();cfg.classes=["a";"b"];cfg.model_seed=11;
X=[-3 -3;-2 -2;-1 -1;1 1;2 2;3 3];y=[1;1;1;2;2;2];
hp=struct('kernel','linear','box_constraint',1,'kernel_scale',1);
m=eba.fit(X,y,cfg,'SVM',hp);p=eba.predict(m,X);assert(isequal(p,y));
assert(strcmp(m.solver_configuration.solver,'SMO') && m.solver_configuration.iteration_limit==2e6 && ...
    m.solver_configuration.delta_gradient_tolerance==1e-3,'Controlled solver budget or tolerance changed.');
assert(isequal(m.mean,mean(X,1)));m2=eba.fit(X,y,cfg,'SVM',hp);assert(isequal(eba.predict(m2,X),p));
m=eba.calibrate(m,[-4 -4;4 4],[1;2],["cal_a";"cal_b"]);[p,c,q]=eba.predict(m,X);
assert(all(c>=0 & c<=1));assert(all(abs(sum(q,2)-1)<1e-12));assert(isequal(p,y));portableRoundtrip(m,X);
hp=struct('trees',20,'min_leaf',1);m=eba.fit(X,y,cfg,'RF',hp);assert(isequal(eba.predict(m,X),y));portableRoundtrip(m,X);
bad=false;try,eba.predict(m,NaN(1,2));catch,bad=true;end;assert(bad);
bad=false;try,eba.requireFrozen(cfg);catch,bad=true;end;assert(bad,'Test must remain sealed during development.');
% Shared selection keeps the classifier fixed even when individual optima differ.
grid=string({jsonencode(struct('kernel','linear','box_constraint',1));jsonencode(struct('kernel','linear','box_constraint',10))});
a=table(grid,[.8;.7],'VariableNames',{'hyperparameters_json','validation_macro_f1'});
b=a;b.validation_macro_f1=[.4;.9];[shared,review]=eba.sharedHyperparameters({a,b},["FFT","STFT"]);
assert(shared.box_constraint==10 && isequal(review.selected,[false;true]));
b.validation_macro_f1=[.6;.7];[shared,review]=eba.sharedHyperparameters({a,b},["FFT";"STFT"]);
assert(shared.box_constraint==1 && isequal(review.selected,[true;false]));
bad=b;bad.hyperparameters_json=flipud(grid);rejects(@() eba.sharedHyperparameters({a,bad},["FFT","STFT"]));
bad=b;bad.validation_macro_f1(1)=NaN;rejects(@() eba.sharedHyperparameters({a,bad},["FFT","STFT"]));
fprintf('CLASSIFIER_TESTS_PASS\n');
end

function rejects(f)
failed=false;try,f();catch err,failed=strcmp(err.identifier,'eba:SharedClassifier');end
assert(failed,'Shared-classifier rejection control failed.');
end

function portableRoundtrip(model,X)
model.fitted=compact(model.fitted);path=[tempname '.mat'];cleanup=onCleanup(@() delete(path));
eba.saveModel(path,model);loaded=load(path,'model');
[p,c,q,s]=eba.predict(model,X);[p2,c2,q2,s2]=eba.predict(loaded.model,X);
assert(isequal(p,p2) && isequal(c,c2) && isequal(q,q2) && isequal(s,s2),'Native portable model changed inference.');
end
