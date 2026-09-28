function writeJson(path, value)
%WRITEJSON Write pretty JSON using built-in jsonencode.
folder = fileparts(path);
if ~isempty(folder) && ~isfolder(folder), mkdir(folder); end
txt = jsonencode(value,'PrettyPrint',true);
fid = fopen(path,'w');
if fid < 0, error('legacy:IO','Cannot open %s for writing.',path); end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid,txt,'char');
end
