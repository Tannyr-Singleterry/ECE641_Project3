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
//Date:  Mon Jun  2 00:32:49 2025
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
//----LED off device
assign LEDR[9:7] = 3'h7; 

//----HEX off device
assign HEX0 =7'h7f;
assign HEX1 =7'h7f;
assign HEX2 =7'h7f;
assign HEX3 =7'h7f;
assign HEX4 =7'h7f;
assign HEX5 =7'h7f;

//----SDRAM off
assign DRAM_DQ   =32'hzzzz_zzzzz;
assign DRAM_CS_n =1'b1;
assign DRAM_WE_n =1'b1;
assign DRAM_CAS_n=1'b1;
assign DRAM_RAS_n=1'b1;
assign DRAM_DQM  =4'b1111;

//=======================================================
//  wire define
//=======================================================
wire AUD_CTRL_CLK ;
wire AUD_BCLK   ;
wire DAC_DACDAT ;
wire AUD_DACLRCK; 
wire reset_n;
wire  V_locked ,A_locked ;
wire  pll_12M288; 
wire  SYSTEM_50MHZ;
wire [7:0] vpg_r;
wire [7:0] vpg_g;
wire [7:0] vpg_b;				
wire HDMI_READY ;
wire HDMI_I2C_SCLK ; 
//=======================================================
//  Structural coding
//=======================================================
//--RESET 	
assign reset_n = ~ninit_done;	
//---INIT RESET 
wire ninit_done;
	ResetRelease ResetRelease_inst (
		.ninit_done (ninit_done)  
	);
//-- PLL LOCK
assign LEDR[5] = ~V_locked	;
assign LEDR[6] = ~A_locked	;

//-- HDMI SET READY	
assign LEDR[4] = ~HDMI_READY	 ;

//-----heart ----
CLOCKMEM  ckK0( .RESET_n(1), .CLK(HDMI_TX_CLK    ) ,.CLK_FREQ ( 148_500_000 )  ,.CK_1HZ  (LEDR[0] ) ) ;
CLOCKMEM  ckK1( .RESET_n(1), .CLK(AUD_DACLRCK    ) ,.CLK_FREQ (      48_000 )  ,.CK_1HZ  (LEDR[1] ) ) ;
CLOCKMEM  ckK2( .RESET_n(1), .CLK(SYSTEM_50MHZ   ) ,.CLK_FREQ (  50_000_000 )  ,.CK_1HZ  (LEDR[2] ) ) ;
CLOCKMEM  ckK3( .RESET_n(1), .CLK(AUD_CTRL_CLK   ) ,.CLK_FREQ (  12_280_000 )  ,.CK_1HZ  (LEDR[3] ) ) ;

//---AV PLL 

VEDIO_PLL u_VEDIO_PLL(
    .refclk       (CLOCK0_50     ),
    .outclk_0     (vpg_pclk      ),//148.5MHZ
    .locked       (V_locked      ),
	 .rst          (~reset_n      )
);

AUDIO_PLL u_AUDIO_PLL(
    .refclk       (CLOCK1_50     ),
    .outclk_0     (pll_12M288    ),//12.288136Mhz
    .locked       (A_locked     ),
	 .rst          (~reset_n      )
);



assign SYSTEM_50MHZ = CLOCK0_50;//
 
assign HDMI_TX_D[23:16]	=	vpg_r;
assign HDMI_TX_D[15:8] 	=	vpg_g;
assign HDMI_TX_D[7:0]  	=	vpg_b;

//--HDMI timing generater & //pattern generator
vpg	u_vpg (
	.vpg_pclk    (vpg_pclk   ),//vedio clock input
	.reset_n     (reset_n    ),    
	.vpg_de      (HDMI_TX_DE ),
	.vpg_hs      (HDMI_TX_HS ),
	.vpg_vs      (HDMI_TX_VS ),
	.vpg_pclk_out(HDMI_TX_CLK),
	.vpg_r       (vpg_r),
	.vpg_g       (vpg_g),
	.vpg_b       (vpg_b)
	);
								
//--  HDMI I2C	SETTING
I2C_HDMI_Config u_I2C_HDMI_Config (
	              .iCLK       (SYSTEM_50MHZ  ),
	              .iRST_N     (reset_n & KEY[0]),
	              .I2C_SCLK   (FPGA_I2C_SCL  ),
	              .I2C_SDAT   (FPGA_I2C_SDA  ),
	              .HDMI_TX_INT(HDMI_TX_INT   ),
	              .READY      (HDMI_READY    ) 	
	            );
			



//---Audio Master L/RCLK , BCK ,DATA  generater 

assign AUD_CTRL_CLK =pll_12M288;

AUDIO_DAC 	u_AUDIO_DAC	(	//	Audio Side
					.oAUD_BCK       (AUD_BCLK        ),
					.oAUD_DATA      (DAC_DACDAT      ),
					.oAUD_LRCK      (AUD_DACLRCK     ),
					//	Control Signals
					.iSrc_Select    (2'b00           ),
			      .iCLK_18_4      (AUD_CTRL_CLK    ),//12.288000MHz --12.288136Mhz
					.iRST_N         (HDMI_READY      )
					);
										
// HDMI I2S out
assign HDMI_MCLK  = AUD_CTRL_CLK;
assign HDMI_SCLK  = AUD_BCLK     ;
assign HDMI_LRCLK = AUD_DACLRCK  ;	

//--key-in KEY3 ,HDMI out 1k sin-tone	
assign HDMI_I2S0 = KEY[3]? 0 : DAC_DACDAT	;

endmodule
