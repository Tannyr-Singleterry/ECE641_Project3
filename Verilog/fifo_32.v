//fifo_32_dc.v
//ECE641 Project 3
//Dual-clock 32-bit FIFO for data storage
//Write clock: 148.5 MHz (SDRAM manager side)

`timescale 1 ns / 1 ns

module fifo_32_dc(wrclk, rdclk, aclr, wrreq, rdreq, data, q, wrempty, wrfull, rdempty, rdfull, usedw);
	input wrclk;
	input rdclk;
	input aclr;
	input wrreq;
	input rdreq;
	input [31:0] data;
	output [31:0] q;
	output wrempty;
	output wrfull;
	output rdempty;
	output rdfull;
	output [10:0] usedw; //Number of words currently stored. 

	parameter DEPTH = 1024;
	parameter AW    = 10;

	reg [31:0] mem [0:DEPTH-1];

	// Write side pointers
	reg [AW:0] wr_ptr;
	reg [AW:0] wr_ptr_gray;

	// Read side pointers
	reg [AW:0] rd_ptr;
	reg [AW:0] rd_ptr_gray;

	// Synchronizers for gray code
	reg [AW:0] wr_ptr_gray_s1, wr_ptr_gray_s2;
	reg [AW:0] rd_ptr_gray_s1, rd_ptr_gray_s2;

	//Converts binary to Gray code so only one bit changes per increment
	//mkaing easier to synch clock domains
	function [AW:0] bin2gray;
		input [AW:0] b;
		begin
			bin2gray = b ^ (b >> 1);
		end
	endfunction
	
	//Converts gray code to binary.
	function [AW:0] gray2bin;
		input [AW:0] g;
		integer i;
		reg [AW:0] b;
		begin
			b[AW] = g[AW];
			for (i = AW-1; i >= 0; i = i - 1)
				b[i] = b[i+1] ^ g[i];
			gray2bin = b;
		end
	endfunction

	// Write port
	always @(posedge wrclk or posedge aclr)
		if(aclr)
		begin
			wr_ptr      <= 0;
			wr_ptr_gray <= 0;
		end
		else if(wrreq && !wrfull)
		begin
			mem[wr_ptr[AW-1:0]] <= data;
			wr_ptr               <= wr_ptr + 1;
			wr_ptr_gray          <= bin2gray(wr_ptr + 1);
		end

	// Read port
	always @(posedge rdclk or posedge aclr)
		if(aclr)
		begin
			rd_ptr      <= 0;
			rd_ptr_gray <= 0;
		end
		else if(rdreq && !rdempty)
		begin
			rd_ptr      <= rd_ptr + 1;
			rd_ptr_gray <= bin2gray(rd_ptr + 1);
		end

	// Sync wr_ptr_gray into rdclk domain
	always @(posedge rdclk or posedge aclr)
		if(aclr)
		begin
			wr_ptr_gray_s1 <= 0;
			wr_ptr_gray_s2 <= 0;
		end
		else
		begin
			wr_ptr_gray_s1 <= wr_ptr_gray;
			wr_ptr_gray_s2 <= wr_ptr_gray_s1;
		end

	// Sync rd_ptr_gray into wrclk domain
	always @(posedge wrclk or posedge aclr)
		if(aclr)
		begin
			rd_ptr_gray_s1 <= 0;
			rd_ptr_gray_s2 <= 0;
		end
		else
		begin
			rd_ptr_gray_s1 <= rd_ptr_gray;
			rd_ptr_gray_s2 <= rd_ptr_gray_s1;
		end
	
	//Convert synched read pointer back to binary so usedw substration works
	wire [AW:0] rd_ptr_synced_wr;
	assign rd_ptr_synced_wr = gray2bin(rd_ptr_gray_s2);

	assign q       = mem[rd_ptr[AW-1:0]];
	assign rdempty = (rd_ptr_gray == wr_ptr_gray_s2);
	assign rdfull  = (rd_ptr_gray == {~wr_ptr_gray_s2[AW:AW-1], wr_ptr_gray_s2[AW-2:0]});
	assign wrempty = (wr_ptr_gray == rd_ptr_gray_s2);
	assign wrfull  = (wr_ptr_gray == {~rd_ptr_gray_s2[AW:AW-1], rd_ptr_gray_s2[AW-2:0]});
	assign usedw   = wr_ptr - rd_ptr_synced_wr;

endmodule
