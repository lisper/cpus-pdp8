/* 32kx12 static ram */
module ram_32kx12(A, DI, DO, CE_N, WE_N);

  input[14:0] A;
  input[11:0] DI;
  input CE_N, WE_N;
  output[11:0] DO;

  reg[11:0] ram [0:32767];
  integer i;

   // synthesis translate_off
   reg [11:0] v;
   integer    file;
   reg [1023:0] str;
   reg [1023:0] testfilename;
   integer 	n;
   
  initial
    begin
      for (i = 0; i < 32768; i=i+1)
        ram[i] = 12'b0;

       n = 0;

`ifdef __ICARUS__
       n = $value$plusargs("test=%s", testfilename);
`endif
       
`ifdef __CVER__
       n = $scan$plusargs("test=", testfilename);
`endif

       if (n == 0)
	 begin
	    testfilename = "../verif/default.mem";
	    n = 1;
	 end
       
       if (n > 0)
	 begin
	    $display("ram: code filename: %s", testfilename);
	    file = $fopen(testfilename, "r");
	    
	    while ($fscanf(file, "%o %o\n", i, v) > 0)
	      begin
		 //$display("ram[%o] <- %o", i, v);
		 ram[i] = v;
	      end
	    
	    $fclose(file);
	 end
    end
   

  always @(WE_N or CE_N or A or DI)
    begin
       if (WE_N == 0 && CE_N == 0)
        begin
	   //$display("ram: write [%o] <- %o", A, DI);
           ram[ A ] = DI;
        end
    end

//always @(A)
//  begin
//    $display("ram: ce %b, we %b [%o] -> %o", CE_N, WE_N, A, ram[A]);
//  end

//  assign DO = ram[ A ];
assign DO = (^A === 1'bX || A === 1'bz) ? ram[0] : ram[A];

endmodule

