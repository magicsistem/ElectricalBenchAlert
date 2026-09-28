function test_metrics()
y=["a";"a";"b";"b"]; p=["a";"b";"b";"b"];
r=legacy.classificationMetrics(y,p,["a";"b"]);
assert(abs(r.accuracy-0.75)<1e-12); assert(r.macro_f1>0 && r.macro_f1<=1);
X=[0.9 0.1;0.8 0.2;0.95 0.3]; q=legacy.paretoFront(X,[1 -1]); assert(any(q));
end
