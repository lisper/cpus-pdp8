/* 256x12 static ram */
module ram_256x12(A, DI, DO, CE_N, WE_N);

   input [7:0]   A;
   input [11:0]  DI;
   input 	 CE_N, WE_N;
   output [11:0] DO;

   reg [11:0] 	 ram [0:255];
   integer 	 i;
   
   initial
     begin
	for (i = 0; i < 256; i=i+1)
          ram[i] = 12'b0;
     end
   
   always @(WE_N or CE_N or A or DI)
     begin
	if (WE_N == 0 && CE_N == 0)
          begin
`ifdef debug_ram
	     $display("rf: buffer ram write [%o] <- %o", A, DI);
`endif
             ram[ A ] = DI;
          end

`ifdef debug_ram
	if (WE_N == 1 && CE_N == 0)
	  $display("rf: buffer ram read [%o] -> %o", A, ram[A]);
`endif
     end
   
   assign DO = ram[ A ];

endmodule

