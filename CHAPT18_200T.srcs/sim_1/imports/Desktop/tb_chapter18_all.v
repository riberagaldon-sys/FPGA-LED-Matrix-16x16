`timescale 1ns/1ps

// Chapter 18: 16x16 LED matrix EXTENDED project, not the LCD renderer.
// Project: top_16x16_led_scan_ext_200t_clean.xpr.
// Design: use companion top_16x16_led_scan_chapter18.v IN PLACE OF the active
// top_16x16_led_scan.v; keep key_filter.v, scroll_rom.v and scroll_msg.mem.
// Add this file to Simulation Sources; Simulation Top: tb_chapter18_all.
// Tcl: restart; run 8 ms. Require CH18 PASS, tests_done=1, error_count=0.
// The existing scroll_msg.mem must remain in the project and simulation directory.
// No $finish/$stop, no force/deposit or writes into DUT registers/memory.
// The companion DUT is exercised through its three high-active key inputs.
// Its function inputs are explicit; all fonts/dividers/scan/PWM behavior is retained.
//
// 100 MHz clock, accelerated SIMULATION dividers only:
// scan=8, scroll=256, second=8, debounce=4, POR=4, PANEL_SWAP_FIX=1.
// One simulated clock second is 80 ns; a full 24-hour run takes about 6.912 ms.
// Do not copy these shortened dividers into the board's download parameters.
//
// Initial capture guides (ns; root Scope tb_chapter18_all):
// 18-1 scan/blanking: 20..1600; detail 105..155.
// 18-2 page and two scroll directions: 894000..914000.
// 18-3 four PWM levels: 1400000..1440000.
// 18-4(a) second/minute carry on clock page: 1300680..1301000.
// 18-4(b) 11:59:59 AM -> 12:00:00 PM: 3455860..3456150.
// Optional same 12-hour rule: 12:59:59 PM -> 01:00:00 PM at 3744035 ns;
// 11:59:59 PM -> 12:00:00 AM at 6912035 ns. Both checked automatically.

module tb_chapter18_all;
    localparam integer SCAN_SIM=8, SCROLL_SIM=256, SECOND_SIM=8, DEBOUNCE_SIM=4;
    reg clk_100m=0;
    reg key_bright=0, key_up=0, key_down=0;
    wire [15:0] I_ROW;
    wire [3:0] I_COL;
    top_16x16_led_scan #(
        .CLK_HZ(100_000_000), .SCAN_DIV(SCAN_SIM), .SCROLL_DIV(SCROLL_SIM),
        .SECOND_DIV(SECOND_SIM), .DEBOUNCE_DIV(DEBOUNCE_SIM),
        .POR_CYCLES(4), .PANEL_SWAP_FIX(1)
    ) dut (
        .clk_100m(clk_100m), .key_bright(key_bright), .key_up(key_up),
        .key_down(key_down), .I_ROW(I_ROW), .I_COL(I_COL)
    );
    always #5 clk_100m=~clk_100m;

    // Aliases of actual DUT signals, available directly in the root Scope.
    wire rst_int=dut.rst_int;
    wire [3:0] scan_col=dut.scan_col;
    wire scan_tick=dut.scan_tick, blank_phase=dut.blank_phase;
    wire [15:0] row_hold=dut.row_hold, selected_row=dut.selected_row;
    wire [15:0] row_to_load=dut.row_to_load;
    wire [1:0] page_sel=dut.page_sel, bright_lvl=dut.bright_lvl;
    wire bright_pulse=dut.bright_pulse, up_pulse=dut.up_pulse, down_pulse=dut.down_pulse;
    wire [8:0] scroll_left=dut.scroll_left, scroll_offset=dut.scroll_offset;
    wire [7:0] scroll_right=dut.scroll_right;
    wire [8:0] rom_addr=dut.rom_addr, rom_addr_partner=dut.rom_addr_partner;
    wire [15:0] text_data=dut.text_data, text_data_partner=dut.text_data_partner;
    wire [7:0] pwm_cnt=dut.pwm_cnt, pwm_limit=dut.pwm_limit;
    wire pwm_on=dut.pwm_on, one_hz_tick=dut.one_hz_tick;
    wire [4:0] hour_12=dut.hour_12;
    wire [5:0] minute=dut.minute, second=dut.second;
    wire is_pm=dut.is_pm;

    reg [15:0] expected_rom[0:511];
    integer error_count=0, check_count=0, test_case=0;
    integer scan_changes=0, blank_checks=0, row_checks=0, rom_checks=0;
    integer page0_loads=0, page1_loads=0, page2_loads=0;
    integer left_wraps=0, right_wraps=0, clock_tick_checks=0;
    integer minute_carries=0, hour_carries=0, ampm_changes=0, twelve_to_one=0;
    integer up_count=0, down_count=0, bright_count=0;
    integer pwm_25=0, pwm_50=0, pwm_75=0, pwm_100=0;
    reg key_tests_done=0, pwm_tests_done=0, tests_done=0;
    integer active_cycles=0, scroll_cycles=0, ref_page=0, ref_bright=3;
    integer ref_seconds=0, ref_hour=12, ref_minute=0, ref_second=0, ref_pm=0;
    integer ref_left=0, ref_right=0, gap_cycles=0;
    reg [15:0] expected_hold=0;
    reg [3:0] previous_col=15;
    reg seen_load=0;
    reg previous_blank=1;
    reg previous_up=0, previous_down=0, previous_bright=0;
    reg [15:0] expected_rows=0;
    wire row_match=(I_ROW === expected_rows);
    integer old_left, old_right, old_seconds, old_hour, old_minute, old_pm;
    integer nc, pa, aa, ab, new_hour24;
    reg old_up, old_down, old_bright, old_blank;
    reg [15:0] lc, pc;
    integer i, before_down, before_up;

    task fail;
        input [8*120-1:0] reason;
        begin
            error_count=error_count+1;
            if (error_count<=16)
                $display("CH18 FAIL: %0s at %0t case=%0d page=%0d col=%0d row=%04h expected=%04h",
                         reason,$time,test_case,page_sel,I_COL,I_ROW,expected_rows);
        end
    endtask

    // Text oracle uses circular arithmetic and original file data, not DUT functions.
    function integer reference_address;
        input integer pg, left_offset, right_offset, logical_col;
        integer pos;
        begin
            if (pg==0) begin
                pos=(left_offset+logical_col)%336;
                reference_address=(pos<320) ? pos : -1;
            end else if (pg==1) begin
                pos=(right_offset+logical_col)%144;
                reference_address=(pos<128) ? 176+pos : -1;
            end else reference_address=-1;
        end
    endfunction

    // Packed 3x5 visual glyph definitions: row 0 first, MSB is left pixel.
    function [14:0] visual_glyph;
        input integer code;
        begin
            case (code)
                 0: visual_glyph=15'b111101101101111;
                 1: visual_glyph=15'b010110010010111;
                 2: visual_glyph=15'b111001111100111;
                 3: visual_glyph=15'b111001111001111;
                 4: visual_glyph=15'b101101111001001;
                 5: visual_glyph=15'b111100111001111;
                 6: visual_glyph=15'b111100111101111;
                 7: visual_glyph=15'b111001010010010;
                 8: visual_glyph=15'b111101111101111;
                 9: visual_glyph=15'b111101111001111;
                10: visual_glyph=15'b010101111101101; // A
                11: visual_glyph=15'b110101110100100; // P
                12: visual_glyph=15'b101111111101101; // M
                default: visual_glyph=0;
            endcase
        end
    endfunction

    // Independently rasterize AM/PM, HH, MM, SS in the four logical quadrants.
    function [15:0] reference_clock_column;
        input integer column, hh, mm, ss, pm;
        integer yy, lx, ly, code, digit_x;
        reg [14:0] glyph;
        begin
            reference_clock_column=0;
            lx=column%8;
            for (yy=0;yy<16;yy=yy+1) begin
                ly=yy%8;
                if ((ly>=1)&&(ly<=5)&&((lx<3)||((lx>=4)&&(lx<=6)))) begin
                    digit_x=(lx<3) ? lx : lx-4;
                    if ((column<8)&&(yy<8)) code=(lx<3) ? (pm ? 11 : 10) : 12;
                    else if (yy<8) code=(lx<3) ? hh/10 : hh%10;
                    else if (column<8) code=(lx<3) ? mm/10 : mm%10;
                    else code=(lx<3) ? ss/10 : ss%10;
                    glyph=visual_glyph(code);
                    reference_clock_column[yy]=glyph[14-(ly-1)*3-digit_x];
                end
            end
        end
    endfunction

    function [15:0] reference_logical_column;
        input integer pg, left_offset, right_offset, column, hh, mm, ss, pm;
        integer addr;
        begin
            if (pg==2) reference_logical_column=reference_clock_column(column,hh,mm,ss,pm);
            else begin
                addr=reference_address(pg,left_offset,right_offset,column);
                reference_logical_column=(addr<0) ? 16'h0000 : expected_rom[addr];
            end
        end
    endfunction

    // Check actual outputs after NBA settles. Reference time comes from elapsed
    // active input-clock cycles, and scrolling from cycles since a page-key pulse.
    always @(posedge clk_100m) begin
        if (rst_int) begin
            active_cycles=0; scroll_cycles=0; ref_page=0; ref_bright=3;
            ref_seconds=0; ref_hour=12; ref_minute=0; ref_second=0; ref_pm=0;
            ref_left=0; ref_right=0; expected_hold=0; previous_col=15;
            seen_load=0; previous_blank=1; gap_cycles=0;
            previous_up=0; previous_down=0; previous_bright=0;
            #1;
            expected_rows=0;
            if ((I_ROW !== 0)||(I_COL !== 15)) fail("power-on reset output mismatch");
        end else begin
            old_up=up_pulse; old_down=down_pulse; old_bright=bright_pulse;
            old_blank=blank_phase;
            old_left=ref_left; old_right=ref_right; old_seconds=ref_seconds;
            old_hour=ref_hour; old_minute=ref_minute; old_pm=ref_pm;
            if (old_blank) begin
                nc=(previous_col+1)%16; pa=nc^8;
                lc=reference_logical_column(ref_page,ref_left,ref_right,nc,ref_hour,ref_minute,ref_second,ref_pm);
                pc=reference_logical_column(ref_page,ref_left,ref_right,pa,ref_hour,ref_minute,ref_second,ref_pm);
                // Physical panel wiring: upper-left/lower-right partner routing.
                expected_hold=(nc<8) ? {pc[7:0],lc[7:0]} : {lc[15:8],pc[15:8]};
                if (ref_page==0) page0_loads=page0_loads+1;
                if (ref_page==1) page1_loads=page1_loads+1;
                if (ref_page==2) page2_loads=page2_loads+1;
            end
            if (old_up) up_count=up_count+1;
            if (old_down) down_count=down_count+1;
            if (old_bright) bright_count=bright_count+1;
            if (old_down) ref_page=(ref_page+1)%3;
            else if (old_up) ref_page=(ref_page+2)%3;
            if (old_bright) ref_bright=(ref_bright+1)%4;
            if (old_up||old_down) scroll_cycles=0;
            else scroll_cycles=scroll_cycles+1;
            ref_left=(scroll_cycles/SCROLL_SIM)%336;
            ref_right=(144-((scroll_cycles/SCROLL_SIM)%144))%144;
            if (!(old_up||old_down)) begin
                if (ref_left<old_left) left_wraps=left_wraps+1;
                if ((old_right==0)&&(ref_right==143)) right_wraps=right_wraps+1;
            end
            active_cycles=active_cycles+1;
            ref_seconds=active_cycles/SECOND_SIM;
            new_hour24=(ref_seconds/3600)%24;
            ref_hour=new_hour24%12; if (ref_hour==0) ref_hour=12;
            ref_minute=(ref_seconds/60)%60; ref_second=ref_seconds%60;
            ref_pm=(new_hour24>=12);
            if (ref_seconds!=old_seconds) begin
                clock_tick_checks=clock_tick_checks+1;
                if (ref_seconds%60==0) minute_carries=minute_carries+1;
                if (ref_seconds%3600==0) hour_carries=hour_carries+1;
                if (ref_pm!=old_pm) ampm_changes=ampm_changes+1;
                if ((old_hour==12)&&(ref_hour==1)) twelve_to_one=twelve_to_one+1;
            end
            gap_cycles=gap_cycles+1;
            #1;
            check_count=check_count+1;
            if ((^I_ROW === 1'bx)||(^I_COL === 1'bx)) fail("X/Z on matrix outputs");
            if ((page_sel !== ref_page[1:0])||(bright_lvl !== ref_bright[1:0]))
                fail("page/brightness key behavior mismatch");
            if ((hour_12 !== ref_hour[4:0])||(minute !== ref_minute[5:0])||
                (second !== ref_second[5:0])||(is_pm !== ref_pm[0]))
                fail("natural 12-hour clock differs from elapsed-cycle oracle");
            if (one_hz_tick !== ((active_cycles%SECOND_SIM)==SECOND_SIM-1))
                fail("one-second tick timing mismatch");
            if ((scroll_left !== ref_left[8:0])||(scroll_right !== ref_right[7:0]))
                fail("scroll direction/reset/circular wrap mismatch");
            if (scroll_offset !== ((ref_page==0) ? ref_left : ((ref_page==1) ? ref_right : 0)))
                fail("selected page scroll offset mismatch");
            if (pwm_cnt !== (active_cycles%256)) fail("PWM counter period mismatch");
            if (pwm_limit !== ((ref_bright==3) ? 255 : 64*(ref_bright+1)))
                fail("PWM threshold mismatch");
            if (pwm_on !== ((ref_bright==3)||((active_cycles%256)<64*(ref_bright+1))))
                fail("PWM gating mismatch");
            if (I_COL !== scan_col) fail("decoder address differs from scan column");
            if (I_COL != previous_col) begin
                if ((I_COL !== ((previous_col+1)%16))||!old_blank)
                    fail("column changed without a preceding blank clock or out of order");
                if (seen_load && (gap_cycles != SCAN_SIM+1)) fail("scan interval mismatch");
                seen_load=1; gap_cycles=0; scan_changes=scan_changes+1;
            end else if (old_blank) fail("blank clock was not followed by a new column");
            if (blank_phase) begin
                blank_checks=blank_checks+1;
                if (previous_blank) fail("blanking lasted more than one active clock");
                if (I_ROW !== 0) fail("nonzero row output during blanking");
            end
            if (row_hold !== expected_hold) fail("physical panel row mapping mismatch");
            expected_rows=(blank_phase||!pwm_on) ? 16'h0000 : expected_hold;
            row_checks=row_checks+1;
            if ((I_ROW !== expected_rows)||(selected_row !== expected_rows))
                fail("row output does not obey scan/PWM blanking");
            nc=(I_COL+1)%16; pa=nc^8;
            aa=reference_address(ref_page,ref_left,ref_right,nc);
            ab=reference_address(ref_page,ref_left,ref_right,pa);
            if ((rom_addr !== ((aa<0) ? 0 : aa))||(rom_addr_partner !== ((ab<0) ? 0 : ab)))
                fail("dual ROM addresses differ from circular text mapping");
            if ((text_data !== expected_rom[(aa<0) ? 0 : aa])||
                (text_data_partner !== expected_rom[(ab<0) ? 0 : ab])) fail("ROM data mismatch");
            rom_checks=rom_checks+2;
            if ((up_pulse&&previous_up)||(down_pulse&&previous_down)||
                (bright_pulse&&previous_bright)) fail("key pulse is wider than one clock");
            previous_col=I_COL; previous_blank=blank_phase;
            previous_up=up_pulse; previous_down=down_pulse; previous_bright=bright_pulse;
        end
    end

    // Drive only external inputs on falling edges. kind: 0=up, 1=down, 2=bright.
    task press_key;
        input integer kind, hold_cycles;
        integer j;
        begin
            #1; // after the falling edge, so all waits count future clock edges
            key_up=(kind==0); key_down=(kind==1); key_bright=(kind==2);
            for (j=0;j<hold_cycles;j=j+1) @(negedge clk_100m);
            key_up=0; key_down=0; key_bright=0;
            repeat (20) @(negedge clk_100m);
        end
    endtask

    task check_pwm_period;
        input integer high_samples;
        integer j, highs;
        begin
            while (pwm_cnt != 0) @(negedge clk_100m);
            highs=0;
            for (j=0;j<256;j=j+1) begin
                if (pwm_on) highs=highs+1;
                @(negedge clk_100m);
            end
            if (highs!=high_samples) fail("256-clock PWM duty count mismatch");
            case (high_samples)
                 64: pwm_25=highs;
                128: pwm_50=highs;
                192: pwm_75=highs;
                256: pwm_100=highs;
            endcase
        end
    endtask

    initial begin
        // The original project contains 321 words (word 320 is unused zero padding).
        $readmemh("scroll_msg.mem",expected_rom,0,320);
        #2;
        for (i=0;i<321;i=i+1)
            if ((^expected_rom[i] === 1'bx)||(dut.u_scroll_rom.mem[i] !== expected_rom[i]))
                fail("original text memory missing or inconsistent");
        if ((expected_rom[0]!==16'h0000)||(expected_rom[1]!==16'h1004)||
            (expected_rom[17]!==16'h6020)||(expected_rom[73]!==16'h0FF0)||
            (expected_rom[257]!==16'h09FA)||(expected_rom[319]!==16'h0000))
            fail("original text ROM fingerprint mismatch");

        #899998; // absolute 900000 ns: full-message wrap already exercised
        test_case=1;
        if (left_wraps<1) fail("full-message scroll did not reach its natural wrap");
        before_down=down_count;
        press_key(1,20);
        if ((page_sel!==1)||(down_count!=before_down+1)) fail("next-page key failed");
        #399600; // absolute 1300000 ns: Chinese right-scroll has wrapped
        test_case=2;
        press_key(1,20);
        if (page_sel!==2) fail("clock page not selected");

        #19600; // 1320000 ns: short glitches must not create a page event
        test_case=3; before_down=down_count; #1;
        key_down=1; @(negedge clk_100m); key_down=0;
        repeat (2) @(negedge clk_100m);
        key_down=1; repeat (2) @(negedge clk_100m); key_down=0;
        repeat (10) @(negedge clk_100m);
        if ((page_sel!==2)||(down_count!=before_down)) fail("short key glitch passed debounce");

        #(1330000-$time); test_case=4; before_up=up_count;
        press_key(0,100); // held key must create exactly one event
        if ((page_sel!==1)||(up_count!=before_up+1)) fail("held key repeated or was missed");
        #(1340000-$time); test_case=5; press_key(0,20);
        if (page_sel!==0) fail("previous-page key failed");
        #(1350000-$time); test_case=6; press_key(0,20);
        if (page_sel!==2) fail("previous-page wrap 0 to 2 failed");
        #(1360000-$time); test_case=7; press_key(1,20);
        if (page_sel!==0) fail("next-page wrap 2 to 0 failed");
        #(1370000-$time); test_case=8; press_key(0,20);
        if (page_sel!==2) fail("return to clock page failed");
        #(1380000-$time); test_case=9;
        #1; key_up=1; key_down=1; repeat (20) @(negedge clk_100m);
        key_up=0; key_down=0; repeat (20) @(negedge clk_100m);
        if (page_sel!==0) fail("simultaneous page keys did not give down priority");
        #(1390000-$time); test_case=10; press_key(0,20);
        if (page_sel!==2) fail("final clock page selection failed");
        key_tests_done=1;

        #(1400000-$time); test_case=20;
        // Check default 100% before the first brightness event.
        if (bright_lvl!==3) fail("default brightness is not 100 percent");
        press_key(2,20); check_pwm_period(64);
        #(1410000-$time); test_case=21; press_key(2,20); check_pwm_period(128);
        #(1420000-$time); test_case=22; press_key(2,20); check_pwm_period(192);
        #(1430000-$time); test_case=23; press_key(2,20); check_pwm_period(256);
        pwm_tests_done=1; test_case=30;

        // Natural clock evolution, including both AM/PM transitions and 12 -> 1.
        wait (clock_tick_checks>=86402);
        @(negedge clk_100m);
        if ((minute_carries<1440)||(hour_carries<24)||(ampm_changes!=2)||
            (twelve_to_one!=2)) fail("24-hour clock rollover coverage incomplete");
        if ((page0_loads==0)||(page1_loads==0)||(page2_loads==0)||
            (left_wraps<1)||(right_wraps<2)||(scan_changes<1000)||!key_tests_done||!pwm_tests_done)
            fail("scan/scroll/key/PWM coverage incomplete");
        tests_done=1;
        if (error_count==0)
            $display("CH18 PASS: scan=%0d rows=%0d rom=%0d ticks=%0d AMPM=%0d 12to1=%0d PWM=%0d/%0d/%0d/%0d errors=%0d",
                scan_changes,row_checks,rom_checks,clock_tick_checks,ampm_changes,twelve_to_one,
                pwm_25,pwm_50,pwm_75,pwm_100,error_count);
        else $display("CH18 FAIL: total errors=%0d",error_count);
    end
endmodule
