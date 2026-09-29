// ddr3_selftest.v -- DDR3 bring-up and self-test for the Sipeed Tang Console
// 138K (GW5AST-138C, x32 DDR3) with the Gowin DDR3 Memory Interface IP.
//
// What it does, after power-up:
//   1. waits for init_calib_complete (latched: it can toggle during init),
//   2. waits DELAY more controller cycles (default 0).  One of our designs
//      needed ~20-40 ms here to avoid silently lost writes; this minimal
//      test never has (docs/03 section 4).  PACE spreads the writes over
//      time to map any loss window,
//   3. writes N_WORDS 256-bit words with an address-derived pattern, issuing
//      each write as a ONE-CYCLE cmd_en + wr_data_en when cmd_ready and
//      wr_data_rdy are both high,
//   4. reads every word back, one read in flight at a time, and compares,
//   5. reports over the UART (115200 8N1, repeating every ~0.7 s):
//        DDR3 N=0800 ERR=0000 FIRST=0000 LAST=0000 TW0=00400002 TW1=0040094A
//      with values in hex.  ERR = mismatching words, FIRST/LAST = first/last
//      bad word, TW0/TW1 = controller (100 MHz) cycles from calibration to
//      the first/last write,
//   6. shows a status code on a PMOD-DTx2 in PMOD1 (optional):
//        C0 waiting for calibration   C1 post-calibration wait
//        A1 writing   A2 reading      d0 PASS   E1 FAIL (errors)
//      and on the LED: blinking = running, steady on = PASS, fast = FAIL.
//
// Clocking and reset follow the settings verified on the board (docs/03):
// the memory-clock enable follows the IP's pll_stop, the PLL is never reset,
// and the controller reset is released after pll_lock.
//
// Needs the Gowin-generated IP (NOT included; see README): Gowin_PLL with
// clkout2 = memory clock (400 MHz) and DDR3_Memory_Interface_Top, both as
// in Sipeed's Tang Mega 138K ddr_memory example.
//
// MIT license -- see the repository LICENSE.
`timescale 1ns / 1ps

module ddr3_selftest #(
    parameter [15:0] N_WORDS  = 16'd2048,        // 256-bit words to test (64 KiB)
    parameter [31:0] DELAY    = 32'd0,           // extra controller cycles after calib before writing
    parameter [31:0] PACE     = 32'd0,           // extra cycles between writes (0 = back to back);
                                                 // with PACE>0, bad word n was written ~n*PACE
                                                 // cycles after the first write -> maps the loss window
    parameter        UART_DIV = 434              // 50 MHz / 115200 - 1
) (
    input  wire        clk,          // 50 MHz, V22
    input  wire        uart_rx,      // V14 (unused)
    output wire        uart_tx,      // U15
    output wire        led_V13,      // V13, lit when high
    input  wire        key1_F4,      // F4 (unused)
    output wire [6:0]  pmod_seg,     // optional PMOD-DTx2 in PMOD1
    output wire        pmod_sel,
    // DDR3 (Sipeed ddr3_1v4_hs.cst names)
    output wire [14:0] ddr_addr,
    output wire [2:0]  ddr_bank,
    output wire        ddr_cs,
    output wire        ddr_ras,
    output wire        ddr_cas,
    output wire        ddr_we,
    output wire        ddr_ck,
    output wire        ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_reset_n,
    output wire [3:0]  ddr_dm,
    inout  wire [31:0] ddr_dq,
    inout  wire [3:0]  ddr_dqs,
    inout  wire [3:0]  ddr_dqs_n
);
    // ---------------------------------------------------------------
    // Clocks and resets
    // ---------------------------------------------------------------
    wire pll_lock, pll_stop, memory_clk;
    wire clk_x1;                     // 100 MHz user clock from the IP
    reg  [7:0] rst_shift = 8'd0;     // controller reset: 8 clk after pll_lock
    always @(posedge clk or negedge pll_lock)
        if (!pll_lock) rst_shift <= 8'd0;
        else           rst_shift <= {rst_shift[6:0], 1'b1};
    wire ctl_rst_n = rst_shift[7];

    // Memory-clock enable FOLLOWS pll_stop (holding it at 1 made calibration
    // drop repeatedly); the OR keeps the clock running while in reset.
    wire mem_clk_en = !ctl_rst_n || pll_stop;

    Gowin_PLL Gowin_PLL_inst (
        .lock(pll_lock), .clkout0(), .clkout1(), .clkout2(memory_clk),
        .clkin(clk), .init_clk(clk), .reset(1'b0),      // never reset the PLL
        .enclk0(1'b1), .enclk1(1'b1), .enclk2(mem_clk_en)
    );

    // user-domain reset
    reg [2:0] urst = 3'd0;
    always @(posedge clk_x1 or negedge ctl_rst_n)
        if (!ctl_rst_n) urst <= 3'd0;
        else            urst <= {urst[1:0], 1'b1};
    wire urst_n = urst[2];

    // ---------------------------------------------------------------
    // DDR3 controller
    // ---------------------------------------------------------------
    wire         calib_raw, cmd_ready, wr_data_rdy, rd_data_valid;
    wire [255:0] rd_data;
    reg          cmd_en_r;               // read command (held)
    wire         wr_go;                  // one-cycle write (cmd + data)
    reg  [2:0]   cmd_r;
    reg  [28:0]  addr_r;
    reg  [255:0] wdata_r;

    DDR3_Memory_Interface_Top u_ddr3 (
        .memory_clk(memory_clk), .pll_stop(pll_stop), .clk(clk),
        .rst_n(ctl_rst_n), .clk_out(clk_x1), .pll_lock(pll_lock),
        .ddr_rst(), .init_calib_complete(calib_raw),
        .cmd_ready(cmd_ready), .cmd(wr_go ? 3'b000 : cmd_r),
        .cmd_en(cmd_en_r || wr_go), .addr(addr_r),
        .wr_data_rdy(wr_data_rdy), .wr_data(wdata_r), .wr_data_en(wr_go),
        .wr_data_end(1'b1), .wr_data_mask(32'd0),
        .rd_data(rd_data), .rd_data_valid(rd_data_valid), .rd_data_end(),
        .sr_req(1'b0), .ref_req(1'b0), .sr_ack(), .ref_ack(), .burst(1'b0),
        .O_ddr_addr(ddr_addr), .O_ddr_ba(ddr_bank), .O_ddr_cs_n(ddr_cs),
        .O_ddr_ras_n(ddr_ras), .O_ddr_cas_n(ddr_cas), .O_ddr_we_n(ddr_we),
        .O_ddr_clk(ddr_ck), .O_ddr_clk_n(ddr_ck_n), .O_ddr_cke(ddr_cke),
        .O_ddr_odt(ddr_odt), .O_ddr_reset_n(ddr_reset_n), .O_ddr_dqm(ddr_dm),
        .IO_ddr_dq(ddr_dq), .IO_ddr_dqs(ddr_dqs), .IO_ddr_dqs_n(ddr_dqs_n)
    );

    // ---------------------------------------------------------------
    // Test pattern: address-only, every bit varies with word and lane
    // ---------------------------------------------------------------
    function [255:0] pat;
        input [15:0] a;
        integer ln;
        reg [31:0] x;
        begin
            for (ln = 0; ln < 8; ln = ln + 1) begin
                x = {a[10:0], ln[2:0], ~a[7:0], a[15:11], 5'b10110}
                    ^ (32'h9E3779B9 >> ln) ^ {a[4:0], 27'd0};
                pat[32*ln +: 32] = x;
            end
        end
    endfunction

    // ---------------------------------------------------------------
    // Self-test FSM (clk_x1 domain)
    // ---------------------------------------------------------------
    localparam S_CAL = 3'd0, S_WAIT = 3'd1, S_WR = 3'd2, S_RDCMD = 3'd3,
               S_RDDAT = 3'd4, S_DONE = 3'd5;
    reg  [2:0]  st;
    reg         calib_seen;
    reg  [31:0] wait_cnt, cal_t, pace_cnt;
    reg  [15:0] n;
    reg  [15:0] err, first_bad, last_bad;
    reg  [31:0] tw0, tw1;
    reg         done, pass;

    // the write fires in the same cycle both readys are seen high
    assign wr_go = (st == S_WR) && (pace_cnt == 32'd0) && cmd_ready && wr_data_rdy;

    always @(posedge clk_x1 or negedge urst_n) begin
        if (!urst_n) begin
            st <= S_CAL; calib_seen <= 1'b0; wait_cnt <= 32'd0; cal_t <= 32'd0; pace_cnt <= 32'd0;
            n <= 16'd0; err <= 16'd0; first_bad <= 16'd0; last_bad <= 16'd0;
            tw0 <= 32'd0; tw1 <= 32'd0; done <= 1'b0; pass <= 1'b0;
            cmd_en_r <= 1'b0; cmd_r <= 3'b001; addr_r <= 29'd0; wdata_r <= 256'd0;
        end else begin
            if (calib_raw) calib_seen <= 1'b1;
            if (calib_seen && ~&cal_t) cal_t <= cal_t + 32'd1;
            case (st)
            S_CAL: if (calib_seen) st <= S_WAIT;
            S_WAIT: begin
                if (wait_cnt >= DELAY) begin
                    st <= S_WR; n <= 16'd0;
                    addr_r <= 29'd0; wdata_r <= pat(16'd0);
                end else wait_cnt <= wait_cnt + 32'd1;
            end
            S_WR: if (pace_cnt != 32'd0) pace_cnt <= pace_cnt - 32'd1;
            else if (wr_go) begin
                pace_cnt <= PACE;
                if (n == 16'd0) tw0 <= cal_t;
                tw1 <= cal_t;
                if (n == N_WORDS - 16'd1) begin
                    st <= S_RDCMD; n <= 16'd0;
                    addr_r <= 29'd0; cmd_r <= 3'b001; cmd_en_r <= 1'b1;
                end else begin
                    n <= n + 16'd1;
                    addr_r <= {10'd0, n + 16'd1, 3'b000};   // word n+1 = column (n+1)*8
                    wdata_r <= pat(n + 16'd1);
                end
            end
            S_RDCMD: if (cmd_ready) begin     // read command held until accepted
                cmd_en_r <= 1'b0;
                st <= S_RDDAT;
            end
            S_RDDAT: if (rd_data_valid) begin
                if (rd_data != pat(n)) begin
                    err <= err + 16'd1;
                    if (err == 16'd0) first_bad <= n;
                    last_bad <= n;
                end
                if (n == N_WORDS - 16'd1) begin
                    st <= S_DONE;
                end else begin
                    n <= n + 16'd1;
                    addr_r <= {10'd0, n + 16'd1, 3'b000};
                    cmd_en_r <= 1'b1;
                    st <= S_RDCMD;
                end
            end
            S_DONE: begin
                done <= 1'b1;
                pass <= (err == 16'd0);
            end
            default: st <= S_CAL;
            endcase
        end
    end

    // ---------------------------------------------------------------
    // Status into the 50 MHz domain (results are static once done)
    // ---------------------------------------------------------------
    reg [2:0] st_s0, st_s1;
    reg       done_s0, done_s1, pass_s0, pass_s1;
    always @(posedge clk) begin
        st_s0 <= st;     st_s1 <= st_s0;
        done_s0 <= done; done_s1 <= done_s0;
        pass_s0 <= pass; pass_s1 <= pass_s0;
    end

    // PMOD-DTx2 status code (see header)
    wire [7:0] code = done_s1 ? (pass_s1 ? 8'hD0 : 8'hE1)
                    : (st_s1 == S_CAL)  ? 8'hC0
                    : (st_s1 == S_WAIT) ? 8'hC1
                    : (st_s1 == S_WR)   ? 8'hA1 : 8'hA2;
    pmod_dtx2 u_disp (.clk(clk), .value(code), .seg(pmod_seg), .sel(pmod_sel));

    // LED: slow blink while running, steady when passed, fast blink on fail
    reg [25:0] blink = 26'd0;
    always @(posedge clk) blink <= blink + 1'b1;
    assign led_V13 = done_s1 ? (pass_s1 ? 1'b1 : blink[21]) : blink[24];

    // ---------------------------------------------------------------
    // UART report: a fixed ASCII line with hex fields, repeated
    //   "DDR3 N=hhhh ERR=hhhh FIRST=hhhh LAST=hhhh TW0=hhhhhhhh TW1=hhhhhhhh\r\n"
    // (before the test finishes the fields show their current values)
    // ---------------------------------------------------------------
    localparam MSG_LEN = 70;
    reg  [6:0]  ci = 7'd0;               // character index
    reg  [7:0]  ch;
    function [7:0] hx;                   // nibble -> ASCII hex
        input [3:0] v;
        hx = (v < 4'd10) ? (8'h30 + v) : (8'h37 + v);
    endfunction
    always @(*) begin
        case (ci)
            0: ch = "D";  1: ch = "D";  2: ch = "R";  3: ch = "3";  4: ch = " ";
            5: ch = "N";  6: ch = "=";
            7: ch = hx(N_WORDS[15:12]); 8: ch = hx(N_WORDS[11:8]);
            9: ch = hx(N_WORDS[7:4]);  10: ch = hx(N_WORDS[3:0]);
            11: ch = " "; 12: ch = "E"; 13: ch = "R"; 14: ch = "R"; 15: ch = "=";
            16: ch = hx(err[15:12]); 17: ch = hx(err[11:8]); 18: ch = hx(err[7:4]); 19: ch = hx(err[3:0]);
            20: ch = " "; 21: ch = "F"; 22: ch = "I"; 23: ch = "R"; 24: ch = "S"; 25: ch = "T"; 26: ch = "=";
            27: ch = hx(first_bad[15:12]); 28: ch = hx(first_bad[11:8]);
            29: ch = hx(first_bad[7:4]);   30: ch = hx(first_bad[3:0]);
            31: ch = " "; 32: ch = "L"; 33: ch = "A"; 34: ch = "S"; 35: ch = "T"; 36: ch = "=";
            37: ch = hx(last_bad[15:12]); 38: ch = hx(last_bad[11:8]);
            39: ch = hx(last_bad[7:4]);   40: ch = hx(last_bad[3:0]);
            41: ch = " "; 42: ch = "T"; 43: ch = "W"; 44: ch = "0"; 45: ch = "=";
            46: ch = hx(tw0[31:28]); 47: ch = hx(tw0[27:24]); 48: ch = hx(tw0[23:20]); 49: ch = hx(tw0[19:16]);
            50: ch = hx(tw0[15:12]); 51: ch = hx(tw0[11:8]);  52: ch = hx(tw0[7:4]);   53: ch = hx(tw0[3:0]);
            54: ch = " "; 55: ch = "T"; 56: ch = "W"; 57: ch = "1"; 58: ch = "=";
            59: ch = hx(tw1[31:28]); 60: ch = hx(tw1[27:24]); 61: ch = hx(tw1[23:20]); 62: ch = hx(tw1[19:16]);
            63: ch = hx(tw1[15:12]); 64: ch = hx(tw1[11:8]);  65: ch = hx(tw1[7:4]);   66: ch = hx(tw1[3:0]);
            67: ch = " "; 68: ch = 8'h0D; 69: ch = 8'h0A;
            default: ch = " ";
        endcase
    end

    reg  [24:0] gap = 25'd0;             // ~0.67 s between lines
    reg  [15:0] baud = 16'd0;
    reg  [3:0]  bitn = 4'd0;
    reg  [9:0]  sh = 10'h3FF;
    reg         busy = 1'b0, sending = 1'b0, tx = 1'b1;
    always @(posedge clk) begin
        if (!busy) begin
            tx <= 1'b1;
            if (!sending) begin
                gap <= gap + 25'd1;
                if (&gap[24:0]) begin sending <= 1'b1; ci <= 7'd0; gap <= 25'd0; end
            end else if (ci == MSG_LEN) begin
                sending <= 1'b0;
            end else begin
                sh <= {1'b1, ch, 1'b0}; bitn <= 4'd0; baud <= 16'd0;
                busy <= 1'b1; tx <= 1'b0;   // start bit
            end
        end else if (baud == UART_DIV[15:0]) begin
            baud <= 16'd0;
            if (bitn == 4'd9) begin
                busy <= 1'b0; ci <= ci + 7'd1;
            end else begin
                bitn <= bitn + 4'd1;
                sh   <= {1'b1, sh[9:1]};
                tx   <= sh[1];
            end
        end else baud <= baud + 16'd1;
    end
    assign uart_tx = tx;
endmodule
