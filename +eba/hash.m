function h = hash(value,kind)
%HASH SHA-256 over file bytes, UTF-8 text, or canonical little-endian numeric bytes.
if nargin<2, kind="text"; end
switch string(kind)
    case "file"
        fid=fopen(value,'rb'); assert(fid>=0,'eba:HashIO','Cannot read hash input.');
        cleanup=onCleanup(@() fclose(fid)); bytes=fread(fid,Inf,'*uint8');
    case "numeric"
        assert(isnumeric(value) && isreal(value),'eba:HashType','Numeric hashes require real arrays.');
        bytes=typecast(value(:),'uint8');
        [~,~,e]=computer;
        if e=='B', bytes=typecast(swapbytes(value(:)),'uint8'); end
    case "text"
        bytes=unicode2native(char(value),'UTF-8');
    otherwise
        error('eba:HashType','Unknown hash input kind.');
end
md=javaMethod('getInstance','java.security.MessageDigest','SHA-256');
md.update(typecast(uint8(bytes(:)),'int8'));
digest=typecast(md.digest(),'uint8');
h=lower(reshape(dec2hex(digest,2).',1,[]));
end
