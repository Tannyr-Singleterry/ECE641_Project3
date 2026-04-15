//uart_mgr.v
//ECE641 Project 2
//UART Manager to interpret UART signals - Updated for SDRAM FIFOs

`timescale 1 ns / 1 ns

module uart_mgr(ar, clk, new_rx, tx_done, tx_start, rx_word, tx_word, control_reg0, control_reg1,
					control_reg2, control_reg3, sdram_wr_addr_valid, sdram_wr_addr, 
					sdram_wr_data_valid, sdram_wr_data, sdram_rd_addr_valid, sdram_rd_addr,
					sdram_rd_data_valid, sdram_rd_data);
					
	input ar;
	input clk;
	input new_rx;
	input tx_done;
	output reg tx_start;
	input [7:0] rx_word;
	output reg [7:0] tx_word;
	output reg [31:0] control_reg0;
	output reg [31:0] control_reg1;
	output reg [31:0] control_reg2;
	output reg [31:0] control_reg3;
	
	// SDRAM FIFO Interface
	output reg sdram_wr_addr_valid;
	output reg [23:0] sdram_wr_addr;
	output reg sdram_wr_data_valid;
	output reg [31:0] sdram_wr_data;
	output reg sdram_rd_addr_valid;
	output reg [23:0] sdram_rd_addr;
	input sdram_rd_data_valid;
	input [31:0] sdram_rd_data;
	
	//Command. Checks the incoming byte against ASCII value per command. 
	reg [3:0] data_value;
	wire R, W, W_bulk, A, C;
	
	assign R = (rx_word == 8'h52 || rx_word == 8'h72) ? 1'b1 : 1'b0; // R or r for read
	assign W = (rx_word == 8'h57) ? 1'b1 : 1'b0; //W for normal write in terminal.
	assign W_bulk = (rx_word == 8'h77) ? 1'b1 : 1'b0; //w my solution for reading in the burst write file. 
	assign A = (rx_word == 8'h41 || rx_word == 8'h61) ? 1'b1 : 1'b0; // A or a for address
	assign C = (rx_word == 8'h43 || rx_word == 8'h63) ? 1'b1 : 1'b0; // C or c for control register
	
	//ASCII converter. 0-9, A-F, a-f, converts to 4 bit binary value.
	always @(rx_word)
		case(rx_word)
			8'h30: data_value = 4'h0;
			8'h31: data_value = 4'h1;
			8'h32: data_value = 4'h2;
			8'h33: data_value = 4'h3;
			8'h34: data_value = 4'h4;
			8'h35: data_value = 4'h5;
			8'h36: data_value = 4'h6;
			8'h37: data_value = 4'h7;
			8'h38: data_value = 4'h8;
			8'h39: data_value = 4'h9;
			8'h41: data_value = 4'ha;
			8'h61: data_value = 4'ha;
			8'h42: data_value = 4'hb;
			8'h62: data_value = 4'hb;
			8'h43: data_value = 4'hc;
			8'h63: data_value = 4'hc;
			8'h44: data_value = 4'hd;
			8'h64: data_value = 4'hd;
			8'h45: data_value = 4'he;
			8'h65: data_value = 4'he;
			8'h46: data_value = 4'hf;
			8'h66: data_value = 4'hf;
			default: data_value = 4'h0;
		endcase
		
	reg rxnew_old, txdone_old;
	wire rxnew_posedge, txdone_posedge;
	
	//Decect edge for registers. 
	always @(negedge ar or posedge clk)
		if(~ar)
		begin
			rxnew_old <= 1'b0;
			txdone_old <= 1'b0;
		end
		else
		begin
			rxnew_old <= new_rx;
			txdone_old <= tx_done;
		end
		
	assign rxnew_posedge = new_rx & ~rxnew_old;
	assign txdone_posedge = tx_done & ~txdone_old;
	
	//FSM states. 
	parameter [4:0] Idle = 5'd0, Command_Type = 5'd1, Read_Mem = 5'd2, Write_Mem = 5'd3,
					Address_Mem = 5'd4, Control_Reg = 5'd5, Wait_Mem = 5'd6, 
					Tx_Mem_Byte = 5'd7, Wait_Tx_Mem = 5'd8, Mem_Incr_Addr = 5'd9, 
					Get_Write_Data_Mem = 5'd10, Write_Mem_Cmd = 5'd11, Get_Mem_Addr = 5'd12, 
					Reg_Num = 5'd13, CR_Ror_W = 5'd14, Prep_Tx_CR = 5'd15, Tx_CR_Byte = 5'd18,
					Wait_Tx_CR = 5'd16, Rx_CR_Byte = 5'd17, Prep_Tx_Mem = 5'd19, Tx_Mem_Fire = 5'd20,
					Bulk_Write = 5'd21, Bulk_Get_Addr = 5'd22, Bulk_Get_Data = 5'd23;
					
	reg [4:0] cs;
	reg [11:0] ctr; //General counter. is 12 bits ot handle bulk write. 
	reg [1:0] idx;	//Control register index (0-3)
	reg [31:0] tx_reg; //shift reg used to serialize 32 bit value for trasmit
	reg [31:0] buffer; 
	reg is_read;
	reg [23:0] current_addr; //Tracks current SDAM address. 
	
	//Converts 4 bit binary to ASCII hex
	function [7:0] binary_to_hex;
		input [3:0] bin;
		begin
			if (bin < 10)
				binary_to_hex = 8'h30 + bin;
			else
				binary_to_hex = 8'h41 + (bin - 10);
		end
	endfunction
	
	always @(negedge ar or posedge clk)
		if(~ar)
		begin
			cs <= Idle;
			tx_word <= 8'd0;
			tx_start <= 1'b0;
			ctr <= 12'd0;
			idx <= 2'b00;
			tx_reg <= 32'd0;
			buffer <= 32'd0;
			is_read <= 1'b0;
			current_addr <= 24'd0;
			
			sdram_wr_addr_valid <= 1'b0;
			sdram_wr_addr <= 24'd0;
			sdram_wr_data_valid <= 1'b0;
			sdram_wr_data <= 32'd0;
			sdram_rd_addr_valid <= 1'b0;
			sdram_rd_addr <= 24'd0;
			
			control_reg0 <= 32'h00000000;
			control_reg1 <= 32'h00000000;
			control_reg2 <= 32'h00000000;
			control_reg3 <= 32'h00000000;
		end
		else
		begin
			sdram_wr_addr_valid <= 1'b0;
			sdram_wr_data_valid <= 1'b0;
			sdram_rd_addr_valid <= 1'b0;
			tx_start <= 1'b0;
			
			case(cs)
				Idle:
				begin
					if(rxnew_posedge)
						cs <= Command_Type;
					else
					begin
						cs <= Idle;
						ctr <= 12'd0;
					end
				end
				
				//Decode which command was recieved and go to relative state. 
				Command_Type:
				begin
					if(R)
						cs <= Read_Mem;
					else if(W)
						cs <= Write_Mem;
					else if(W_bulk)
						cs <= Bulk_Write;
					else if(A)
						cs <= Address_Mem;
					else if(C)
						cs <= Control_Reg;
					else
						cs <= Idle;
				end
				
				Read_Mem:
				begin
					sdram_rd_addr <= current_addr;
					sdram_rd_addr_valid <= 1'b1;
					cs <= Wait_Mem;
				end
				
				//Wait for sdram_mgr to return valid read data before going to tx.
				Wait_Mem:
				begin
					if(sdram_rd_data_valid)
					begin
						tx_reg <= sdram_rd_data;
						ctr <= 12'd0;
						cs <= Prep_Tx_Mem;
					end
				end
				
				//Load next 4 bits into tx_word and shfit tx_reg left, ready to tx. 
				Prep_Tx_Mem:
				begin
					tx_word <= binary_to_hex(tx_reg[31:28]);
					tx_reg <= {tx_reg[27:0], 4'h0};
					cs <= Tx_Mem_Byte;
				end
				
				//Separate state to assert tx_start so tx_word is stable for a full cycle before tx. 
				Tx_Mem_Byte:
				begin
					tx_start <= 1'b1;
					cs <= Wait_Tx_Mem;
				end
				
				Wait_Tx_Mem:
				begin
					if(txdone_posedge)
					begin
						if(ctr < 7)
						begin
							ctr <= ctr + 1;
							cs <= Prep_Tx_Mem;
						end
						else
							cs <= Mem_Incr_Addr;
					end
				end
				
				//Increment current addres after each read or write and put into control_reg0. 
				Mem_Incr_Addr:
				begin
					current_addr <= current_addr + 1;
					control_reg0 <= {8'd0, current_addr + 1};
					cs <= Idle;
				end
				
				Write_Mem:
				begin
					ctr <= 12'd0;
					buffer <= 32'd0;
					cs <= Get_Write_Data_Mem;
				end
				
				//Recieve 8 hex 4 bit values and shfit them into buffer to form 32 bit word for write. 
				Get_Write_Data_Mem:
				begin
					if(rxnew_posedge)
					begin
						buffer <= {buffer[27:0], data_value};
						if(ctr < 7)
							ctr <= ctr + 1;
						else
							cs <= Write_Mem_Cmd;
					end	
				end
				
				//Issue the write address and data to the SDRAM FIFO in a single cycle. 
				Write_Mem_Cmd:
				begin
					sdram_wr_addr <= current_addr;
					sdram_wr_addr_valid <= 1'b1;
					sdram_wr_data <= buffer;
					sdram_wr_data_valid <= 1'b1;
					cs <= Mem_Incr_Addr;
				end
				
				Address_Mem:
				begin
					ctr <= 12'd0;
					buffer <= 32'd0;
					cs <= Get_Mem_Addr;
				end
				
				//Recieve 6 hex 4 bit values to form the new 24 bit SDRAM address
				Get_Mem_Addr:
				begin
					if(rxnew_posedge)
					begin
						buffer <= {buffer[19:0], data_value};
						if(ctr < 5)
							ctr <= ctr + 1;
						else
						begin
							current_addr <= {buffer[19:0], data_value};
							control_reg0 <= {8'd0, buffer[19:0], data_value};
							cs <= Idle;
						end
					end
				end
				
				// Receive the register number (0-3) to determine which control reg to access. 
				Control_Reg:
				begin
					if(rxnew_posedge)
					begin
						if(data_value < 4)
						begin
							idx <= data_value[1:0];
							cs <= CR_Ror_W;
						end
						else
							cs <= Idle;
					end
				end
				
				//Recieve R or W to determine whether to read or write the selected control reg. 
				CR_Ror_W:
				begin
					if(rxnew_posedge)
					begin
						if(R)
						begin
							is_read <= 1'b1;
							case(idx)
								2'd0: tx_reg <= control_reg0;
								2'd1: tx_reg <= control_reg1;
								2'd2: tx_reg <= control_reg2;
								2'd3: tx_reg <= control_reg3;
							endcase
							ctr <= 12'd0;
							cs <= Prep_Tx_CR;
						end
						else if(W)
						begin
							is_read <= 1'b0;
							ctr <= 12'd0;
							buffer <= 32'd0;
							cs <= Rx_CR_Byte;
						end
						else
							cs <= Idle;
					end
				end
				
				Prep_Tx_CR:
				begin
					tx_word <= binary_to_hex(tx_reg[31:28]);
					tx_reg <= {tx_reg[27:0], 4'h0};
					cs <= Tx_CR_Byte;
				end
				
				Tx_CR_Byte:
				begin
					tx_start <= 1'b1;
					cs <= Wait_Tx_CR;
				end
				
				Wait_Tx_CR:
				begin
					if(txdone_posedge)
					begin
						if(ctr < 7)
						begin
							ctr <= ctr + 1;
							cs <= Prep_Tx_CR;
						end
						else
							cs <= Idle;
					end
				end
				
				//Recieve 8 hex 4 bit valuies and write the assembled 32 bit value into the relative control register. 
				Rx_CR_Byte:
				begin
					if(rxnew_posedge)
					begin
						buffer <= {buffer[27:0], data_value};
						if(ctr < 7)
							ctr <= ctr + 1;
						else
						begin
							case(idx)
								2'd0: control_reg0 <= {buffer[27:0], data_value};
								2'd1: control_reg1 <= {buffer[27:0], data_value};
								2'd2: control_reg2 <= {buffer[27:0], data_value};
								2'd3: control_reg3 <= {buffer[27:0], data_value};
							endcase
							cs <= Idle;
						end
					end
				end
				
				Bulk_Write:
				begin
					// Start of lowercase 'w' bulk write: read 6-char address then 512 words
					ctr <= 12'd0;
					buffer <= 32'd0;
					cs <= Bulk_Get_Addr;
				end
				
				//Recieve 6 hex 4 bit values to form the 24 bit starting address. 
				Bulk_Get_Addr:
				begin
					if(rxnew_posedge)
					begin
						buffer <= {buffer[19:0], data_value};
						if(ctr < 5)
							ctr <= ctr + 1;
						else
						begin
							sdram_wr_addr <= {buffer[19:0], data_value};
							sdram_wr_addr_valid <= 1'b1;
							current_addr <= {buffer[19:0], data_value};
							control_reg0 <= {8'd0, buffer[19:0], data_value};
							ctr <= 12'd0;
							buffer <= 32'd0;
							cs <= Bulk_Get_Data;
						end
					end
				end

				//Recieve the 512 x 24 bit value (4096)
				//Assert wr_data_valid every 24 bits to push each word into the FIFO. 
				Bulk_Get_Data:
				begin
					if(rxnew_posedge)
					begin
						buffer <= {buffer[27:0], data_value};
						if(ctr[2:0] == 3'd7)
						begin
							sdram_wr_data <= {buffer[27:0], data_value};
							sdram_wr_data_valid <= 1'b1;
						end
						if(ctr < 12'd4095)
							ctr <= ctr + 1;
						else
							cs <= Idle;
					end
				end

				default:
					cs <= Idle;
				
			endcase
		end
	
endmodule