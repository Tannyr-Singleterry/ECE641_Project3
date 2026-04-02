module FRE_MEASURE( 
input          MES_CLK ,
input          RESET_n , 

input          HZ1,

output reg [31:0]  FREQ ,
output reg [31:0]  FCNT
) ;

//--REG------
reg [4:0] rHZ1  ; 
reg [1:0] F; 

//--MEASUR--- 
always @(negedge RESET_n or  posedge MES_CLK  )    
if (!RESET_n)  begin 
      rHZ1   <=0; 
		F      <=0; 
		FCNT <= 0 ;
		FREQ <=0; 
end
else 
begin
        rHZ1   <=  { rHZ1[3:0] , HZ1 } ;
			    if (|rHZ1==0 )  F  <= {F[0] ,1'b0 } ; 
		  else if (&rHZ1==1 )  F  <= {F[0] ,1'b1 } ; 
		
	//----------	
	  if ( F == 2'b01)   { FREQ , FCNT } <= { FCNT[31:0] , 32'h0 } ;  
	  else  FCNT <=FCNT+1;
end		
	
endmodule 
	
	