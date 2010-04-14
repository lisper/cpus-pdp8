// KW8/I emulation
// brad@heeltoe.com

module pdp8_kw(clk, reset, iot, state, mb,
	       io_select, io_selected, io_interrupt, io_skip);

   input	clk;
   input 	reset;
   input 	iot;
   
   input [3:0] 	state;
   input [11:0] mb;
   input [5:0] 	io_select;

   output reg	     io_selected;
   output  	     io_interrupt;
   output reg 	     io_skip;

   // cpu states
   parameter
       F0 = 4'b0000,
       F1 = 4'b0001,
       F2 = 4'b0010,
       F3 = 4'b0011;

   // state
//   reg [7:0] kw_src_ctr;
   reg [1:0] kw_src_ctr;
   reg 	     kw_src_clk;

   reg [11:0] kw_ctr;
   reg 	      kw_int_en;
   reg 	      kw_clk_en;
   reg 	      kw_flag;
   
   wire     assert_kw_flag;
   
   assign   io_interrupt = kw_int_en && kw_flag;

   // combinatorial
   always @(state or iot or io_select or kw_flag or mb)
     begin
	// sampled during f1
	io_skip = 1'b0;
	io_selected = 1'b0;

	if (state == F1 && iot)
	  case (io_select)
	    6'o13:
	      begin
		 io_selected = 1'b1;

		 case (mb[2:0] )
		 3'o3:
		   if (kw_flag)
		     io_skip = 1;
		 endcase
		 
	      end
	  endcase // case(io_select)
     end
   

   //
   // registers
   //
   always @(posedge clk)
     if (reset)
       begin
	  kw_clk_en <= 1'b0;
	  kw_int_en <= 1'b0;
	  kw_flag <= 1'b0;
       end
     else
       case (state)
	  F0:
	    begin
	    end

	  F1:
	    begin
	       if (iot && io_select == 6'o13)
		 case (mb[2:0])
		   3'o1:
		     begin
			kw_int_en <= 1'b1;
			kw_clk_en <= 1'b1;
`ifdef debug
			$display("kw8i: clocks on!");
`endif
		     end
		   3'o2:
		     begin
`ifdef debug
			$display("CCFF");
`endif
			kw_flag <= 1'b0;
			kw_clk_en <= 1'b0;
			kw_int_en <= 1'b0;
		     end
		   3'o3:
		     begin
`ifdef debug
			$display("CSCF");
`endif
			kw_flag <= 1'b0;
		     end
		   3'o6:
		     begin
`ifdef debug
			$display("CCEC");
`endif
			kw_clk_en <= 1;
		     end
		   3'o7:
		     begin
`ifdef debug
			$display("CECI");
`endif
			kw_clk_en <= 1;
			kw_int_en <= 1;
		     end
		 endcase
	    end

	  F3:
	    begin
	       if (assert_kw_flag)
		 begin
		    kw_flag <= 1;
`ifdef debug
		    if (kw_flag == 0) $display("kw8i: set kw_flag!\n");
`endif
		 end
	    end

       endcase // case(state)

   assign assert_kw_flag = kw_ctr == 0;
   
   //
   always @(posedge kw_src_clk or posedge reset)
     if (reset)
       kw_ctr <= 0;
     else
       if (kw_clk_en)
	 kw_ctr <= kw_ctr + 1;

   // source clock - divide down cpu clock
   always @(posedge clk)
     if (reset)
       begin
	  kw_src_ctr <= 0;
	  kw_src_clk <= 1'b0;
       end
     else
       begin
	  kw_src_ctr <= kw_src_ctr + 1;
	  if (kw_src_ctr == 0)
	    kw_src_clk <= ~kw_src_clk;
       end

endmodule // pdp8_kw

	      
