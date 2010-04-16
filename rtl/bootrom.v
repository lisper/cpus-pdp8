//
// boot rom occupies one page from 7400 - 7577
//

module bootrom(clk, reset, addr, data_out, rd, selected);

   input clk;
   input reset;
   input [14:0] addr;
   output [11:0] data_out;
   input 	 rd;
   output 	 selected;

   //
   reg 		 deactivate;
   reg [2:0] 	 delay;
   reg [11:0] 	 data;
   wire 	 active;
   
   always @(posedge clk)
     if (reset)
       delay <= 3'o7;
     else
       if (deactivate || (delay != 3'o7 && delay != 3'o0))
	 delay <= delay - 3'o1;

    assign active = delay != 3'b000;
    assign selected = active && (addr >= 12'o7400 && addr <= 12'o7577);
		
    assign data_out = data;
   
   always @(*)
     begin
	deactivate = 0;

//`define debug_rom
`ifdef debug_rom
	$display("rom: active %b delay %o addr %o", active, delay, addr);
`endif

	if (rd)
	  case (addr)
	    // copy tss8 bootstrap to ram and jump to it
	    // (see ../rom/rom.pal)
	    12'o7400: data = 12'o7240;
	    12'o7401: data = 12'o1223;
	    12'o7402: data = 12'o3010;
	    12'o7403: data = 12'o1216;
	    12'o7404: data = 12'o3410;
	    12'o7405: data = 12'o1217;
	    12'o7406: data = 12'o3410;
	    12'o7407: data = 12'o1220;
	    12'o7410: data = 12'o3410;
	    12'o7411: data = 12'o1221;
	    12'o7412: data = 12'o3410;
	    12'o7413: data = 12'o1222;
	    12'o7414: data = 12'o3410;
	    12'o7415: data = 12'o5623;
	    12'o7416: data = 12'o7600;
	    12'o7417: data = 12'o6603;
	    12'o7420: data = 12'o6622;
	    12'o7421: data = 12'o5352;
	    12'o7422: data = 12'o5752;
	    12'o7423: data = 12'o7750;
	  endcase // case(addr)

	if (rd && addr == 12'o7415)
	  deactivate = 1;
	
     end
   
endmodule
