function id=recordId(family_id,snr_db,realization_id)
%RECORDID Canonical identity shared by metadata, generated signals and predictions.
f=string(family_id);
assert(isscalar(f) && ~ismissing(f) && strlength(strtrim(f))>0,'eba:RecordIdentity','A nonempty family identity is required.');
assert(isnumeric(snr_db) && isreal(snr_db) && isscalar(snr_db) && (isfinite(snr_db) || snr_db==Inf), ...
    'eba:RecordIdentity','SNR must be finite or positive infinity.');
assert(isnumeric(realization_id) && isreal(realization_id) && isscalar(realization_id) && isfinite(realization_id) && realization_id==fix(realization_id), ...
    'eba:RecordIdentity','Realization must be an integer.');
if snr_db==Inf
    assert(realization_id==0,'eba:RecordIdentity','A clean record has realization zero.');id=f+"_clean";
else
    assert(realization_id>=1 && snr_db==fix(snr_db),'eba:RecordIdentity','Declared noisy records use integer dB and positive realizations.');
    id=f+string(sprintf('_snr%+03d_r%d',snr_db,realization_id));
end
end
