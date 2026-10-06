`timescale 1ns / 1ps

module key_filter #(
    parameter integer DEBOUNCE_CYCLES = 1_000_000
) (
    input  wire clk,
    input  wire rst_n,
    input  wire key_in,
    output wire key_press
);

reg key_meta;
reg key_sync;
reg key_stable;
reg key_stable_d;
reg [31:0] debounce_cnt;

always @(posedge clk) begin
    if (!rst_n) begin
        key_meta     <= 1'b0;
        key_sync     <= 1'b0;
        key_stable   <= 1'b0;
        key_stable_d <= 1'b0;
        debounce_cnt <= 32'd0;
    end
    else begin
        key_meta <= key_in;
        key_sync <= key_meta;

        if (key_sync == key_stable) begin
            debounce_cnt <= 32'd0;
        end
        else if (debounce_cnt >= DEBOUNCE_CYCLES - 1) begin
            key_stable   <= key_sync;
            debounce_cnt <= 32'd0;
        end
        else begin
            debounce_cnt <= debounce_cnt + 1'b1;
        end

        key_stable_d <= key_stable;
    end
end

assign key_press = key_stable & ~key_stable_d;

endmodule