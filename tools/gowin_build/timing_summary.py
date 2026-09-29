#!/usr/bin/env python3
"""timing_summary.py <proj>/impl/pnr/<name>_tr_content.html

Print Fmax per clock and the total negative slack (TNS) / failing endpoint
count for setup and hold, from Gowin's HTML timing report.
"""
import html, re, sys

t = html.unescape(re.sub(r'<[^>]+>', ' ', open(sys.argv[1]).read()))
t = re.sub(r'\s+', ' ', t)
i = t.find('Max Frequency Summary')
for clk, con, fmax in re.findall(r'\d+ (\S+) ([\d.]+\(MHz\)) ([\d.]+\(MHz\))', t[i:i + 2000]):
    print(f'{clk:24s} constraint {con:14s} achieved {fmax}')
i = t.find('Total Negative Slack Summary')
for clk, kind, tns, n in re.findall(r'(\S+) (Setup|Hold) (-?[\d.]+) (\d+)', t[i:i + 1500]):
    flag = '' if float(tns) == 0 else '   <-- FAILING'
    print(f'{clk:24s} {kind:5s} TNS {tns:>9s}  endpoints {n}{flag}')
