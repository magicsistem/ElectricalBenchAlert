function json(path,value)
%JSON Write a UTF-8 JSON artifact through a temporary file in the target directory.
folder=fileparts(path); if ~isfolder(folder),mkdir(folder);end
tmp=[tempname(folder) '.json']; fid=fopen(tmp,'w','n','UTF-8');
assert(fid>=0,'eba:JsonIO','Cannot open output.');
cleanup=onCleanup(@() fclose(fid)); fprintf(fid,'%s\n',jsonencode(value,'PrettyPrint',true));
clear cleanup;
[ok,msg]=movefile(tmp,path,'f'); assert(ok,'eba:JsonIO','%s',msg);
end
