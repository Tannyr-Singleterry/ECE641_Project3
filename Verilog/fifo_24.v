//fifo_24.v
//ECE641 Project 2
//24-bit FIFO for address storage

`timescale 1 ns / 1 ns

module fifo_24(clk, aclr, wrreq, rdreq, data, q, empty, full);

	input clk;
	input aclr;
	input wrreq;
	input rdreq;
	input [23:0] data;
	output [23:0] q;
	output empty;
	output full;
	
	parameter DEPTH = 16;
	
	reg [23:0] mem [0:DEPTH-1];
	reg [4:0] wr_ptr;
	reg [4:0] rd_ptr;
	reg [4:0] count;
	
	assign q = mem[rd_ptr[3:0]];
	assign empty = (count == 5'd0);
	assign full = (count == DEPTH);
	
	always @(posedge clk or posedge aclr)
		if(aclr)
		begin
			wr_ptr <= 5'd0;
			rd_ptr <= 5'd0;
			count <= 5'd0;
		end
		else
		begin
			if(wrreq && !full)
			begin
				mem[wr_ptr[3:0]] <= data;
				wr_ptr <= wr_ptr + 5'd1;
				if(!rdreq)
					count <= count + 5'd1;
			end
			
			if(rdreq && !empty)
			begin
				rd_ptr <= rd_ptr + 5'd1;
				if(!wrreq)
					count <= count - 5'd1;
			end
		end

endmodule
