`timescale 1ns / 1ps

// Chapter 18 correction: combinational calculation functions receive every
// changing state as an explicit argument. This makes continuous-assignment
// reevaluation track page, scroll offset and clock state in RTL simulation.
// Module name, ports, dividers, font pixels, scan/PWM and board mapping retained.
// Original one-argument functions remain available to the original testbench.

// ============================================================================
// 4 x 8x8 LED dot-matrix -> 16x16 extension experiment
// Target device: XC7A200T-FBG484-2
//
// This merged version deliberately keeps the two proven parts separate:
//   1. Text pixels and their bit order come unchanged from scroll_msg.mem.
//   2. The 12-hour clock, AM/PM rollover and four-quadrant layout come from
//      the clock-correct version.
//
// Page 0: full message, scrolls left
//         "欢迎使用 GX-BIDT-FPGA 通用创新实验平台"
// Page 1: Chinese suffix, scrolls right
//         "通用创新实验平台"
// Page 2: four-quadrant 12-hour clock
//         upper-left AM/PM, upper-right HH,
//         lower-left MM, lower-right SS
//
// High-active keys:
//   key_down   -> next page
//   key_up     -> previous page
//   key_bright -> 25% / 50% / 75% / 100%
// ============================================================================

module top_16x16_led_scan #(
    parameter integer CLK_HZ         = 100_000_000,
    parameter integer SCAN_DIV       = 20_000,
    parameter integer SCROLL_DIV     = 8_000_000,
    parameter integer SECOND_DIV     = 100_000_000,
    parameter integer DEBOUNCE_DIV   = 1_000_000,
    parameter integer POR_CYCLES     = 32,
    parameter integer PANEL_SWAP_FIX = 1
) (
    input  wire        clk_100m,
    input  wire        key_bright,
    input  wire        key_up,
    input  wire        key_down,
    output wire [15:0] I_ROW,
    output reg  [3:0]  I_COL
);

// The memory contains 320 verified text columns:
//   0..63    "欢迎使用"
//   64..175  "GX-BIDT-FPGA" plus spacing
//   176..303 "通用创新实验平台" (8 Chinese characters x 16 columns)
//   304..319 trailing blank spacing
localparam integer FULL_TEXT_COLS   = 320;
localparam integer FULL_PERIOD_COLS = 336; // text + 16 blank columns
localparam integer CN_TEXT_START    = 176;
localparam integer CN_TEXT_COLS     = 128;
localparam integer CN_PERIOD_COLS   = 144; // text + 16 blank columns

// CLK_HZ documents the board clock and is intentionally retained as a
// user-visible parameter. SECOND_DIV controls the actual one-second divider.

// ============================================================================
// 1. Internal power-on reset
// ============================================================================

reg [7:0] por_count;
reg       rst_int;

initial begin
    por_count = 8'd0;
    rst_int   = 1'b1;
end

always @(posedge clk_100m) begin
    if (por_count < POR_CYCLES - 1) begin
        por_count <= por_count + 1'b1;
        rst_int   <= 1'b1;
    end
    else begin
        rst_int <= 1'b0;
    end
end

wire rst_n_int = ~rst_int;

// ============================================================================
// 2. Key synchronization, debounce and one-shot pulses
// ============================================================================

wire bright_pulse;
wire up_pulse;
wire down_pulse;

key_filter #(
    .DEBOUNCE_CYCLES(DEBOUNCE_DIV)
) u_key_bright (
    .clk       (clk_100m),
    .rst_n     (rst_n_int),
    .key_in    (key_bright),
    .key_press (bright_pulse)
);

key_filter #(
    .DEBOUNCE_CYCLES(DEBOUNCE_DIV)
) u_key_up (
    .clk       (clk_100m),
    .rst_n     (rst_n_int),
    .key_in    (key_up),
    .key_press (up_pulse)
);

key_filter #(
    .DEBOUNCE_CYCLES(DEBOUNCE_DIV)
) u_key_down (
    .clk       (clk_100m),
    .rst_n     (rst_n_int),
    .key_in    (key_down),
    .key_press (down_pulse)
);

// ============================================================================
// 3. Page and brightness selection
// ============================================================================

(* mark_debug = "true" *) reg [1:0] page_sel;
(* mark_debug = "true" *) reg [1:0] bright_lvl;

always @(posedge clk_100m) begin
    if (rst_int) begin
        page_sel   <= 2'd0;
        bright_lvl <= 2'd3;
    end
    else begin
        if (down_pulse) begin
            page_sel <= (page_sel == 2'd2)
                        ? 2'd0
                        : page_sel + 1'b1;
        end
        else if (up_pulse) begin
            page_sel <= (page_sel == 2'd0)
                        ? 2'd2
                        : page_sel - 1'b1;
        end

        if (bright_pulse)
            bright_lvl <= bright_lvl + 1'b1;
    end
end

// ============================================================================
// 4. Four-level PWM brightness
// ============================================================================

reg [7:0] pwm_cnt;
reg [7:0] pwm_limit;

always @(*) begin
    case (bright_lvl)
        2'd0:    pwm_limit = 8'd64;
        2'd1:    pwm_limit = 8'd128;
        2'd2:    pwm_limit = 8'd192;
        default: pwm_limit = 8'd255;
    endcase
end

always @(posedge clk_100m) begin
    if (rst_int)
        pwm_cnt <= 8'd0;
    else
        pwm_cnt <= pwm_cnt + 1'b1;
end

(* mark_debug = "true" *) wire pwm_on =
    (bright_lvl == 2'd3)
    ? 1'b1
    : (pwm_cnt < pwm_limit);

// ============================================================================
// 5. Text scrolling
// ============================================================================

reg [31:0] scroll_cnt;
reg [8:0]  scroll_left;
reg [7:0]  scroll_right;

wire scroll_tick = (scroll_cnt >= SCROLL_DIV - 1);

always @(posedge clk_100m) begin
    if (rst_int || up_pulse || down_pulse) begin
        scroll_cnt   <= 32'd0;
        scroll_left  <= 9'd0;
        scroll_right <= 8'd0;
    end
    else if (scroll_tick) begin
        scroll_cnt <= 32'd0;

        scroll_left <= (scroll_left == FULL_PERIOD_COLS - 1)
                       ? 9'd0
                       : scroll_left + 1'b1;

        scroll_right <= (scroll_right == 8'd0)
                        ? CN_PERIOD_COLS - 1
                        : scroll_right - 1'b1;
    end
    else begin
        scroll_cnt <= scroll_cnt + 1'b1;
    end
end

// This exact signal name is kept for ILA and testbench observation.
(* mark_debug = "true" *) wire [8:0] scroll_offset =
    (page_sel == 2'd0)
    ? scroll_left
    : ((page_sel == 2'd1)
       ? {1'b0, scroll_right}
       : 9'd0);

// ============================================================================
// 6. Proven 12-hour clock
// ============================================================================

reg [31:0] second_cnt;
reg [3:0]  time_hour;
reg [5:0]  time_minute;
reg [5:0]  time_second;
reg        is_pm;

(* mark_debug = "true" *) wire one_hz_tick =
    (second_cnt >= SECOND_DIV - 1);

always @(posedge clk_100m) begin
    if (rst_int) begin
        second_cnt  <= 32'd0;
        time_hour   <= 4'd12;
        time_minute <= 6'd0;
        time_second <= 6'd0;
        is_pm       <= 1'b0;
    end
    else if (one_hz_tick) begin
        second_cnt <= 32'd0;

        if (time_second == 6'd59) begin
            time_second <= 6'd0;

            if (time_minute == 6'd59) begin
                time_minute <= 6'd0;

                if (time_hour == 4'd11) begin
                    time_hour <= 4'd12;
                    is_pm     <= ~is_pm;
                end
                else if (time_hour == 4'd12) begin
                    time_hour <= 4'd1;
                end
                else begin
                    time_hour <= time_hour + 1'b1;
                end
            end
            else begin
                time_minute <= time_minute + 1'b1;
            end
        end
        else begin
            time_second <= time_second + 1'b1;
        end
    end
    else begin
        second_cnt <= second_cnt + 1'b1;
    end
end

// Stable signal names for ILA.
(* mark_debug = "true" *) wire [4:0] hour_12 = {1'b0, time_hour};
(* mark_debug = "true" *) wire [5:0] minute  = time_minute;
(* mark_debug = "true" *) wire [5:0] second  = time_second;

// ============================================================================
// 7. 3x5 font used only by the clock page
// Codes 0..9 are digits, 10=A, 11=P, 12=M.
// ============================================================================

function [2:0] glyph3x5_row;
    input [3:0] code;
    input [2:0] row;

    begin
        glyph3x5_row = 3'b000;

        case (code)
            4'd0: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b101;
                    2: glyph3x5_row = 3'b101;
                    3: glyph3x5_row = 3'b101;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd1: begin
                case (row)
                    0: glyph3x5_row = 3'b010;
                    1: glyph3x5_row = 3'b110;
                    2: glyph3x5_row = 3'b010;
                    3: glyph3x5_row = 3'b010;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd2: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b001;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b100;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd3: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b001;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b001;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd4: begin
                case (row)
                    0: glyph3x5_row = 3'b101;
                    1: glyph3x5_row = 3'b101;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b001;
                    4: glyph3x5_row = 3'b001;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd5: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b100;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b001;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd6: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b100;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b101;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd7: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b001;
                    2: glyph3x5_row = 3'b010;
                    3: glyph3x5_row = 3'b010;
                    4: glyph3x5_row = 3'b010;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd8: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b101;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b101;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd9: begin
                case (row)
                    0: glyph3x5_row = 3'b111;
                    1: glyph3x5_row = 3'b101;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b001;
                    4: glyph3x5_row = 3'b111;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd10: begin
                case (row)
                    0: glyph3x5_row = 3'b010;
                    1: glyph3x5_row = 3'b101;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b101;
                    4: glyph3x5_row = 3'b101;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd11: begin
                case (row)
                    0: glyph3x5_row = 3'b110;
                    1: glyph3x5_row = 3'b101;
                    2: glyph3x5_row = 3'b110;
                    3: glyph3x5_row = 3'b100;
                    4: glyph3x5_row = 3'b100;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            4'd12: begin
                case (row)
                    0: glyph3x5_row = 3'b101;
                    1: glyph3x5_row = 3'b111;
                    2: glyph3x5_row = 3'b111;
                    3: glyph3x5_row = 3'b101;
                    4: glyph3x5_row = 3'b101;
                    default: glyph3x5_row = 3'b000;
                endcase
            end

            default:
                glyph3x5_row = 3'b000;
        endcase
    end
endfunction

// Place two 3x5 characters inside one 8x8 panel. Local rows 0, 6 and 7
// remain blank, so the four panels do not acquire seam or border lines.
function [7:0] pair3x5_col;
    input [3:0] left_code;
    input [3:0] right_code;
    input [2:0] local_col;

    integer r;
    integer bit_index;
    reg [2:0] row_bits;

    begin
        pair3x5_col = 8'd0;

        for (r = 0; r < 5; r = r + 1) begin
            if (local_col <= 3'd2) begin
                row_bits  = glyph3x5_row(left_code, r);
                bit_index = 2 - local_col;
                pair3x5_col[r + 1] = row_bits[bit_index];
            end
            else if ((local_col >= 3'd4) &&
                     (local_col <= 3'd6)) begin
                row_bits  = glyph3x5_row(right_code, r);
                bit_index = 6 - local_col;
                pair3x5_col[r + 1] = row_bits[bit_index];
            end
        end
    end
endfunction

function [15:0] clock_col_calc;
    input [3:0] logical_col;
    input [3:0] clock_hour;
    input [5:0] clock_minute;
    input [5:0] clock_second;
    input clock_pm;

    reg [3:0] left_code;
    reg [3:0] right_code;
    reg [7:0] upper_rows;
    reg [7:0] lower_rows;
    reg [3:0] h_tens;
    reg [3:0] h_ones;
    reg [3:0] m_tens;
    reg [3:0] m_ones;
    reg [3:0] s_tens;
    reg [3:0] s_ones;

    begin
        h_tens = clock_hour / 10;
        h_ones = clock_hour % 10;
        m_tens = clock_minute / 10;
        m_ones = clock_minute % 10;
        s_tens = clock_second / 10;
        s_ones = clock_second % 10;

        if (logical_col < 4'd8) begin
            left_code  = clock_pm ? 4'd11 : 4'd10;
            right_code = 4'd12;

            upper_rows = pair3x5_col(
                left_code,
                right_code,
                logical_col[2:0]
            );

            lower_rows = pair3x5_col(
                m_tens,
                m_ones,
                logical_col[2:0]
            );
        end
        else begin
            upper_rows = pair3x5_col(
                h_tens,
                h_ones,
                logical_col[2:0]
            );

            lower_rows = pair3x5_col(
                s_tens,
                s_ones,
                logical_col[2:0]
            );
        end

        clock_col_calc = {lower_rows, upper_rows};
    end
endfunction

// One-argument compatibility helper for the original project testbench.
function [15:0] clock_col;
    input [3:0] logical_col;
    begin
        clock_col = clock_col_calc(logical_col, time_hour, time_minute, time_second, is_pm);
    end
endfunction

// ============================================================================
// 8. Verified text-ROM address mapping
// ============================================================================

function [8:0] text_relative_pos_calc;
    input [3:0] logical_col;
    input [1:0] active_page;
    input [8:0] left_offset;
    input [7:0] right_offset;

    reg [9:0] sum;

    begin
        sum = 10'd0;

        case (active_page)
            2'd0: begin
                sum = {1'b0, left_offset} + logical_col;
                if (sum >= FULL_PERIOD_COLS)
                    sum = sum - FULL_PERIOD_COLS;
            end

            2'd1: begin
                sum = {2'b00, right_offset} + logical_col;
                if (sum >= CN_PERIOD_COLS)
                    sum = sum - CN_PERIOD_COLS;
            end

            default:
                sum = 10'd0;
        endcase

        text_relative_pos_calc = sum[8:0];
    end
endfunction

// One-argument compatibility helper for the original project testbench.
function [8:0] text_relative_pos;
    input [3:0] logical_col;
    begin
        text_relative_pos = text_relative_pos_calc(logical_col, page_sel, scroll_left, scroll_right);
    end
endfunction

function text_col_valid_calc;
    input [3:0] logical_col;
    input [1:0] active_page;
    input [8:0] left_offset;
    input [7:0] right_offset;

    reg [8:0] rel_pos;

    begin
        rel_pos = text_relative_pos_calc(logical_col, active_page, left_offset, right_offset);

        case (active_page)
            2'd0:    text_col_valid_calc = (rel_pos < FULL_TEXT_COLS);
            2'd1:    text_col_valid_calc = (rel_pos < CN_TEXT_COLS);
            default: text_col_valid_calc = 1'b0;
        endcase
    end
endfunction

// One-argument compatibility helper for the original project testbench.
function text_col_valid;
    input [3:0] logical_col;
    begin
        text_col_valid = text_col_valid_calc(logical_col, page_sel, scroll_left, scroll_right);
    end
endfunction

function [8:0] text_addr_for_calc;
    input [3:0] logical_col;
    input [1:0] active_page;
    input [8:0] left_offset;
    input [7:0] right_offset;

    reg [8:0] rel_pos;

    begin
        rel_pos = text_relative_pos_calc(logical_col, active_page, left_offset, right_offset);

        case (active_page)
            2'd0:    text_addr_for_calc =
                       (rel_pos < FULL_TEXT_COLS)
                       ? rel_pos
                       : 9'd0;
            2'd1:    text_addr_for_calc =
                       (rel_pos < CN_TEXT_COLS)
                       ? CN_TEXT_START + rel_pos
                       : 9'd0;
            default: text_addr_for_calc = 9'd0;
        endcase
    end
endfunction

// One-argument compatibility helper for the original project testbench.
function [8:0] text_addr_for;
    input [3:0] logical_col;
    begin
        text_addr_for = text_addr_for_calc(logical_col, page_sel, scroll_left, scroll_right);
    end
endfunction

// ============================================================================
// 9. Dynamic scan, dual-port text fetch and panel wiring compensation
// ============================================================================

reg [31:0] scan_cnt;

(* mark_debug = "true" *) reg [3:0] scan_col;

reg [15:0] row_hold;
reg        blank_pending;

wire [3:0] next_scan_col =
    (scan_col == 4'd15)
    ? 4'd0
    : scan_col + 1'b1;

wire [3:0] partner_col = next_scan_col ^ 4'd8;

(* mark_debug = "true" *) wire [8:0] rom_addr =
    text_addr_for_calc(next_scan_col, page_sel, scroll_left, scroll_right);

wire [8:0] rom_addr_partner =
    text_addr_for_calc(partner_col, page_sel, scroll_left, scroll_right);

wire text_now_valid =
    text_col_valid_calc(next_scan_col, page_sel, scroll_left, scroll_right);

wire text_partner_valid =
    text_col_valid_calc(partner_col, page_sel, scroll_left, scroll_right);

wire [15:0] text_data;
wire [15:0] text_data_partner;

scroll_rom u_scroll_rom (
    .addr_a (rom_addr),
    .addr_b (rom_addr_partner),
    .data_a (text_data),
    .data_b (text_data_partner)
);

wire [15:0] logical_now =
    (page_sel == 2'd2)
    ? clock_col_calc(next_scan_col, time_hour, time_minute, time_second, is_pm)
    : (text_now_valid ? text_data : 16'h0000);

wire [15:0] logical_partner =
    (page_sel == 2'd2)
    ? clock_col_calc(partner_col, time_hour, time_minute, time_second, is_pm)
    : (text_partner_valid ? text_data_partner : 16'h0000);

// This is exactly the board-tested four-panel mapping from the text version.
wire [15:0] panel_corrected =
    next_scan_col[3]
    ? {logical_now[15:8], logical_partner[15:8]}
    : {logical_partner[7:0], logical_now[7:0]};

wire [15:0] row_to_load =
    PANEL_SWAP_FIX
    ? panel_corrected
    : logical_now;

(* mark_debug = "true" *) wire scan_tick =
    (scan_cnt >= SCAN_DIV - 1);

// Keep these exact names for DUT hierarchy checks and ILA.
(* mark_debug = "true" *) wire blank_phase = blank_pending;

(* mark_debug = "true" *) wire [15:0] selected_row =
    (rst_int || blank_pending || !pwm_on)
    ? 16'h0000
    : row_hold;

always @(posedge clk_100m) begin
    if (rst_int) begin
        scan_cnt      <= 32'd0;
        scan_col      <= 4'd15;
        I_COL         <= 4'd15;
        row_hold      <= 16'h0000;
        blank_pending <= 1'b1;
    end
    else if (blank_pending) begin
        // The old column has already been blanked for one full system-clock
        // period. It is now safe to change the decoder address and row data.
        scan_col      <= next_scan_col;
        I_COL         <= next_scan_col;
        row_hold      <= row_to_load;
        blank_pending <= 1'b0;
    end
    else if (scan_tick) begin
        scan_cnt      <= 32'd0;
        blank_pending <= 1'b1;
    end
    else begin
        scan_cnt <= scan_cnt + 1'b1;
    end
end

assign I_ROW = selected_row;

endmodule
