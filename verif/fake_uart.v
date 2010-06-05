//
// fake model of uart used for sim
//

//`define debug_fake_tx 1
`define debug_fake_rx 1

module fake_uart(clk, reset, state,
		 tx_clk, tx_req, tx_ack, tx_data, tx_empty,
		 rx_clk, rx_req, rx_ack, rx_empty, rx_data);

   input clk;
   input reset;
   input [3:0] state;

   input tx_clk;
   input tx_req;
   input [7:0] tx_data;

   input rx_clk;
   input rx_req;

   output tx_ack;
   output tx_empty;

   output rx_ack;
   output rx_empty;
   output reg [7:0] rx_data;

   //
   reg [1:0] 	t_state;
   wire [1:0] 	t_state_next;
   
   reg [1:0] 	r_state;
   wire [1:0] 	r_state_next;

   integer 	t_delay;
   reg 		t_done;

   //
   assign t_state_next =
			(t_state == 0 && tx_req) ? 1 :
			t_state == 1 ? 2 :
			(t_state == 2 && t_done) ? 0 :
			t_state;

   assign tx_ack = t_state == 1;
   assign tx_empty = t_delay == 0;

   initial
     begin
	t_delay = 0;
	refire_state = 0;
     end

   always @(posedge clk)
     begin
	if (t_state == 1)
	  begin
	     t_delay = 38/*20*/;
	  end
	if (t_delay > 0)
	  begin
	     if (state == 4'b0001)
	       t_delay = t_delay - 1;
//	     t_delay = t_delay - 1;
	     if (t_delay == 0)
	       begin
		  t_done = 1;
		  //$display("xxx t_done; cycles %d", cycles);
	       end
`ifdef debug_fake_tx
	     $display("t_state %d t_delay %d", t_state, t_delay);
`endif
	  end
	if (t_state == 0)
	  t_done = 0;
     end

   integer cycles;
   initial
     cycles = 0;
   
   always @(posedge clk)
     begin
	if (state == 4'b0001)
	  begin
	     cycles = cycles + 1;
	     //$display("cycles %d", cycles);
//	     if (r_index == r_count && cycles >= 30000)
//	       begin
//		  $display("xxx want input; cycles %d", cycles);
//	       end
	     if (r_index == r_count && cycles == 110000/*200000*/)
	       begin
		  rdata[0] = "L";
		  rdata[1] = "O";
		  rdata[2] = "G";
		  rdata[3] = "I";
		  rdata[4] = "N";
		  rdata[5] = " ";
		  rdata[6] = "2";
		  rdata[7] = " ";
		  rdata[8] = "L";
		  rdata[9] = "X";
		  rdata[10] = "H";
		  rdata[11] = "E";
		  rdata[12] = "\215";
		  rdata[13] = "\215";
		  r_index = 0;
		  r_count = 14;
		  r_refires = 1;
		  $display("xxx boom 1; cycles %d", cycles);
	       end
	     if (r_index == r_count && cycles == 120000/*300000*/)
	       begin
		  rdata[0] = "\215";
		  r_index = 0;
		  r_count = 1;
		  r_refires = 2;
		  $display("xxx boom 2; cycles %d", cycles);
	       end
	     if (r_index == r_count && cycles == 130000/*400000*/)
	       begin
		  rdata[0] = "\215";
		  r_index = 0;
		  r_count = 1;
		  r_refires = 3;
		  $display("xxx boom 3; cycles %d", cycles);
	       end
//`define msg_rcat 1
//`define msg_rfocal 1
`define msg_pald 1
	     if (r_index == r_count && cycles == 300000/*500000*/)
	       begin
`ifdef msg_rcat
		  rdata[0] = "R";
		  rdata[1] = " ";
		  rdata[2] = "C";
		  rdata[3] = "A";
		  rdata[4] = "T";
		  rdata[5] = "\215";
		  r_index = 0;
		  r_count = 6;
`endif
`ifdef msg_rfocal
		  rdata[0] = "R";
		  rdata[1] = " ";
		  rdata[2] = "F";
		  rdata[3] = "O";
		  rdata[4] = "C";
		  rdata[5] = "A";
		  rdata[6] = "L";
		  rdata[7] = "\215";
		  r_index = 0;
		  r_count = 8;
`endif
`ifdef msg_pald
		  rdata[0] = "R";
		  rdata[1] = " ";
		  rdata[2] = "P";
		  rdata[3] = "A";
		  rdata[4] = "L";
		  rdata[5] = "D";
		  rdata[6] = "\215";
		  r_index = 0;
		  r_count = 7;
`endif
		  r_refires = 4;
		  $display("xxx boom 4; cycles %d", cycles);
	       end
	     if (r_index == r_count && cycles == 400000/*600000*/)
	       begin
		  rdata[0] = "\215";
		  r_index = 0;
		  r_count = 1;
		  r_refires = 5;
		  $display("xxx boom 5; cycles %d", cycles);
	       end
	  end
     end
   
   //
   assign r_state_next =
			r_state == 0 && rx_req ? 1 :
			r_state == 1 ? 2 :
			r_state == 2 ? 0 :
			r_state;
   

   assign rx_ack = r_state == 1;
   
   integer r_index, r_count, r_refires;

   integer do_refire, refire_state;
   
   assign rx_empty = r_index == r_count;

   initial
     begin
	r_index= 0;
`ifdef no_fake_input
	r_count = 0;
`else
	r_count = 22;
`endif
	r_refires = 0;
     end

   reg [7:0] rdata[50:0];
   integer   ii;

   /* "START\r01:01:85\r10:10\r" */
   initial
     begin
	ii = 0;
	rdata[ii] = 0; ii=ii+1;	
	rdata[ii] = "S"; ii=ii+1;
	rdata[ii] = "T"; ii=ii+1;
	rdata[ii] = "A"; ii=ii+1;
	rdata[ii] = "R"; ii=ii+1;
	rdata[ii] = "T"; ii=ii+1;
	rdata[ii] = "\215"; ii=ii+1;
	rdata[ii] = "0"; ii=ii+1;
	rdata[ii] = "1"; ii=ii+1;
	rdata[ii] = ":"; ii=ii+1;
	rdata[ii] = "0"; ii=ii+1;
	rdata[ii] = "1"; ii=ii+1;
	rdata[ii] = ":"; ii=ii+1;
	rdata[ii] = "8"; ii=ii+1;
	rdata[ii] = "5"; ii=ii+1;
	rdata[ii] = "\215"; ii=ii+1;
	rdata[ii] = "1"; ii=ii+1;
	rdata[ii] = "0"; ii=ii+1;
	rdata[ii] = ":"; ii=ii+1;
	rdata[ii] = "1"; ii=ii+1;
	rdata[ii] = "0"; ii=ii+1;
	rdata[ii] = "\215"; ii=ii+1;
	
	rx_data = 0;
     end

   
   always @(*)
     begin
	if (r_state == 2)
	  begin
`ifdef debug_fake_rx
	     $display("xxx dispense %0d %o %t",
		      r_index, rdata[r_index], $time);
`endif
	     rx_data = rdata[r_index];
	     r_index = r_index + 1;
	  end
     end
	  
   //
   always @(posedge clk)
     if (reset)
       t_state <= 0;
     else
       t_state <= t_state_next;
   
   always @(posedge clk)
     if (reset)
       r_state <= 0;
     else
       r_state <= r_state_next;
   
endmodule

