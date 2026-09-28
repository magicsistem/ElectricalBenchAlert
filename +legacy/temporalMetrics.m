function out = temporalMetrics(F)
%TEMPORALMETRICS M8 onset/offset metrics where ground truth is finite.
valid=isfinite(F.event_start_s) & isfinite(F.event_end_s);
T=F(valid,:);
T.start_error_s=T.detected_start_s-T.event_start_s;
T.end_error_s=T.detected_end_s-T.event_end_s;
T.detection_latency_s=T.start_error_s;
T.abs_start_error_s=abs(T.start_error_s);
T.abs_end_error_s=abs(T.end_error_s);
detected=isfinite(T.detected_start_s) & isfinite(T.detected_end_s);
out=struct();
out.n_applicable=height(T);
out.n_detected=sum(detected);
out.detection_rate=sum(detected)/max(height(T),1);
if any(detected)
    out.mean_latency_s=mean(T.detection_latency_s(detected));
    out.median_latency_s=median(T.detection_latency_s(detected));
    out.mae_start_s=mean(T.abs_start_error_s(detected));
    out.mae_end_s=mean(T.abs_end_error_s(detected));
    out.p95_abs_start_s=prctile(T.abs_start_error_s(detected),95);
    out.p95_abs_end_s=prctile(T.abs_end_error_s(detected),95);
else
    out.mean_latency_s=NaN; out.median_latency_s=NaN;
    out.mae_start_s=NaN; out.mae_end_s=NaN;
    out.p95_abs_start_s=NaN; out.p95_abs_end_s=NaN;
end
out.rows=T;
end
