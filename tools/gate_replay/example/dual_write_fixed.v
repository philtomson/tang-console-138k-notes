// dual_write_fixed.v -- the fix: split the array so each part takes at most
// one write per clock.  Correct whether synthesis picks registers or RAM.
// MIT license -- see the repository LICENSE.
module dual_write (
    input  wire        clk,
    input  wire        we,
    input  wire [1:0]  a_lo,
    input  wire [1:0]  a_hi,
    input  wire [2:0]  bsel,
    input  wire [7:0]  d_lo,
    input  wire [7:0]  d_hi,
    input  wire [2:0]  ra,
    output wire [63:0] q
);
    reg [63:0] mem_lo [0:3];
    reg [63:0] mem_hi [0:3];
    always @(posedge clk)
        if (we) begin
            mem_lo[a_lo][{bsel, 3'b000} +: 8] <= d_lo;
            mem_hi[a_hi][{bsel, 3'b000} +: 8] <= d_hi;
        end
    assign q = ra[2] ? mem_hi[ra[1:0]] : mem_lo[ra[1:0]];
endmodule
