//uart_tx.v
//ECE641 Project 3
//UART RS232 Transmitter

`timescale 1 ns / 1 ns

module uart_tx(ar, clk, data, tx_start, tx, tx_busy);
	input ar;
	input clk;
	input [7:0] data;
	input tx_start;
	output reg tx;
	output reg tx_busy;

	parameter [1:0] Idle  = 2'd0,
	                Start = 2'd1,
	                Data  = 2'd2,
	                Stop  = 2'd3;

	reg [1:0] cs;
	reg [15:0] ctr;
	reg [2:0] idx;
	reg [7:0] tx_byte;

	always @(negedge ar or posedge clk)
		if(~ar)
		begin
			cs      <= Idle;
			ctr     <= 0;
			idx     <= 0;
			tx_byte <= 8'd0;
			tx      <= 1'b1;
			tx_busy <= 1'b0;
		end
		else
		case(cs)
			Idle:
			begin
				tx      <= 1'b1;
				ctr     <= 0;
				idx     <= 0;
				tx_busy <= 1'b0;
				if(tx_start)
				begin
					tx_byte <= data;
					tx_busy <= 1'b1;
					cs      <= Start;
				end
			end

			Start:
			begin
				tx <= 1'b0;
				if(ctr < 1289 - 1)
					ctr <= ctr + 1;
				else
				begin
					ctr <= 0;
					cs  <= Data;
				end
			end

			Data:
			begin
				tx <= tx_byte[idx];
				if(ctr < 1289 - 1)
					ctr <= ctr + 1;
				else
				begin
					ctr <= 0;
					if(idx < 7)
						idx <= idx + 1;
					else
						cs <= Stop;
				end
			end

			Stop:
			begin
				tx <= 1'b1;
				if(ctr < 1289 - 1)
					ctr <= ctr + 1;
				else
				begin
					ctr <= 0;
					cs  <= Idle;
				end
			end

			default:
				cs <= Idle;
		endcase

endmodule