//uart_rx.v
//ECE641 Project 3
//UART RS232 Receiver

`timescale 1 ns / 1 ns

module uart_rx(ar, clk, rx, data, new_rx);
	input ar;
	input clk;
	input rx;
	output reg [7:0] data;
	output reg new_rx;

	parameter [1:0] Idle  = 2'd0,
	                Start = 2'd1,
	                Data  = 2'd2,
	                Stop  = 2'd3;

	reg [1:0] cs;
	reg [15:0] ctr;
	reg [2:0] idx;
	reg [7:0] rx_byte;

	always @(negedge ar or posedge clk)
		if(~ar)
		begin
			cs      <= Idle;
			ctr     <= 0;
			idx     <= 0;
			rx_byte <= 8'd0;
			data    <= 8'd0;
			new_rx  <= 1'b0;
		end
		else
		begin
			new_rx <= 1'b0;

			case(cs)
				Idle:
				begin
					ctr <= 0;
					idx <= 0;
					if(~rx)
						cs <= Start;
				end

				Start:
				begin
					if(ctr < 644 - 1)
						ctr <= ctr + 1;
					else
					begin
						ctr <= 0;
						cs  <= Data;
					end
				end

				Data:
				begin
					if(ctr < 1289 - 1)
						ctr <= ctr + 1;
					else
					begin
						ctr          <= 0;
						rx_byte[idx] <= rx;
						if(idx < 7)
							idx <= idx + 1;
						else
							cs <= Stop;
					end
				end

				Stop:
				begin
					if(ctr < 1289 - 1)
						ctr <= ctr + 1;
					else
					begin
						ctr    <= 0;
						data   <= rx_byte;
						new_rx <= 1'b1;
						cs     <= Idle;
					end
				end

				default:
					cs <= Idle;
			endcase
		end

endmodule