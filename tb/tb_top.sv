// ============================================================================
// tb_top.sv - Top-Level Testbench Module
// ============================================================================
`timescale 1ns/1ps

module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import bird_pkg::*;

    // -------------------------------------------------------------------------
    // Clock generation - 10 ns period (100 MHz)
    // -------------------------------------------------------------------------
    logic clk;
    initial clk = 1'b0;
    always #5 clk = ~clk;

    // -------------------------------------------------------------------------
    // Interface instantiation
    // -------------------------------------------------------------------------
    bird_if dut_if (.clk(clk));

    // -------------------------------------------------------------------------
    // DUT instantiation - connect to interface signals
    // -------------------------------------------------------------------------
    bird dut (
        .clk         (clk),
        .rst_n       (dut_if.rst_n),
        .in_vld      (dut_if.in_vld),
        .in_rdy      (dut_if.in_rdy),
        .data_in     (dut_if.data_in),
        .cfg         (dut_if.cfg),
        .local_vld   (dut_if.local_vld),
        .local_rdy   (dut_if.local_rdy),
        .data_local  (dut_if.data_local),
        .remote_vld  (dut_if.remote_vld),
        .remote_rdy  (dut_if.remote_rdy),
        .data_remote (dut_if.data_remote),
        .drop_cnt    (dut_if.drop_cnt)
    );

    // -------------------------------------------------------------------------
    // Reset generation
    //   - rst_n asserted (low) for first 20 ns
    //   - then deasserted (high)
    // -------------------------------------------------------------------------
    initial begin
        dut_if.rst_n      = 1'b0;
        dut_if.in_vld     = 1'b0;
        dut_if.data_in    = 8'h00;
        dut_if.cfg        = 32'h00000000;
        dut_if.local_rdy  = 1'b1;
        dut_if.remote_rdy = 1'b1;

        // Hold reset for 4 clock cycles
        repeat (4) @(negedge clk);
        dut_if.rst_n = 1'b1;
        `uvm_info("tb_top", "Reset deasserted", UVM_LOW)
    end

    // -------------------------------------------------------------------------
    // UVM interface registration in config_db
    // -------------------------------------------------------------------------
    initial begin
        // Register driver_mp modport for driver and base_test
        uvm_config_db #(virtual bird_if.driver_mp)::set(
            null, "uvm_test_top.*", "vif", dut_if.driver_mp);

        // Register monitor_mp modport for monitors and coverage
        uvm_config_db #(virtual bird_if.monitor_mp)::set(
            null, "uvm_test_top.*", "vif", dut_if.monitor_mp);

        // Start UVM test (test name passed via +UVM_TESTNAME=<test>)
        run_test();
    end

    // -------------------------------------------------------------------------
    // Simulation timeout watchdog - abort after 1 ms simulated time
    // -------------------------------------------------------------------------
    initial begin
        #1_000_000;
        `uvm_fatal("tb_top", "Simulation timeout - possible hang detected")
    end

    // -------------------------------------------------------------------------
    // Optional waveform dump
    // -------------------------------------------------------------------------
    initial begin
        if ($test$plusargs("WAVES")) begin
            `ifdef VCS
                $vcdplusfile("bird_tb.vpd");
                $vcdpluson(0, tb_top);
            `elsif QUESTA
                $wlfdumpvars(0, tb_top);
            `else
                $dumpfile("bird_tb.vcd");
                $dumpvars(0, tb_top);
            `endif
        end
    end

endmodule : tb_top
