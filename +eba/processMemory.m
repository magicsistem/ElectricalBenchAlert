function r=processMemory()
%PROCESSMEMORY Actual MATLAB process resident/high-water bytes on Linux.
r=struct('rss_bytes',NaN,'hwm_bytes',NaN,'source','unavailable');
if ~isfile('/proc/self/status'),return;end
s=fileread('/proc/self/status');
rss=regexp(s,'(?m)^VmRSS:\s+(\d+)\s+kB','tokens','once');hwm=regexp(s,'(?m)^VmHWM:\s+(\d+)\s+kB','tokens','once');
if ~isempty(rss),r.rss_bytes=1024*str2double(rss{1});end
if ~isempty(hwm),r.hwm_bytes=1024*str2double(hwm{1});end
r.source='/proc/self/status; entire MATLAB process including startup and model load';
end
