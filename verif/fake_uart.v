//

module fake_uart(clk, reset, 
		 tx_clk, tx_req, tx_ack, tx_data, tx_empty,
		 rx_clk, rx_req, rx_ack, rx_empty, rx_data);

   input clk;
   input reset;

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
     t_delay = 0;
   
   always @(posedge clk)
     begin
	if (t_state == 1)
	  t_delay = 20;
	if (t_delay > 0)
	  begin
	     t_delay = t_delay - 1;
	     if (t_delay == 0)
	       t_done = 1;
	     if (0) $display("t_state %d t_delay %d", t_state, t_delay);
	  end
	if (t_state == 0)
	  t_done = 0;
     end


   //
   assign r_state_next =
			r_state == 0 && rx_req ? 1 :
			r_state == 1 ? 2 :
			r_state == 2 ? 0 :
			r_state;
   

   assign rx_ack = r_state == 1;
   
   integer r_index, r_count;
   
   assign rx_empty = r_index == r_count;

   initial
     begin
	r_index= 0;
	r_count = 6;
     end

   reg [7:0] rdata[5:0];

   initial
     begin
	rdata[0] = "S";
	rdata[1] = "T";
	rdata[2] = "A";
	rdata[3] = "R";
	rdata[4] = "T";
	rdata[5] = "\015";

	rx_data = 0;
     end

   
   always @(*)
     begin
	if (r_state == 2)
	  begin
	     $display("xxx dispense %0d %o", r_index, rdata[r_index]);
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
