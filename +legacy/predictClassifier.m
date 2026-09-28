function pred = predictClassifier(model,F)
%PREDICTCLASSIFIER Predict labels using stored feature schema.
X=table2array(F(:,model.feature_names));
yhat=predict(model.fitted,X);
pred=string(yhat);
end
