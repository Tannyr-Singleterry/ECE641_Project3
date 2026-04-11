// ============================================================================
// Copyright (c) 2025 by Terasic Technologies Inc.
// ============================================================================
//
// Permission:
//
//   Terasic grants permission to use and modify this code for use
//   in synthesis for all Terasic Development Boards and Altera Development
//   Kits made by Terasic.  Other use of this code, including the selling
//   ,duplication, or modification of any portion is strictly prohibited.
//
// Disclaimer:
//
//   This VHDL/Verilog or C/C++ source code is intended as a design reference
//   which illustrates how these types of functions can be implemented.
//   It is the user's responsibility to verify their design for
//   consistency and functionality through the use of formal
//   verification methods.  Terasic provides no warranty regarding the use
//   or functionality of this code.
//
// ============================================================================
//
//  Terasic Technologies Inc
//  No.80, Fenggong Rd., Hukou Township, Hsinchu County 303035. Taiwan
//
//
//                     web: http://www.terasic.com/
//                     email: support@terasic.com
//
// ============================================================================
// ECE641 Project 3 - HDMI + SDRAM + UART Integration
// Base: Terasic PR3 golden_top
// ============================================================================


module golden_top(

      ///////// CLOCK /////////
      input              CLOCK0_50,
      input              CLOCK1_50,

      ///////// KEY /////////
      input    [ 3: 0]   KEY, //BUTTON is Low-Active

      ///////// SW /////////
      input    [ 9: 0]   SW,

      ///////// LED /////////
      output   [ 9: 0]   LEDR, //LED is Low-Active

      ///////// Seg7 /////////
      output   [ 6: 0]   HEX0,
      output   [ 6: 0]   HEX1,
      output   [ 6: 0]   HEX2,
      output   [ 6: 0]   HEX3,
      output   [ 6: 0]   HEX4,
      output   [ 6: 0]   HEX5,

      ///////// SDRAM /////////
      output             DRAM_CLK,
      output             DRAM_CKE,
      output   [12: 0]   DRAM_ADDR,
      output   [ 1: 0]   DRAM_BA,
      inout    [31: 0]   DRAM_DQ,
      output             DRAM_CS_n,
      output             DRAM_WE_n,
      output             DRAM_CAS_n,
      output             DRAM_RAS_n,
      output   [ 3: 0]   DRAM_DQM,

      ///////// HDMI /////////
      inout              HDMI_LRCLK,
      inout              HDMI_MCLK,
      inout              HDMI_SCLK,
      output             HDMI_TX_CLK,
      output             HDMI_TX_HS,
      output             HDMI_TX_VS,
      output   [23: 0]   HDMI_TX_D,
      output             HDMI_TX_DE,
      input              HDMI_TX_INT,
      inout              HDMI_I2S0,

      ///////// I2C for HDMI and ADC /////////
      inout              FPGA_I2C_SCL,
      inout              FPGA_I2C_SDA,

      ///////// UART /////////
      output             FPGA_UART_TX,
      input              FPGA_UART_RX,

      ///////// GPIO /////////
      inout    [35: 0]   GPIO_D

);

// Wire definitions

// base wires
wire AUD_CTRL_CLK;
wire AUD_BCLK;
wire DAC_DACDAT;
wire AUD_DACLRCK;
wire reset_n;
wire V_locked, A_locked;
wire pll_12M288;
wire SYSTEM_50MHZ;
wire [7:0] vpg_r;
wire [7:0] vpg_g;
wire [7:0] vpg_b;
wire HDMI_READY;
wire ninit_done;

// Clock wires from VEDIO_PLL
wire vpg_pclk;        // 148.5 MHz — SDRAM controller, manager, UART
wire clk_sdram_148;   // 148.5 MHz, 180 degree phase — DRAM_CLK
wire clk_hdmi_74;     // 74.25 MHz — HDMI read port of dual clock data FIFOs

// PR2 UART wires
wire ar;
wire [7:0] rx_word;
wire new_rx_pulse;
wire [7:0] tx_word;
wire tx_start;
wire tx_busy;
wire tx_done;

// PR2 UART / SDRAM manager interface wires
wire [31:0] control_reg0, control_reg1, control_reg2, control_reg3;
wire uart_wr_addr_valid;
wire [23:0] uart_wr_addr;
wire uart_wr_data_valid;
wire [31:0] uart_wr_data;
wire uart_rd_addr_valid;
wire [23:0] uart_rd_addr;
wire uart_rd_data_valid;
wire [31:0] uart_rd_data;

// HDMI pixel output from sdram_mgr
wire [7:0] hdmi_pixel_r;
wire [7:0] hdmi_pixel_g;
wire [7:0] hdmi_pixel_b;
wire hdmi_pixel_valid;

// SDRAM controller interface wires
wire sdram_busy;
wire sdram_rd_req;
wire sdram_wr_req;
wire [23:0] sdram_addr;
wire [31:0] sdram_wr_data;
wire [31:0] sdram_rd_data;
wire sdram_rd_valid;
wire sdram_wr_next;

