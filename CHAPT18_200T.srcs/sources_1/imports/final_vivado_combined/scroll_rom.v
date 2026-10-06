`timescale 1ns / 1ps

module scroll_rom (
    input  wire [8:0]  addr_a,
    input  wire [8:0]  addr_b,
    output reg  [15:0] data_a,
    output reg  [15:0] data_b
);

reg [15:0] mem [0:511];

initial begin
    $readmemh("scroll_msg.mem", mem);
end

always @(*) begin
    data_a = mem[addr_a];
    data_b = mem[addr_b];
end

endmodule
