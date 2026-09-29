// pmod_dtx2.v -- driver for Sipeed's PMOD-DTx2 two-digit 7-segment module.
//
// Shows `value` as two hex digits (tens = value[7:4] on the left as the
// Tang Console is normally viewed).  Segments are active-low and the two
// digits share the segment lines, selected by `sel` (1 = tens digit), so
// the driver multiplexes at clk / 2^(SCAN_BITS+1) per digit.
//
// ROTATE180=1 (default) is right for the module plugged into the Tang
// Console's PMOD1: as mounted the display reads upside down, so the font is
// rotated (A<->D, B<->E, C<->F).  Set 0 if yours reads upside down.
//
// MIT license -- see the repository LICENSE.
module pmod_dtx2 #(
    parameter SCAN_BITS = 17,   // 50 MHz / 2^17 = ~381 Hz per digit
    parameter ROTATE180 = 1
) (
    input  wire       clk,
    input  wire [7:0] value,
    output wire [6:0] seg,      // {G,F,E,D,C,B,A}, active low -> PMOD pins
    output wire       sel       // 1 = tens digit
);
    reg [SCAN_BITS-1:0] scan = 0;
    always @(posedge clk) scan <= scan + 1'b1;
    assign sel = scan[SCAN_BITS-1];

    wire [3:0] nib = sel ? value[7:4] : value[3:0];
    reg  [6:0] on;              // {G,F,E,D,C,B,A}, 1 = lit
    always @(*) begin
        case (nib)
            4'h0: on = 7'h3F;  4'h1: on = 7'h06;  4'h2: on = 7'h5B;  4'h3: on = 7'h4F;
            4'h4: on = 7'h66;  4'h5: on = 7'h6D;  4'h6: on = 7'h7D;  4'h7: on = 7'h07;
            4'h8: on = 7'h7F;  4'h9: on = 7'h6F;  4'hA: on = 7'h77;  4'hB: on = 7'h7C;
            4'hC: on = 7'h39;  4'hD: on = 7'h5E;  4'hE: on = 7'h79;  default: on = 7'h71;
        endcase
    end
    wire [6:0] on_r = ROTATE180 ? {on[6], on[2], on[1], on[0], on[5], on[4], on[3]} : on;
    assign seg = ~on_r;
endmodule
