#!/bin/bash
# usage: forkC_perf.sh <head.wgsl> <new.wgsl> [rounds] [p1,p2,p3,p4] [size] [frames]
# Interleaves HEAD/new, prints per-round min ms (min-of-drained-frames) and the median ratio.
H=$1; N=$2; R=${3:-5}; P=${4:-0.4,0.3,0.5,0.3}; SZ=${5:-192}; FR=${6:-24}
cd /root/iv-sonnet-batch-47
for r in $(seq 1 $R); do
  h=$(SRC=img node agents/mr_perf.mjs $H /tmp/_pf_h.png $SZ $FR 2 $P 2>&1 | grep PERF | sed 's/.*"min":\([0-9.]*\).*/\1/')
  n=$(SRC=img node agents/mr_perf.mjs $N /tmp/_pf_n.png $SZ $FR 2 $P 2>&1 | grep PERF | sed 's/.*"min":\([0-9.]*\).*/\1/')
  echo "round $r head=$h new=$n ratio=$(python3 -c "print(round($n/$h,3))")"
done | tee /tmp/_pf_rounds.txt
python3 - <<'PY'
import re,statistics
r=[float(re.search(r'ratio=([\d.]+)',l).group(1)) for l in open('/tmp/_pf_rounds.txt')]
print("median ratio", statistics.median(r))
PY
