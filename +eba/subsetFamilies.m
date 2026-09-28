function [S,calibration_ids] = subsetFamilies(F,train_per_cell,validation_per_cell)
%SUBSETFAMILIES Nested deterministic development families, calibration disjoint from fitting.
assert(all(F.split~="test"),'eba:TestFirewall','Subset selection cannot receive final-test rows.');
S=F([],:);calibration_ids=strings(0,1);
classes=unique(F.class_id);cells=unique(F(:,{'class_id','severity_stratum','duration_stratum'}),'rows');
for k=1:height(cells)
    m=F.class_id==cells.class_id(k) & F.severity_stratum==cells.severity_stratum(k) & F.duration_stratum==cells.duration_stratum(k);
    train=sortrows(F(m & F.split=="train",:),'family_id');
    val=sortrows(F(m & F.split=="validation",:),'family_id');
    assert(height(train)>=train_per_cell && height(val)>=validation_per_cell,'eba:SubsetSize','Insufficient independent families in design cell.');
    S=[S;train(1:train_per_cell,:);val(1:validation_per_cell,:)]; %#ok<AGROW>
    if train_per_cell>0,calibration_ids(end+1,1)=train.family_id(train_per_cell);end %#ok<AGROW>
end
assert(isequal(unique(S.class_id),classes),'eba:SubsetClasses','A class disappeared.');
end
