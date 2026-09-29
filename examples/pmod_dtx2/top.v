// top.v -- PMOD-DTx2 demo for the Tang Console 138K: counts 00..FF on the
// display (about 4 per second) and blinks the V13 LED.
// MIT license -- see the repository LICENSE.
module top (
    input  wire       clk,        // 50 MHz, V22
    output wire       led,        // V13, lit when high
    output wire [6:0] pmod_seg,   // PMOD1, see pins.cst
    output wire       pmod_sel
);
    reg [25:0] div = 0;
    reg [7:0]  count = 0;
    always @(posedge clk) begin
        div <= div + 1'b1;
        if (&div[23:0]) count <= count + 1'b1;
    end
    assign led = div[25];
    pmod_dtx2 u_disp (.clk(clk), .value(count), .seg(pmod_seg), .sel(pmod_sel));
endmodule
