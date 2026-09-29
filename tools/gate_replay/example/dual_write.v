// dual_write.v -- reproducer: two byte-writes into ONE array in the same
// clock (one in words 0..3, one in words 4..7).  Simulation performs both;
// if synthesis maps `mem` to a single-write-port RAM, one of the two writes
// is silently lost.  Shape taken from a real bug (docs/04, pitfall 1).
// MIT license -- see the repository LICENSE.
module dual_write (
    input  wire        clk,
    input  wire        we,
    input  wire [1:0]  a_lo,      // word 0..3
    input  wire [1:0]  a_hi,      // word 4..7
    input  wire [2:0]  bsel,      // byte within the word
    input  wire [7:0]  d_lo,
    input  wire [7:0]  d_hi,
    input  wire [2:0]  ra,        // read address
    output wire [63:0] q
);
    reg [63:0] mem [0:7];
    always @(posedge clk)
        if (we) begin
            mem[{1'b0, a_lo}][{bsel, 3'b000} +: 8] <= d_lo;
            mem[{1'b1, a_hi}][{bsel, 3'b000} +: 8] <= d_hi;
        end
    assign q = mem[ra];
endmodule
