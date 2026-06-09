// ============================================================
// BIRD — Birzeit Integrated Router Design
// DUT placeholder — port declaration only, no implementation
// ============================================================
module bird (
    // Global
    input  logic        clk,
    input  logic        rst_n,

    // Input interface (valid/ready handshake)
    input  logic        in_vld,
    output logic        in_rdy,
    input  logic [7:0]  data_in,
    input  logic [31:0] cfg,

    // Local output interface
    output logic        local_vld,
    input  logic        local_rdy,
    output logic [7:0]  data_local,

    // Remote output interface
    output logic        remote_vld,
    input  logic        remote_rdy,
    output logic [31:0] data_remote,

    // Status
    output logic [15:0] drop_cnt
);

// TODO: implement routing logic
// Placeholder — outputs driven to safe defaults
assign in_rdy      = 1'b0;
assign local_vld   = 1'b0;
assign data_local  = 8'h00;
assign remote_vld  = 1'b0;
assign data_remote = 32'h00000000;
assign drop_cnt    = 16'h0000;

endmodule : bird
