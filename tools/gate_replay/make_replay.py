#!/usr/bin/env python3
"""make_replay.py -- gate-level replay of a Gowin netlist against its RTL.

Given the RTL of a module and its Gowin netlist (impl/gwsynthesis/*.vg from a
standalone synthesis of that module), generate:

  <out>/gate.v  the netlist with every module renamed <name>_g (the netlist
                reuses the RTL module names, so both can't coexist otherwise)
  <out>/tb.v    a testbench that reads recorded inputs (one hex line per
                clock, ports in declaration order, clock(s) excluded), drives
                the RTL and the netlist in lockstep, and reports every output
                port that differs, ignoring bits that are X in the RTL

and print the $fwrite line to paste into your system simulation to produce
the recording.

    make_replay.py --top my_block --rtl my_block.v [more.v ...] \
                   --netlist proj/impl/gwsynthesis/proj.vg --out replay/

Then:
    iverilog -g2012 -s tb -o replay/sim replay/tb.v <rtl files> replay/gate.v \
        $GOWIN/IDE/simlib/gw5a/prim_sim.v
    vvp -n replay/sim +rec=inputs.hex [+max=N] [+stop=N]

Notes (see docs/05):
  * The testbench instantiates GSR (Gowin primitives reference GSR.GSRO) and
    must be elaborated with -s tb.
  * RTL memories start at X in iverilog but at 0 on the board: X bits in the
    RTL outputs are ignored.  If internal X's still skew the RTL, zero its
    memories in an initial block.
  * Pipeline stages hold junk while invalid; compare what matters or add
    valid gating.
MIT license -- see the repository LICENSE.
"""
import argparse, os, re, sys


def parse_ports(src, top):
    m = re.search(r'\bmodule\s+%s\b' % re.escape(top), src)
    if not m:
        sys.exit(f'module {top} not found')
    body = src[m.end():]
    # parameters (#( ... )) are skipped; the port list ends at the first ');'
    hdr = body[:body.index(');')]
    hdr = re.sub(r'//[^\n]*', '', hdr)
    ports = []
    for d, w, n in re.findall(
            r'\b(input|output|inout)\s+(?:wire|reg)?\s*(?:signed\s+)?(\[[^\]]+\])?\s*(\w+)', hdr):
        width = 1
        if w:
            hi, lo = w[1:-1].split(':')
            width = abs(int(eval(hi)) - int(eval(lo))) + 1
        ports.append((d, width, n))
    if not ports:
        sys.exit('no ANSI-style ports found (non-ANSI headers are not supported)')
    return ports


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--top', required=True)
    ap.add_argument('--rtl', nargs='+', required=True)
    ap.add_argument('--netlist', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--clock', action='append', default=None,
                    help='clock input(s); default: clk')
    a = ap.parse_args()
    clocks = a.clock or ['clk']
    os.makedirs(a.out, exist_ok=True)

    src = '\n'.join(open(f).read() for f in a.rtl)
    ports = parse_ports(src, a.top)
    ins = [p for p in ports if p[0] == 'input' and p[2] not in clocks]
    outs = [p for p in ports if p[0] == 'output']
    clk_ports = [p for p in ports if p[2] in clocks]

    # --- rename netlist modules ---
    net = open(a.netlist).read()
    mods = set(re.findall(r'^module\s+(\w+)', net, flags=re.M))
    net = re.sub(r'^module\s+(\w+)', lambda m: f'module {m.group(1)}_g', net, flags=re.M)
    net = re.sub(r'^(\s+)(\w+)(\s+\S+\s*\()',
                 lambda m: m.group(1) + (m.group(2) + '_g' if m.group(2) in mods else m.group(2)) + m.group(3),
                 net, flags=re.M)
    open(os.path.join(a.out, 'gate.v'), 'w').write(net)

    W = lambda w: f'[{w - 1}:0] ' if w > 1 else ''
    tot = sum(p[1] for p in ins)
    L = ['`timescale 1ns/1ps', 'module tb;', '    reg clk = 0;']
    L += [f'    reg {W(w)}{n} = 0;' for d, w, n in ins]
    L += [f'    wire {W(w)}{n}_r, {n}_g;' for d, w, n in outs]
    conn = lambda sfx: ', '.join([f'.{n}(clk)' for d, w, n in clk_ports] +
                                 [f'.{n}({n})' for d, w, n in ins] +
                                 [f'.{n}({n}{sfx})' for d, w, n in outs])
    L += [f'    {a.top} r ({conn("_r")});', f'    {a.top}_g g ({conn("_g")});',
          '    GSR GSR (.GSRI(1\'b1));',
          f'    reg [{tot - 1}:0] v;',
          '    integer fd, rc, cyc = 0, nbad = 0, maxc, stopn, b, d;',
          '    reg [8*256-1:0] rec;',
          '    initial begin',
          '        if (!$value$plusargs("rec=%s", rec)) rec = "inputs.hex";',
          '        if (!$value$plusargs("max=%d", maxc)) maxc = 32\'h7fffffff;',
          '        if (!$value$plusargs("stop=%d", stopn)) stopn = 10;',
          '        fd = $fopen(rec, "r");',
          '        if (fd == 0) begin $display("cannot open %0s", rec); $finish; end',
          '        while (!$feof(fd) && cyc < maxc) begin',
          '            rc = $fscanf(fd, "%h\\n", v);',
          '            {' + ', '.join(n for d, w, n in ins) + '} = v;',
          '            #1 clk = 1; #4; cyc = cyc + 1; d = 0;']
    for dd, w, n in outs:
        L.append(f'            for (b = 0; b < {w}; b = b + 1) if ({n}_r[b] !== 1\'bx && {n}_r[b] !== {n}_g[b]) begin')
        L.append(f'                if (d == 0) $display("DIVERGE cycle %0d:", cyc);')
        L.append(f'                $display("   {n}: rtl=%h gate=%h", {n}_r, {n}_g); d = 1; b = {w}; end')
    L += ['            if (d) begin nbad = nbad + 1; if (nbad >= stopn) begin $display("stopping after %0d diverging cycles", nbad); $finish; end end',
          '            #5 clk = 0;',
          '        end',
          '        $display("END cycles=%0d diverging_cycles=%0d", cyc, nbad);',
          '        $finish;',
          '    end',
          'endmodule']
    open(os.path.join(a.out, 'tb.v'), 'w').write('\n'.join(L) + '\n')

    print(f'wrote {a.out}/gate.v ({len(mods)} modules renamed) and {a.out}/tb.v')
    print(f'{len(ins)} recorded inputs, {tot} bits per line; {len(outs)} outputs compared')
    print('\nRecorder to paste next to the module instance in your simulation:')
    print('    integer rec_fd;')
    print('    initial rec_fd = $fopen("inputs.hex", "w");')
    print(f'    always @(posedge {clocks[0]}) $fwrite(rec_fd, "%h\\n", {{' +
          ', '.join(n for d, w, n in ins) + '});')


if __name__ == '__main__':
    main()
