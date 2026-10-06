## ============================================================================
## 16x16 LED dot-matrix extension experiment
## Target part: xc7a200tfbg484-2
## Top module : top_16x16_led_scan
## ============================================================================

## 100 MHz system clock
set_property PACKAGE_PIN W19 [get_ports clk_100m]
set_property IOSTANDARD LVCMOS33 [get_ports clk_100m]
create_clock -name clk_100m -period 10.000 -waveform {0.000 5.000} \
    [get_ports clk_100m]

## High-active push buttons:
## key_bright = KEY_0, key_up = KEY_1, key_down = KEY_2
set_property PACKAGE_PIN Y6  [get_ports key_bright]
set_property PACKAGE_PIN AA6 [get_ports key_up]
set_property PACKAGE_PIN V7  [get_ports key_down]
set_property IOSTANDARD LVCMOS33 \
    [get_ports {key_bright key_up key_down}]
set_property PULLDOWN true \
    [get_ports {key_bright key_up key_down}]
set_false_path -from [get_ports {key_bright key_up key_down}]

## I_COL[3:0]: column address for the two 74HC138 decoders
set_property PACKAGE_PIN P14 [get_ports {I_COL[0]}]
set_property PACKAGE_PIN R14 [get_ports {I_COL[1]}]
set_property PACKAGE_PIN P19 [get_ports {I_COL[2]}]
set_property PACKAGE_PIN R19 [get_ports {I_COL[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {I_COL[*]}]
set_property DRIVE 8 [get_ports {I_COL[*]}]
set_property SLEW SLOW [get_ports {I_COL[*]}]

## I_ROW[15:0]: 16 high-active row-pixel outputs
set_property PACKAGE_PIN T21  [get_ports {I_ROW[0]}]
set_property PACKAGE_PIN U21  [get_ports {I_ROW[1]}]
set_property PACKAGE_PIN U20  [get_ports {I_ROW[2]}]
set_property PACKAGE_PIN V20  [get_ports {I_ROW[3]}]
set_property PACKAGE_PIN W20  [get_ports {I_ROW[4]}]
set_property PACKAGE_PIN T20  [get_ports {I_ROW[5]}]
set_property PACKAGE_PIN AB21 [get_ports {I_ROW[6]}]
set_property PACKAGE_PIN AB22 [get_ports {I_ROW[7]}]
set_property PACKAGE_PIN N13  [get_ports {I_ROW[8]}]
set_property PACKAGE_PIN V22  [get_ports {I_ROW[9]}]
set_property PACKAGE_PIN W21  [get_ports {I_ROW[10]}]
set_property PACKAGE_PIN W22  [get_ports {I_ROW[11]}]
set_property PACKAGE_PIN R18  [get_ports {I_ROW[12]}]
set_property PACKAGE_PIN Y19  [get_ports {I_ROW[13]}]
set_property PACKAGE_PIN V18  [get_ports {I_ROW[14]}]
set_property PACKAGE_PIN V19  [get_ports {I_ROW[15]}]
set_property IOSTANDARD LVCMOS33 [get_ports {I_ROW[*]}]
set_property DRIVE 8 [get_ports {I_ROW[*]}]
set_property SLEW SLOW [get_ports {I_ROW[*]}]

## Configuration-bank voltage (removes CFGBVS-1 DRC warning)
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
