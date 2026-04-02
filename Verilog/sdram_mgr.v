//sdram_mgr.v
//ECE641 Project 2
//SDRAM Manager with FIFOs and FSM

`timescale 1 ns / 1 ns

module sdram_mgr(ar, clk, 
				wr_addr_valid, wr_addr, wr_data_valid, wr_data,
				rd_addr_valid, rd_addr, rd_data_valid, rd_data,
				sdram_busy, sdram_rd_req, sdram_wr_req, sdram_addr,
				sdram_wr_data, sdram_rd_data, sdram_rd_valid, sdram_wr_next);
				
	input ar;
	input clk;
	input wr_addr_valid;
	input [23:0] wr_addr;
	input wr_data_valid;
	input [31:0] wr_data;
	input rd_addr_valid;
	input [23:0] rd_addr;
	output reg rd_data_valid;
	output reg [31:0] rd_data;
	input sdram_busy;
	output reg sdram_rd_req;
	output reg sdram_wr_req;
	output reg [23:0] sdram_addr;
	output reg [31:0] sdram_wr_data;
	input [31:0] sdram_rd_data;
	input sdram_rd_valid;
	input sdram_wr_next;
	
	parameter [2:0] Idle = 3'd0, Check_Write = 3'd1, Start_Write = 3'd2, 
					Write_Burst = 3'd3, Check_Read = 3'd4, Start_Read = 3'd5,
					Read_Burst = 3'd6;
	
	reg [2:0] cs;
	reg [2:0] burst_cnt;
	
	// FIFO signals - Write Address
	wire wr_addr_fifo_wrreq;
	reg wr_addr_fifo_rdreq;
	wire [23:0] wr_addr_fifo_q;
	wire wr_addr_fifo_empty;
	wire wr_addr_fifo_full;
	
	// FIFO signals - Write Data
	wire wr_data_fifo_wrreq;
	reg wr_data_fifo_rdreq;
	wire [31:0] wr_data_fifo_q;
	wire wr_data_fifo_empty;
	wire wr_data_fifo_full;
	wire [4:0] wr_data_fifo_usedw;
	
	// FIFO signals - Read Address
	wire rd_addr_fifo_wrreq;
	reg rd_addr_fifo_rdreq;
	wire [23:0] rd_addr_fifo_q;
	wire rd_addr_fifo_empty;
	wire rd_addr_fifo_full;
	
	// FIFO signals - Read Data
	reg rd_data_fifo_wrreq;
	reg rd_data_fifo_rdreq;
	wire [31:0] rd_data_fifo_q;
	wire rd_data_fifo_empty;
	wire rd_data_fifo_full;
	
	assign wr_addr_fifo_wrreq = wr_addr_valid;
	assign wr_data_fifo_wrreq = wr_data_valid;
	assign rd_addr_fifo_wrreq = rd_addr_valid;
	
	// Instantiate FIFOs
	fifo_24 wr_addr_fifo(
		.clk(clk),
		.aclr(~ar),
		.wrreq(wr_addr_fifo_wrreq),
		.rdreq(wr_addr_fifo_rdreq),
		.data(wr_addr),
		.q(wr_addr_fifo_q),
		.empty(wr_addr_fifo_empty),
		.full(wr_addr_fifo_full)
	);
	
	fifo_32 wr_data_fifo(
		.clk(clk),
		.aclr(~ar),
		.wrreq(wr_data_fifo_wrreq),
		.rdreq(wr_data_fifo_rdreq),
		.data(wr_data),
		.q(wr_data_fifo_q),
		.empty(wr_data_fifo_empty),
		.full(wr_data_fifo_full),
		.usedw(wr_data_fifo_usedw)
	);
	
	fifo_24 rd_addr_fifo(
		.clk(clk),
		.aclr(~ar),
		.wrreq(rd_addr_fifo_wrreq),
		.rdreq(rd_addr_fifo_rdreq),
		.data(rd_addr),
		.q(rd_addr_fifo_q),
		.empty(rd_addr_fifo_empty),
		.full(rd_addr_fifo_full)
	);
	
	fifo_32 rd_data_fifo(
		.clk(clk),
		.aclr(~ar),
		.wrreq(rd_data_fifo_wrreq),
		.rdreq(rd_data_fifo_rdreq),
		.data(sdram_rd_data),
		.q(rd_data_fifo_q),
		.empty(rd_data_fifo_empty),
		.full(rd_data_fifo_full),
		.usedw()
	);
	
	// Connect UART reads from read data FIFO to uart_mgr
	always @(posedge clk or negedge ar)
		if(~ar)
		begin
			rd_data <= 32'd0;
			rd_data_valid <= 1'b0;
			rd_data_fifo_rdreq <= 1'b0;
		end
		else
		begin
			rd_data_fifo_rdreq <= 1'b0;
			rd_data_valid <= 1'b0;
			
			if(!rd_data_fifo_empty)
			begin
				rd_data <= rd_data_fifo_q;
				rd_data_valid <= 1'b1;
				rd_data_fifo_rdreq <= 1'b1;
			end
		end
	
	// Main FSM
	always @(negedge ar or posedge clk)
		if(~ar)
		begin
			cs <= Idle;
			sdram_rd_req <= 1'b0;
			sdram_wr_req <= 1'b0;
			sdram_addr <= 24'd0;
			sdram_wr_data <= 32'd0;
			burst_cnt <= 3'd0;
			wr_addr_fifo_rdreq <= 1'b0;
			wr_data_fifo_rdreq <= 1'b0;
			rd_addr_fifo_rdreq <= 1'b0;
			rd_data_fifo_wrreq <= 1'b0;
		end
		else
		begin
			// Default: clear one-shot signals
			sdram_rd_req <= 1'b0;
			sdram_wr_req <= 1'b0;
			wr_addr_fifo_rdreq <= 1'b0;
			wr_data_fifo_rdreq <= 1'b0;
			rd_addr_fifo_rdreq <= 1'b0;
			rd_data_fifo_wrreq <= 1'b0;
			
			case(cs)
				Idle:
				begin
					burst_cnt <= 3'd0;
					if(!sdram_busy)
					begin
						if(!wr_addr_fifo_empty)
							cs <= Check_Write;
						else if(!rd_addr_fifo_empty)
							cs <= Check_Read;
					end
				end
				
				Check_Write:
				begin
					if(wr_data_fifo_usedw >= 5'd8)
						cs <= Start_Write;
					else
					begin
						if(!rd_addr_fifo_empty)
							cs <= Check_Read;
						else
							cs <= Idle;
					end
				end
				
				Start_Write:
				begin
					sdram_addr <= wr_addr_fifo_q;
					wr_addr_fifo_rdreq <= 1'b1;
					sdram_wr_req <= 1'b1;
					burst_cnt <= 3'd0;
					cs <= Write_Burst;
				end
				
				Write_Burst:
				begin
					sdram_wr_data <= wr_data_fifo_q;
					
					if(sdram_wr_next)
					begin
						wr_data_fifo_rdreq <= 1'b1;
						
						if(burst_cnt < 3'd7)
							burst_cnt <= burst_cnt + 3'd1;
						else
							cs <= Idle;
					end
				end
				
				Check_Read:
				begin
					if(!rd_data_fifo_full)
						cs <= Start_Read;
					else
						cs <= Idle;
				end
				
				Start_Read:
				begin
					sdram_addr <= rd_addr_fifo_q;
					rd_addr_fifo_rdreq <= 1'b1;
					sdram_rd_req <= 1'b1;
					burst_cnt <= 3'd0;
					cs <= Read_Burst;
				end
				
				Read_Burst:
				begin
					if(sdram_rd_valid)
					begin
						rd_data_fifo_wrreq <= 1'b1;
						
						if(burst_cnt < 3'd7)
							burst_cnt <= burst_cnt + 3'd1;
						else
							cs <= Idle;
					end
				end
				
				default:
					cs <= Idle;
					
			endcase
		end

endmodule