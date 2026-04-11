//fifo_24_dc.v
//ECE641 Project 3
//Dual-clock 24-bit FIFO for address storage
//Write clock: 148.5 MHz (SDRAM/UART side)
//Read clock:  148.5 MHz (address FIFOs run same domain on both sides)

`timescale 1 ns / 1 ns

module fifo_24_dc(wrclk, rdclk, aclr, wrreq, rdreq, data, q, wrempty, wrfull, rdempty, rdfull);
	input wrclk;
	input rdclk;
	input aclr;
	input wrreq;
	input rdreq;
	input [23:0] data;
	output [23:0] q;
	output wrempty;
	output wrfull;
	output rdempty;
	output rdfull;

	parameter DEPTH = 16;
	parameter AW    = 4;

	reg [23:0] mem [0:DEPTH-1];

	// Write side pointers
	reg [AW:0] wr_ptr;
	reg [AW:0] wr_ptr_gray;

	// Read side pointers
	reg [AW:0] rd_ptr;
	reg [AW:0] rd_ptr_gray;

	// Synchronizers
	reg [AW:0] wr_ptr_gray_s1, wr_ptr_gray_s2;
	reg [AW:0] rd_ptr_gray_s1, rd_ptr_gray_s2;

	function [AW:0] bin2gray;
		input [AW:0] b;
		begin
			bin2gray = b ^ (b >> 1);
		end
	endfunction

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

	assign q       = mem[rd_ptr[AW-1:0]];
	assign rdempty = (rd_ptr_gray == wr_ptr_gray_s2);
	assign rdfull  = (rd_ptr_gray == {~wr_ptr_gray_s2[AW:AW-1], wr_ptr_gray_s2[AW-2:0]});
	assign wrempty = (wr_ptr_gray == rd_ptr_gray_s2);
	assign wrfull  = (wr_ptr_gray == {~rd_ptr_gray_s2[AW:AW-1], rd_ptr_gray_s2[AW-2:0]});

endmodule
