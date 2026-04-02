//   Creates an output clock based on a modulus ctr which toggles the output clock each time the counter
//		goes to zero.  So there are two input cycle counts for every ouptut clock perod.
//
//	Author:   	D. Gruenbacher
//  Updated:    limit doubled from 24999999 to 49999999 for 100 MHz input clock
//              limit = (f_input / (2 * f_output)) - 1
//              1 Hz from 100 MHz: (100,000,000 / 2) - 1 = 49,999,999

`timescale 1 ns / 1 ns

module    clk_div(ar, clk_in, clk_out);
    input ar;			   // asynch reset (active low)
    input clk_in;         // Input clock
    output reg clk_out;       // Output clock 
    
    parameter n = 26;      // Bit width increased to 26 bits to hold 49999999 (requires 26 bits)
    parameter [n-1:0] limit = 26'd49999999; // Generates 1 Hz output from 100 MHz input
									        // limit = (f_input/(2*f_output)) - 1
    reg [n-1:0]   count;
    
    
    always @(negedge ar or posedge clk_in)
    if(~ar)
       begin
          count <= 0;
		  clk_out <= 1'b0;
       end
    else
      begin
                  
       if(count >= limit)  // use inequalty to save logic space for comparison
         begin
		 clk_out <= ~clk_out;
         
		 count <= 0;
		 end
		else
			count <= count + 1;
      end
                                                                                                                                                                                                              
 endmodule