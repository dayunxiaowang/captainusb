set part xc7a75tfgg484-2
set root [file normalize [file dirname [info script]]/..]
set run_dir $root/build/synth_check
file delete -force $run_dir
create_project CaptainUSB_synth $run_dir -part $part -force
set_property simulator_language Mixed [current_project]
set_property target_language Verilog [current_project]
read_verilog -sv $root/rtl/common/captainusb_pkg.sv
read_verilog -sv $root/rtl/common/captainusb_stream_if.sv
read_verilog -sv $root/rtl/common/captainusb_reset_sync.sv
read_verilog -sv $root/rtl/common/captainusb_sync_fifo.sv
read_verilog -sv $root/rtl/common/captainusb_async_fifo.sv
read_verilog -sv $root/rtl/ft601/captainusb_ft601_phy.sv
read_verilog -sv $root/rtl/ft601/captainusb_ft601_loopback.sv
read_verilog -sv $root/rtl/dma/captainusb_ring_tx_dma.sv
read_verilog -sv $root/rtl/dma/captainusb_ring_rx_dma.sv
read_verilog -sv $root/rtl/pcie/captainusb_tlp_rx64.sv
read_verilog -sv $root/rtl/pcie/captainusb_tlp_tx64.sv
read_verilog -sv $root/rtl/pcie/captainusb_pcie_requester_7x.sv
read_verilog -sv $root/rtl/pcie/captainusb_bar0_regs.sv
read_verilog -sv $root/rtl/pcie/captainusb_pcie_app.sv
read_verilog -sv $root/rtl/pcie/captainusb_pcie_minimal_a7.sv
read_verilog -sv $root/rtl/captainusb_top.sv
read_ip $root/ip/captainusb_pcie_7x.xci
read_xdc $root/constraints/captainusb_75t484_x1.xdc
set_property top captainusb_top [current_fileset]
upgrade_ip [get_ips] -quiet
generate_target all [get_ips]
update_compile_order -fileset sources_1
launch_runs synth_1 -jobs 2
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synth failed" }
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} { error "synth failed" }
puts "Synthesis PASSED"