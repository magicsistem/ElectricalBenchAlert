function saveModel(path,model)
%SAVEMODEL Portable native inference artifact with exact restored-object validation.
% Installation references are serialization metadata, never learned coefficients.
% This HDF5 metadata edit is an engineering proposal, guarded by native roundtrip.
folder=fileparts(path);if ~isfolder(folder),mkdir(folder);end
staged=[tempname(folder) '.mat'];cleanup=onCleanup(@() removeStaged(staged));
save(staged,'model','-v7.3');replaceInstallationReferences(h5info(staged),staged);
lastwarn('');restored=load(staged,'model');[warningText,warningId]=lastwarn;
assert(isempty(warningText),'eba:ModelPortability','Portable native load emitted warning %s.',warningId);
assert(isequaln(model,restored.model),'eba:ModelPortability','Portable native restoration changed model state.');
[ok,message]=movefile(staged,path,'f');assert(ok,'eba:ModelPortability','%s',message);
end

function replaceInstallationReferences(info,path)
for i=1:numel(info.Datasets)
    d=info.Datasets(i);
    if strcmp(d.Name,'matlabroot') && strcmp(d.Datatype.Type,'H5T_STD_U16LE')
        key=replace(string(info.Name)+"/"+d.Name,'//','/');value=h5read(path,key);
        assert(~isempty(value),'eba:ModelPortability','Empty serialized installation reference.');
        neutral=repmat(uint16('m'),size(value));neutral(1)=uint16('/');
        h5write(path,key,neutral);
    end
end
for i=1:numel(info.Groups),replaceInstallationReferences(info.Groups(i),path);end
end

function removeStaged(path)
if isfile(path),delete(path);end
end
