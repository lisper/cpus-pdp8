
module pdp8_tt(clk, reset, iot, state, mb,
	       io_data_in, io_data_out, io_select, io_selected,
	       io_data_avail, io_interrupt, io_skip);
   
   input clk, reset, iot;
   input [11:0] io_data_in;
   input [11:0]      mb;
   input [3:0] 	     state;
   input [5:0] 	     io_select;

   output reg	     io_selected;
   output reg [11:0] io_data_out;
   output reg 	     io_data_avail;
   output reg 	     io_interrupt;
   output reg 	     io_skip;
   
   
   reg 		     rx_int, tx_int;
   reg [12:0] 	     rx_data, tx_data;
   reg 		     tx_delaying;
integer tx_delay;

   parameter 	     F0 = 4'b0000;
   parameter 	     F1 = 4'b0001;
   parameter 	     F2 = 4'b0010;
   parameter 	     F3 = 4'b0011;


   // combinatorial
   always @(state or
	    rx_int or tx_int)
     begin
	// sampled during f1
	io_skip = 1'b0;
	io_data_out = io_data_in;
	io_data_avail = 1'b1;
	io_selected = 1'b0;
	
	if (state == F1 && iot)
	  case (io_select)
	    6'o03:
	      begin
		 io_selected = 1'b1;
		 if (mb[0])
		   io_skip = rx_int;

		 if (mb[2])
		   io_data_out = rx_data;
	      end
	    
	    6'o04:
	      begin
		 io_selected = 1'b1;
		 if (mb[0])
		   begin
		      io_skip = tx_int;
		      $display("xxx io_skip %b", tx_int);
		   end
	      end
	  endcase // case(io_select)
     end
   

   //
   // registers
   //
   always @(posedge clk)
     if (reset)
       begin
       end
     else
       case (state)
	  F0:
	    begin
	       // sampled during f1
	       io_data_avail <= 0;
	    end

	  F1:
	    if (iot)
	      begin
		 $display("iot2 %t, state %b, mb %o, io_select %o",
			  $time, state, mb, io_select);

		 case (io_select)
		   6'o03:
		     begin
			if (mb[1])
			  rx_int <= 0;
		     end

		   6'o04:
		     begin
			if (mb[0])
			  begin
			  end
			if (mb[1])
			  begin
			     tx_int <= 0;
			     $display("xxx reset tx_int");
			  end
			if (mb[2])
			  begin
			     tx_data <= io_data_in;
			     $display("xxx tx_data %o", io_data_in);
			     tx_int <= 1;
			     tx_delaying <= 1;
			     tx_delay <= 98;
			     $display("xxx set tx_int");
			  end
		     end // case: 6'o04

                 endcase

	      end // if (iot)

	  F2:
	    begin
	       if (io_interrupt)
	       	 $display("iot2 %t, reset io_interrupt", $time);

	       // sampled during f0
	       io_interrupt <= 0;
	    end

	  F3:
	    begin
	       if (tx_delaying)
		 begin
		    tx_delay <= tx_delay - 1;
		    //$display("xxx delay %d", tx_delay);
		    if (tx_delay == 0)
		      begin
			 $display("iot2 %t, xxx set io_interrupt", $time);
			 tx_delaying <= 0;
			 io_interrupt <= 1;
		      end
		 end
	    end

       endcase // case(state)
   
endmodule
