function [grade,physical]=severity(x,class_name,Fs)
%SEVERITY Window measurement for amplitude classes; other physical grades remain unknown.
class_name=string(class_name);x=double(x(:));period=round(Fs/60);
assert(numel(x)>=period && all(isfinite(x)),'eba:SeverityInput','At least one nominal cycle is required.');
envelope=sqrt(movmean(x.^2,period,Endpoints='discard'));
low=quantile(envelope,.1);high=quantile(envelope,.9);grade="unknown";
physical=struct('voltage_rms_pu_min',low,'voltage_rms_pu_max',high,'scope','arrived-window one-cycle RMS quantiles; not regulatory aggregation');
if any(class_name==["voltage_sag","voltage_sag_harmonics"])
    grade="low";if low<.65,grade="medium";end;if low<.35,grade="high";end
elseif any(class_name==["voltage_swell","voltage_swell_harmonics"])
    grade="low";if high>1.33,grade="medium";end;if high>1.56,grade="high";end
elseif class_name=="interruption"
    grade="low";if low<.066,grade="medium";end;if low<.033,grade="high";end
end
end
