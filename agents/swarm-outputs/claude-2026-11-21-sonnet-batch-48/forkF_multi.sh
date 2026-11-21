#!/bin/bash
# usage: forkF_multi.sh rounds size frames file1 file2 ...   (interleaved, chain-style C, prints min-of-mins ratio vs file1)
S=/tmp/claude-0/-root-image-video-effects/2b7775f4-9af2-40c8-a5e7-7ac04b08ac66/scratchpad/f
R=$1; SZ=$2; FR=$3; shift 3
cd /root/iv-sonnet-batch-48
for f in "$@"; do : > $S/_m_$(basename $f).txt; done
for r in $(seq 1 $R); do
  for f in "$@"; do
    v=$(SRC=tex CPROC=1 NOFB=1 node $S/mr_perf_f.mjs $f $S/_pf_m.png $SZ $FR 2 ${PARAMS:-0.4,0.3,0.85,0} -1,-1,0 2>&1 | grep PERF | sed 's/.*"min":\([0-9.]*\).*/\1/')
    echo $v >> $S/_m_$(basename $f).txt
  done
done
python3 - "$@" <<PY
import sys,os
S="$S"
base=None
for f in sys.argv[1:]:
    v=[float(x) for x in open(f"{S}/_m_{os.path.basename(f)}.txt") if x.strip()]
    m=min(v); med=sorted(v)[len(v)//2]
    if base is None: base=(m,med)
    print("%-28s min %.1f (x%.3f)  median %.1f (x%.3f)  n=%d"%(os.path.basename(f),m,m/base[0],med,med/base[1],len(v)))
PY
