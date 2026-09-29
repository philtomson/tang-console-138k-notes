#!/bin/bash
# check_ram_mapping.sh <netlist.vg> -- which arrays became RAM primitives?
#
# Gowin's log says "Extracting RAM for identifier 'x'" for candidates, but only
# the netlist tells you what an array really became.  An array written more than
# once per clock is only safe as REGISTERS; if it shows up here as RAM16S*/
# RAM16SDP* (distributed RAM, one write port) or SDPB/DPB (block RAM), one of
# the writes can be silently dropped (docs/04, pitfall 1).
# MIT license -- see the repository LICENSE.
vg=${1:?usage: $0 impl/gwsynthesis/<name>.vg}
grep -oE '^\s*(RAM16SDP[124]|RAM16S[124]|SDPB|SDPX9B|DPB|DPX9B|SP|SPX9|pROM|pROMX9)\s+\S+' "$vg" |
python3 -c '
import sys, re, collections
c = collections.Counter()
for line in sys.stdin:
    prim, inst = line.split()[:2]
    inst = inst.lstrip("\\")
    inst = re.sub(r"(_s\d*)+$", "", inst)
    # Gowin names RAM slices "<array>_<array>_<n>": keep the shortest prefix
    # that repeats, else strip trailing _<n> groups
    parts = inst.split("_")
    name = None
    for k in range(1, len(parts)):
        if parts[k:2 * k] == parts[:k]:
            name = "_".join(parts[:k]); break
    if name is None:
        name = re.sub(r"(_\d+)+$", "", inst)
    c[(name, prim)] += 1
for (name, prim), n in sorted(c.items()):
    print(f"{name:40s} {prim:9s} x{n}")
'
