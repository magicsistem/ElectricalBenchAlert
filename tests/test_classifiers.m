function test_classifiers()
cfg=eba.config();cfg.classes=["a";"b"];cfg.model_seed=11;
X=[-3 -3;-2 -2;-1 -1;1 1;2 2;3 3];y=[1;1;1;2;2;2];
hp=struct('kernel','linear','box_constraint',1,'kernel_scale',1);
m=eba.fit(X,y,cfg,'SVM',hp);p=eba.predict(m,X);assert(isequal(p,y));
assert(isequal(m.mean,mean(X,1)));m2=eba.fit(X,y,cfg,'SVM',hp);assert(isequal(eba.predict(m2,X),p));
m=eba.calibrate(m,[-4 -4;4 4],[1;2],["cal_a";"cal_b"]);[p,c,q]=eba.predict(m,X);
assert(all(c>=0 & c<=1));assert(all(abs(sum(q,2)-1)<1e-12));assert(isequal(p,y));
hp=struct('trees',20,'min_leaf',1);m=eba.fit(X,y,cfg,'RF',hp);assert(isequal(eba.predict(m,X),y));
bad=false;try,eba.predict(m,NaN(1,2));catch,bad=true;end;assert(bad);
bad=false;try,eba.requireFrozen(cfg);catch,bad=true;end;assert(bad,'Test must remain sealed during development.');
fprintf('CLASSIFIER_TESTS_PASS\n');
end
