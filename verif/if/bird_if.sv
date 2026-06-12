// ============================================================
// BIRD Interface — clocking blocks for driver and monitors
// ============================================================
interface bird_if (input logic clk);

    // ---- DUT signals ----------------------------------------
    logic        rst_n;

    // Input channel
    logic        in_vld;
    logic        in_rdy;
    logic [7:0]  data_in;
    logic [31:0] cfg;

    // Local output channel
    logic        local_vld;
    logic        local_rdy;
    logic [7:0]  data_local;

    // Remote output channel
    logic        remote_vld;
    logic        remote_rdy;
    logic [31:0] data_remote;

    // Status
    logic [15:0] drop_cnt;

    // ---- Driver clocking block ------------------------------
    // Inputs to DUT driven at negedge (setup before posedge sample)
    // DUT outputs (in_rdy, local_vld, …) sampled at posedge
    clocking driver_cb @(posedge clk);
        default input  #1step;
        default output #1ns;

        // Signals driven by driver (DUT inputs)
        output in_vld;
        output data_in;
        output cfg;
        output local_rdy;
        output remote_rdy;

        // Signals sampled by driver (DUT outputs)
        input  in_rdy;
        input  local_vld;
        input  data_local;
        input  remote_vld;
        input  data_remote;
        input  drop_cnt;
    endclocking : driver_cb

    // ---- Monitor clocking block -----------------------------
    // All signals sampled at posedge — pure observation
    clocking monitor_cb @(posedge clk);
        default input #1step;

        input in_vld;
        input in_rdy;
        input data_in;
        input cfg;

        input local_vld;
        input local_rdy;
        input data_local;

        input remote_vld;
        input remote_rdy;
        input data_remote;

        input drop_cnt;
    endclocking : monitor_cb

    // ---- Modports -------------------------------------------
    modport driver_mp  (clocking driver_cb,  input clk, input rst_n);
    modport monitor_mp (clocking monitor_cb, input clk, input rst_n);

endinterface : bird_if
