//sdram_mgr.v
//ECE641 Project 3
//SDRAM Manager with dual-clock FIFOs, 512 word page burst FSM,
//and HDMI read FSM for 1080p pixel streaming at 148.5 MHz

`timescale 1 ns / 1 ns

module sdram_mgr(ar, clk, clk_hdmi,
				wr_addr_valid, wr_addr, wr_data_valid, wr_data,
				rd_addr_valid, rd_addr, rd_data_valid, rd_data,
				hdmi_vsync, hdmi_hsync, hdmi_de, image_loaded,
				hdmi_pixel_r, hdmi_pixel_g, hdmi_pixel_b, hdmi_pixel_valid,
				sdram_busy, sdram_rd_req, sdram_wr_req, sdram_addr,
				sdram_wr_data, sdram_rd_data, sdram_rd_valid, sdram_wr_next);

	input ar;
	input clk;       // 148.5 MHz - all FIFOs, main FSM, and HDMI FSM
	input clk_hdmi;  // 74.25 MHz - kept as port for compatibility, not used internally

	// UART write interface
	input wr_addr_valid;
	input [23:0] wr_addr;
	input wr_data_valid;
	input [31:0] wr_data;

	// UART read interface
	input rd_addr_valid;
	input [23:0] rd_addr;
	output reg rd_data_valid;
	output reg [31:0] rd_data;

	// HDMI sync and pixel output (clk domain - 148.5 MHz)
	input hdmi_vsync;
	input hdmi_hsync;
	input hdmi_de;
	input image_loaded;    // goes high after bulk write completes
	output reg [7:0] hdmi_pixel_r;
	output reg [7:0] hdmi_pixel_g;
	output reg [7:0] hdmi_pixel_b;
	output reg hdmi_pixel_valid;

	// SDRAM controller interface
	input sdram_busy;
	output reg sdram_rd_req;
	output reg sdram_wr_req;
	output reg [23:0] sdram_addr;
	output reg [31:0] sdram_wr_data;
	input [31:0] sdram_rd_data;
	input sdram_rd_valid;
	input sdram_wr_next;

	parameter [2:0] Idle        = 3'd0, Check_Write = 3'd1, Start_Write = 3'd2,
					Write_Burst = 3'd3, Check_Read  = 3'd4, Start_Read  = 3'd5,
					Read_Burst  = 3'd6;

	reg [2:0]  cs;
	reg [9:0]  burst_cnt;

	// FIFO signals - Write Address
	wire wr_addr_fifo_wrreq;
	reg wr_addr_fifo_rdreq;
	wire [23:0] wr_addr_fifo_q;
	wire wr_addr_fifo_wrempty;
	wire wr_addr_fifo_wrfull;
	wire wr_addr_fifo_rdempty;
	wire wr_addr_fifo_rdfull;

	// FIFO signals - Write Data
	wire wr_data_fifo_wrreq;
	reg wr_data_fifo_rdreq;
	wire [31:0] wr_data_fifo_q;
	wire wr_data_fifo_wrempty;
	wire wr_data_fifo_wrfull;
	wire wr_data_fifo_rdempty;
	wire [10:0] wr_data_fifo_usedw;

	// FIFO signals - Read Address
	wire rd_addr_fifo_wrreq;
	reg rd_addr_fifo_rdreq;
	wire [23:0] rd_addr_fifo_q;
	wire rd_addr_fifo_wrempty;
	wire rd_addr_fifo_wrfull;
	wire rd_addr_fifo_rdempty;
	wire rd_addr_fifo_rdfull;

	// FIFO signals - Read Data
	reg rd_data_fifo_wrreq;
	reg rd_data_fifo_rdreq;
	wire [31:0] rd_data_fifo_q;
	wire rd_data_fifo_wrempty;
	wire rd_data_fifo_wrfull;
	wire rd_data_fifo_rdempty;
	wire [10:0] rd_data_fifo_usedw;

	// HDMI FSM signals
	reg hdmi_rd_addr_valid;
	reg [23:0] hdmi_rd_addr;

	// rd_addr_fifo: UART or HDMI FSM can write, SDRAM FSM reads
	assign wr_addr_fifo_wrreq = wr_addr_valid;
	assign wr_data_fifo_wrreq = wr_data_valid;
	assign rd_addr_fifo_wrreq = rd_addr_valid | hdmi_rd_addr_valid;

	// Mux rd_addr: HDMI takes priority over UART for pixel streaming
	wire [23:0] rd_addr_mux;
	assign rd_addr_mux = hdmi_rd_addr_valid ? hdmi_rd_addr : rd_addr;

	// Write address FIFO - all clk (148.5 MHz)
	fifo_24_dc wr_addr_fifo(
		.wrclk  (clk),
		.rdclk  (clk),
		.aclr   (~ar),
		.wrreq  (wr_addr_fifo_wrreq),
		.rdreq  (wr_addr_fifo_rdreq),
		.data   (wr_addr),
		.q      (wr_addr_fifo_q),
		.wrempty(wr_addr_fifo_wrempty),
		.wrfull (wr_addr_fifo_wrfull),
		.rdempty(wr_addr_fifo_rdempty),
		.rdfull (wr_addr_fifo_rdfull)
	);

	// Write data FIFO - all clk (148.5 MHz)
	fifo_32_dc wr_data_fifo(
		.wrclk  (clk),
		.rdclk  (clk),
		.aclr   (~ar),
		.wrreq  (wr_data_fifo_wrreq),
		.rdreq  (wr_data_fifo_rdreq),
		.data   (wr_data),
		.q      (wr_data_fifo_q),
		.wrempty(wr_data_fifo_wrempty),
		.wrfull (wr_data_fifo_wrfull),
		.rdempty(wr_data_fifo_rdempty),
		.rdfull (),
		.usedw  (wr_data_fifo_usedw)
	);

	// Read address FIFO - all clk (148.5 MHz)
	fifo_24_dc rd_addr_fifo(
		.wrclk  (clk),
		.rdclk  (clk),
		.aclr   (~ar),
		.wrreq  (rd_addr_fifo_wrreq),
		.rdreq  (rd_addr_fifo_rdreq),
		.data   (rd_addr_mux),
		.q      (rd_addr_fifo_q),
		.wrempty(rd_addr_fifo_wrempty),
		.wrfull (rd_addr_fifo_wrfull),
		.rdempty(rd_addr_fifo_rdempty),
		.rdfull (rd_addr_fifo_rdfull)
	);

	// Read data FIFO - all clk (148.5 MHz)
	// Both sides run at 148.5 MHz since 1080p pixel clock is 148.5 MHz
	fifo_32_dc rd_data_fifo(
		.wrclk  (clk),
		.rdclk  (clk),
		.aclr   (~ar),
		.wrreq  (rd_data_fifo_wrreq),
		.rdreq  (rd_data_fifo_rdreq),
		.data   (sdram_rd_data),
		.q      (rd_data_fifo_q),
		.wrempty(rd_data_fifo_wrempty),
		.wrfull (rd_data_fifo_wrfull),
		.rdempty(rd_data_fifo_rdempty),
		.rdfull (),
		.usedw  (rd_data_fifo_usedw)
	);

	// UART read data output
	always @(posedge clk or negedge ar)
		if(~ar)
		begin
			rd_data       <= 32'd0;
			rd_data_valid <= 1'b0;
		end
		else
		begin
			rd_data_valid <= 1'b0;
			if(rd_addr_valid && !rd_data_fifo_rdempty)
			begin
				rd_data       <= rd_data_fifo_q;
				rd_data_valid <= 1'b1;
			end
		end

	// 720p image displayed in top-left corner of 1080p frame
	parameter BURSTS_PER_FRAME  = 12'd1800;   // 921600 / 512
	parameter FRAME_START_ADDR  = 24'h000000;
	parameter IMAGE_WIDTH       = 11'd1280;    // pixels per image line
	parameter IMAGE_HEIGHT      = 11'd720;     // image lines per frame

	// Vsync and hsync edge detection
	reg vsync_prev;
	reg hsync_prev;
	wire vsync_posedge;
	wire hsync_posedge;

	always @(posedge clk or negedge ar)
		if(~ar)
			vsync_prev <= 1'b0;
		else
			vsync_prev <= hdmi_vsync;

	assign vsync_posedge = hdmi_vsync & ~vsync_prev;

	parameter [1:0] HDMI_Idle    = 2'd0,
	                HDMI_Prefill = 2'd1,
	                HDMI_Stream  = 2'd2;

	reg [1:0]  hdmi_cs;
	reg [23:0] hdmi_frame_addr;
	reg [11:0] hdmi_burst_count;

	// Image pixel and line counters - track position within the FIFO data
	/
	reg [10:0] img_pixel_cnt;  
	reg [9:0]  img_line_cnt;   
	reg        img_done;        
	reg        img_line_active; 
	reg        img_draining;     
	reg [8:0]  img_drain_cnt;  

	always @(posedge clk or negedge ar)
		if(~ar)
		begin
			vsync_prev <= 1'b0;
			hsync_prev <= 1'b0;
		end
		else
		begin
			vsync_prev <= hdmi_vsync;
			hsync_prev <= hdmi_hsync;
		end

	assign vsync_posedge = hdmi_vsync & ~vsync_prev;
	assign hsync_posedge = hdmi_hsync & ~hsync_prev;



	always @(posedge clk or negedge ar)
		if(~ar)
		begin
			hdmi_cs            <= HDMI_Idle;
			hdmi_frame_addr    <= FRAME_START_ADDR;
			hdmi_burst_count   <= 12'd0;
			hdmi_rd_addr       <= 24'd0;
			hdmi_rd_addr_valid <= 1'b0;
			hdmi_pixel_r       <= 8'd0;
			hdmi_pixel_g       <= 8'd0;
			hdmi_pixel_b       <= 8'd0;
			hdmi_pixel_valid   <= 1'b0;
			rd_data_fifo_rdreq <= 1'b0;
			img_pixel_cnt      <= 11'd0;
			img_line_cnt       <= 10'd0;
			img_done           <= 1'b0;
			img_line_active    <= 1'b0;
			img_draining       <= 1'b0;
			img_drain_cnt      <= 9'd0;
		end
		else
		begin
			hdmi_rd_addr_valid <= 1'b0;
			hdmi_pixel_valid   <= 1'b0;
			rd_data_fifo_rdreq <= 1'b0;

			case(hdmi_cs)

				HDMI_Idle:
				begin
					if(vsync_posedge && image_loaded)
					begin
						hdmi_frame_addr  <= FRAME_START_ADDR;
						hdmi_burst_count <= 12'd0;
						hdmi_cs          <= HDMI_Prefill;
					end
				end

				HDMI_Prefill:
				begin
					if(vsync_posedge)
					begin
						hdmi_frame_addr  <= FRAME_START_ADDR;
						hdmi_burst_count <= 12'd0;
						img_pixel_cnt    <= 11'd0;
						img_line_cnt     <= 10'd0;
						img_done         <= 1'b0;
						img_line_active  <= 1'b0;
						img_draining     <= 1'b0;
						img_drain_cnt    <= 9'd0;
					end
					else if(!rd_addr_fifo_wrfull && hdmi_burst_count < BURSTS_PER_FRAME)
					begin
						hdmi_rd_addr       <= hdmi_frame_addr;
						hdmi_rd_addr_valid <= 1'b1;
						hdmi_frame_addr    <= hdmi_frame_addr + 24'd512;
						hdmi_burst_count   <= hdmi_burst_count + 12'd1;
					end

					if(rd_data_fifo_usedw >= 11'd512)
						hdmi_cs <= HDMI_Stream;
				end

				HDMI_Stream:
				begin
					if(vsync_posedge)
					begin
						hdmi_frame_addr  <= FRAME_START_ADDR;
						hdmi_burst_count <= 12'd0;
						img_pixel_cnt    <= 11'd0;
						img_line_cnt     <= 10'd0;
						img_done         <= 1'b0;
						img_line_active  <= 1'b0;
						img_draining     <= 1'b0;
						img_drain_cnt    <= 9'd0;
						hdmi_cs          <= HDMI_Prefill;
					end
					else
					begin
						if(hsync_posedge && img_line_cnt < IMAGE_HEIGHT && !img_done)
						begin
							img_line_active <= 1'b1;
							img_draining    <= 1'b0;
							img_drain_cnt   <= 9'd0;
						end

						if(hdmi_de && img_line_active && !img_done && !rd_data_fifo_rdempty)
						begin
							hdmi_pixel_r       <= rd_data_fifo_q[31:24];
							hdmi_pixel_g       <= rd_data_fifo_q[23:16];
							hdmi_pixel_b       <= rd_data_fifo_q[15:8];
							hdmi_pixel_valid   <= 1'b1;
							rd_data_fifo_rdreq <= 1'b1;

							if(img_pixel_cnt < IMAGE_WIDTH - 1)
							begin
								img_pixel_cnt <= img_pixel_cnt + 11'd1;
							end
							else
							begin
								img_pixel_cnt   <= 11'd0;
								img_line_active <= 1'b0;
								img_draining    <= 1'b1;
								img_drain_cnt   <= 9'd0;
								if(img_line_cnt < IMAGE_HEIGHT - 1)
									img_line_cnt <= img_line_cnt + 10'd1;
								else
									img_done <= 1'b1;
							end
						end

						if(img_draining && !rd_data_fifo_rdempty)
						begin
							rd_data_fifo_rdreq <= 1'b1;
							if(img_drain_cnt < 9'd255)
								img_drain_cnt <= img_drain_cnt + 9'd1;
							else
								img_draining <= 1'b0;
						end

						if(!rd_addr_fifo_wrfull && hdmi_burst_count < BURSTS_PER_FRAME)
						begin
							hdmi_rd_addr       <= hdmi_frame_addr;
							hdmi_rd_addr_valid <= 1'b1;
							hdmi_frame_addr    <= hdmi_frame_addr + 24'd512;
							hdmi_burst_count   <= hdmi_burst_count + 12'd1;
						end
					end
				end

				default:
					hdmi_cs <= HDMI_Idle;

			endcase
		end

	// Main SDRAM FSM (clk - 148.5 MHz)
	always @(negedge ar or posedge clk)
		if(~ar)
		begin
			cs                 <= Idle;
			sdram_rd_req       <= 1'b0;
			sdram_wr_req       <= 1'b0;
			sdram_addr         <= 24'd0;
			sdram_wr_data      <= 32'd0;
			burst_cnt          <= 10'd0;
			wr_addr_fifo_rdreq <= 1'b0;
			wr_data_fifo_rdreq <= 1'b0;
			rd_addr_fifo_rdreq <= 1'b0;
			rd_data_fifo_wrreq <= 1'b0;
		end
		else
		begin
			sdram_rd_req       <= 1'b0;
			sdram_wr_req       <= 1'b0;
			wr_addr_fifo_rdreq <= 1'b0;
			wr_data_fifo_rdreq <= 1'b0;
			rd_addr_fifo_rdreq <= 1'b0;
			rd_data_fifo_wrreq <= 1'b0;

			case(cs)
				Idle:
				begin
					burst_cnt <= 10'd0;
					if(!sdram_busy)
					begin
						if(!wr_addr_fifo_rdempty)
							cs <= Check_Write;
						else if(!rd_addr_fifo_rdempty)
							cs <= Check_Read;
					end
				end

				Check_Write:
				begin
					if(wr_data_fifo_usedw >= 11'd512)
						cs <= Start_Write;
					else
					begin
						if(!rd_addr_fifo_rdempty)
							cs <= Check_Read;
						else
							cs <= Idle;
					end
				end

				Start_Write:
				begin
					sdram_addr         <= wr_addr_fifo_q;
					wr_addr_fifo_rdreq <= 1'b1;
					sdram_wr_req       <= 1'b1;
					burst_cnt          <= 10'd0;
					cs                 <= Write_Burst;
				end

				Write_Burst:
				begin
					sdram_wr_data <= wr_data_fifo_q;

					if(sdram_wr_next)
					begin
						wr_data_fifo_rdreq <= 1'b1;

						if(burst_cnt < 10'd511)
							burst_cnt <= burst_cnt + 10'd1;
						else
							cs <= Idle;
					end
				end

				Check_Read:
				begin
					if(!rd_data_fifo_wrfull)
						cs <= Start_Read;
				end

				Start_Read:
				begin
					sdram_addr         <= rd_addr_fifo_q;
					rd_addr_fifo_rdreq <= 1'b1;
					sdram_rd_req       <= 1'b1;
					burst_cnt          <= 10'd0;
					cs                 <= Read_Burst;
				end

				Read_Burst:
				begin
					if(sdram_rd_valid)
					begin
						rd_data_fifo_wrreq <= 1'b1;

						if(burst_cnt < 10'd511)
							burst_cnt <= burst_cnt + 10'd1;
						else
							cs <= Idle;
					end
				end

				default:
					cs <= Idle;

			endcase
		end

endmodule