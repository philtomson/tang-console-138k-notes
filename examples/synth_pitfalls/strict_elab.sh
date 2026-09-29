#!/bin/bash
# strict_elab.sh <top> <files...> -- elaborate with iverilog as a strict check.
#
# Verilator (and, with warnings, Gowin) accept signals used before their
# declaration; strict Verilog makes them implicit 1-bit nets (docs/04,
# pitfall 3).  iverilog refuses such designs, which makes it a cheap linter.
# Vendor IP you don't have as source can be replaced by empty stub modules.
# MIT license -- see the repository LICENSE.
top=${1:?usage: $0 <top> <files...>}; shift
iverilog -g2012 -o /dev/null -s "$top" "$@" 2>&1 | grep -iE "error|Unable to bind|declared here" \
  && { echo "FAIL: see above"; exit 1; } || echo "OK: $top elaborates strictly"
