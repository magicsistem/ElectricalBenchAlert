function isPareto = paretoFront(X,direction)
%PARETOFRONT Non-dominated rows. direction=1 maximize, -1 minimize.
X=double(X); direction=double(direction(:).');
if size(X,2)~=numel(direction), error('legacy:ParetoShape','Direction mismatch.'); end
Z=X;
for j=1:numel(direction)
    if direction(j)==1, Z(:,j)=-Z(:,j); end
end
n=size(Z,1); isPareto=true(n,1);
for i=1:n
    if any(~isfinite(Z(i,:))), isPareto(i)=false; continue; end
    for j=1:n
        if i==j || any(~isfinite(Z(j,:))), continue; end
        if all(Z(j,:)<=Z(i,:)) && any(Z(j,:)<Z(i,:))
            isPareto(i)=false; break;
        end
    end
end
end