// Clock and Reset

// PR3 reset from ResetRelease IP (power-on reset sequencer)
assign reset_n = ~ninit_done;

ResetRelease ResetRelease_inst (
    .ninit_done (ninit_done)
);

// Active-low reset: KEY[0] gated with power-on reset
assign ar = KEY[0] & reset_n;

// 50 MHz kept only for I2C_HDMI_Config
assign SYSTEM_50MHZ = CLOCK0_50;

// SDRAM chip clock from PLL 180-degree output
assign DRAM_CLK = clk_sdram_148;

assign tx_done = ~tx_busy;

reg [10:0] wr_addr_count;
reg image_loaded_reg;
wire image_loaded;
assign image_loaded = image_loaded_reg;

always @(posedge vpg_pclk or negedge ar)
    if(~ar)
    begin
        wr_addr_count    <= 11'd0;
        image_loaded_reg <= 1'b0;
    end
    else if(uart_wr_addr_valid && !image_loaded_reg)
    begin
        if(wr_addr_count < 11'd1799)
            wr_addr_count <= wr_addr_count + 11'd1;
        else
            image_loaded_reg <= 1'b1;
    end

//PLLs

VEDIO_PLL u_VEDIO_PLL (
    .refclk   (CLOCK0_50),
    .outclk_0 (vpg_pclk),       // 148.5 MHz, 0 deg   -> SDRAM/UART system clock
    .outclk_1 (clk_sdram_148),  // 148.5 MHz, 5000 ps -> DRAM_CLK (180 degree)
    .outclk_2 (clk_hdmi_74),    // 74.25 MHz, 0 deg   -> HDMI read side of data FIFOs
    .locked   (V_locked),
    .rst      (~reset_n)
);

AUDIO_PLL u_AUDIO_PLL (
    .refclk   (CLOCK1_50),
    .outclk_0 (pll_12M288),
    .locked   (A_locked),
    .rst      (~reset_n)
);

//PR3 HDMI video pattern generator

assign HDMI_TX_D[23:16] = hdmi_pixel_valid ? hdmi_pixel_r : vpg_r;
assign HDMI_TX_D[15:8]  = hdmi_pixel_valid ? hdmi_pixel_g : vpg_g;
assign HDMI_TX_D[7:0]   = hdmi_pixel_valid ? hdmi_pixel_b : vpg_b;

vpg u_vpg (
    .vpg_pclk    (vpg_pclk),
    .reset_n     (reset_n),
    .vpg_de      (HDMI_TX_DE),
    .vpg_hs      (HDMI_TX_HS),
    .vpg_vs      (HDMI_TX_VS),
    .vpg_pclk_out(HDMI_TX_CLK),
    .vpg_r       (vpg_r),
    .vpg_g       (vpg_g),
    .vpg_b       (vpg_b)
);

//HDMI I2C configuration

I2C_HDMI_Config u_I2C_HDMI_Config (
    .iCLK       (SYSTEM_50MHZ),
    .iRST_N     (reset_n & KEY[0]),
    .I2C_SCLK   (FPGA_I2C_SCL),
    .I2C_SDAT   (FPGA_I2C_SDA),
    .HDMI_TX_INT(HDMI_TX_INT),
    .READY      (HDMI_READY)
);

//Audio

assign AUD_CTRL_CLK = pll_12M288;

AUDIO_DAC u_AUDIO_DAC (
    .oAUD_BCK   (AUD_BCLK),
    .oAUD_DATA  (DAC_DACDAT),
    .oAUD_LRCK  (AUD_DACLRCK),
    .iSrc_Select(2'b00),
    .iCLK_18_4  (AUD_CTRL_CLK),
    .iRST_N     (HDMI_READY)
);

assign HDMI_MCLK  = AUD_CTRL_CLK;
assign HDMI_SCLK  = AUD_BCLK;
assign HDMI_LRCLK = AUD_DACLRCK;
assign HDMI_I2S0  = KEY[3] ? 0 : DAC_DACDAT;

//clock heartbeat monitors

CLOCKMEM ckK0 (.RESET_n(1), .CLK(HDMI_TX_CLK),  .CLK_FREQ(148_500_000), .CK_1HZ(LEDR[0]));
CLOCKMEM ckK1 (.RESET_n(1), .CLK(AUD_DACLRCK),  .CLK_FREQ(     48_000), .CK_1HZ(LEDR[1]));
CLOCKMEM ckK2 (.RESET_n(1), .CLK(SYSTEM_50MHZ), .CLK_FREQ( 50_000_000), .CK_1HZ(LEDR[2]));
CLOCKMEM ckK3 (.RESET_n(1), .CLK(AUD_CTRL_CLK), .CLK_FREQ( 12_280_000), .CK_1HZ(LEDR[3]));

assign LEDR[4] = ~HDMI_READY;
assign LEDR[5] = ~V_locked;
assign LEDR[6] = ~A_locked;

assign LEDR[7] = ~new_rx_pulse;
assign LEDR[8] = ~tx_busy;
assign LEDR[9] = ~sdram_busy;

//UART modules

uart_tx uart_tx_inst (
    .ar      (ar),
    .clk     (vpg_pclk),
    .data    (tx_word),
    .tx_start(tx_start),
    .tx      (FPGA_UART_TX),
    .tx_busy (tx_busy)
);

uart_rx uart_rx_inst (
    .ar    (ar),
    .clk   (vpg_pclk),
    .rx    (FPGA_UART_RX),
    .data  (rx_word),
    .new_rx(new_rx_pulse)
);

uart_mgr mgr_inst (
    .ar                 (ar),
    .clk                (vpg_pclk),
    .new_rx             (new_rx_pulse),
    .tx_done            (tx_done),
    .tx_start           (tx_start),
    .rx_word            (rx_word),
    .tx_word            (tx_word),
    .control_reg0       (control_reg0),
    .control_reg1       (control_reg1),
    .control_reg2       (control_reg2),
    .control_reg3       (control_reg3),
    .sdram_wr_addr_valid(uart_wr_addr_valid),
    .sdram_wr_addr      (uart_wr_addr),
    .sdram_wr_data_valid(uart_wr_data_valid),
    .sdram_wr_data      (uart_wr_data),
    .sdram_rd_addr_valid(uart_rd_addr_valid),
    .sdram_rd_addr      (uart_rd_addr),
    .sdram_rd_data_valid(uart_rd_data_valid),
    .sdram_rd_data      (uart_rd_data)
);

// SDRAM manager

sdram_mgr sdram_mgr_inst (
    .ar              (ar),
    .clk             (vpg_pclk),
    .clk_hdmi        (vpg_pclk),
    .wr_addr_valid   (uart_wr_addr_valid),
    .wr_addr         (uart_wr_addr),
    .wr_data_valid   (uart_wr_data_valid),
    .wr_data         (uart_wr_data),
    .rd_addr_valid   (uart_rd_addr_valid),
    .rd_addr         (uart_rd_addr),
    .rd_data_valid   (uart_rd_data_valid),
    .rd_data         (uart_rd_data),
    .hdmi_vsync      (HDMI_TX_VS),
    .hdmi_hsync      (HDMI_TX_HS),
    .hdmi_de         (HDMI_TX_DE),
    .image_loaded    (image_loaded),
    .hdmi_pixel_r    (hdmi_pixel_r),
    .hdmi_pixel_g    (hdmi_pixel_g),
    .hdmi_pixel_b    (hdmi_pixel_b),
    .hdmi_pixel_valid(hdmi_pixel_valid),
    .sdram_busy      (sdram_busy),
    .sdram_rd_req    (sdram_rd_req),
    .sdram_wr_req    (sdram_wr_req),
    .sdram_addr      (sdram_addr),
    .sdram_wr_data   (sdram_wr_data),
    .sdram_rd_data   (sdram_rd_data),
    .sdram_rd_valid  (sdram_rd_valid),
    .sdram_wr_next   (sdram_wr_next)
);

// SDRAM controller v3

sdram_controller_32bit sdram_ctrl_inst (
    .clk          (vpg_pclk),
    .rst_n        (ar),
    .start_refresh(HDMI_TX_HS),   // hsync triggers refresh bursts
    .num_words    (10'd512),       
    .wr_req       (sdram_wr_req),
    .rd_req       (sdram_rd_req),
    .addr         (sdram_addr),
    .wr_data      (sdram_wr_data),
    .rd_data      (sdram_rd_data),
    .rd_valid     (sdram_rd_valid),
    .busy         (sdram_busy),
    .wr_next      (sdram_wr_next),
    .sdram_a      (DRAM_ADDR),
    .sdram_ba     (DRAM_BA),
    .sdram_dq     (DRAM_DQ),
    .sdram_dqm    (DRAM_DQM),
    .sdram_cke    (DRAM_CKE),
    .sdram_cs_n   (DRAM_CS_n),
    .sdram_ras_n  (DRAM_RAS_n),
    .sdram_cas_n  (DRAM_CAS_n),
    .sdram_we_n   (DRAM_WE_n)
);


// Seven segment displays

sevseg_dec hex0_inst (.x_in(control_reg0[3:0]),   .segs(HEX0));
sevseg_dec hex1_inst (.x_in(control_reg0[7:4]),   .segs(HEX1));
sevseg_dec hex2_inst (.x_in(control_reg0[11:8]),  .segs(HEX2));
sevseg_dec hex3_inst (.x_in(control_reg0[15:12]), .segs(HEX3));
sevseg_dec hex4_inst (.x_in(control_reg0[19:16]), .segs(HEX4));
sevseg_dec hex5_inst (.x_in(control_reg0[23:20]), .segs(HEX5));

endmodule