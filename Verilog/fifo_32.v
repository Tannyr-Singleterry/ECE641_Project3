//fifo_32.v
//ECE641 Project 2
//32-bit FIFO for data storage with usedw count

`timescale 1 ns / 1 ns

module fifo_32(clk, aclr, wrreq, rdreq, data, q, empty, full, usedw);

	input clk;
	input aclr;
	input wrreq;
	input rdreq;
	input [31:0] data;
	output [31:0] q;
	output empty;
	output full;
	output [4:0] usedw;
	
	parameter DEPTH = 32;
	
	reg [31:0] mem [0:DEPTH-1];
	reg [5:0] wr_ptr;
	reg [5:0] rd_ptr;
	reg [5:0] count;
	
	assign q = mem[rd_ptr[4:0]];
	assign empty = (count == 6'd0);
	assign full = (count == DEPTH);
	assign usedw = count[4:0];
	
	always @(posedge clk or posedge aclr)
		if(aclr)
		begin
			wr_ptr <= 6'd0;
			rd_ptr <= 6'd0;
			count <= 6'd0;
		end
		else
		begin
			if(wrreq && !full)
			begin
				mem[wr_ptr[4:0]] <= data;
				wr_ptr <= wr_ptr + 6'd1;
				if(!rdreq)
					count <= count + 6'd1;
			end
			
			if(rdreq && !empty)
			begin
				rd_ptr <= rd_ptr + 6'd1;
				if(!wrreq)
					count <= count - 6'd1;
			end
		end

endmodule
