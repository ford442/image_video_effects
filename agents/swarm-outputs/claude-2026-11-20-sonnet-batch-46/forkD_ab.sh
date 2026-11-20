#!/bin/bash
# usage: forkD_ab.sh <perf-script> <head.wgsl> <new.wgsl> <rounds> -- <args after wgsl/out...>  (env passes through)
# interleaves HEAD/new, prints per-round min-of-drained-frames ratio and the median ratio
PERFJS=$1; HEADW=$2; NEWW=$3; R=$4; shift 5
OUT=/tmp/claude-0/-root-image-video-effects/bd0d6c66-96e3-4dcc-84fd-ec19638d2915/scratchpad/forkD/ab.png
ratios=()
for i in $(seq 1 $R); do
  h=$(node $PERFJS $HEADW $OUT "$@" | grep -o '"min":[0-9.]*' | head -1 | cut -d: -f2)
  n=$(node $PERFJS $NEWW $OUT "$@" | grep -o '"min":[0-9.]*' | head -1 | cut -d: -f2)
  r=$(python3 -c "print(round($n/$h,3))"); echo "round $i head=$h new=$n ratio=$r"; ratios+=($r)
done
python3 -c "import statistics,sys; v=[float(x) for x in sys.argv[1:]]; print('MEDIAN ratio', round(statistics.median(v),3), 'min', min(v), 'max', max(v))" "${ratios[@]}"
