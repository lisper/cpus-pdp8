// PDP-8 i/o
// Based on descriptions in "Computer Engineering"
// Dev 2006 Brad Parker brad@heeltoe.com
// Revamp 2009 Brad Parker brad@heeltoe.com

module pdp8_io(clk, reset, iot, state, mb,
	       io_data_in, io_data_out, io_select,
	       io_data_avail, io_interrupt, io_skip, io_clear_ac);
   
   input clk, reset, iot;
   input [11:0] io_data_in;
   input [11:0]      mb;
   input [3:0] 	     state;
   input [5:0] 	     io_select;

   output wire [11:0] io_data_out;
   output wire 	      io_data_avail;
   output wire 	      io_interrupt;
   output wire 	      io_skip;
   output wire 	      io_clear_ac;

   wire 	     tt_io_selected;
   wire [11:0] 	     tt_io_data_out;
   wire 	     tt_io_data_avail;
   wire 	     tt_io_interrupt;
   wire 	     tt_io_skip;
   wire 	     tt_io_clear_ac;

   wire 	     rf_io_selected;
   wire [11:0] 	     rf_io_data_out;
   wire 	     rf_io_data_avail;
   wire 	     rf_io_interrupt;
   wire 	     rf_io_skip;
   wire 	     rf_io_clear_ac;
   
   pdp8_tt tt(.clk(clk),
	      .reset(reset),
	      .iot(iot),
	      .state(state),
	      .mb(mb),
	      .io_data_in(io_data_in),
	      .io_select(io_select),

	      .io_selected(tt_io_selected),
	      .io_data_out(tt_io_data_out),
	      .io_data_avail(tt_io_data_avail),
	      .io_interrupt(tt_io_interrupt),
	      .io_skip(tt_io_skip));

   pdp8_rf tf(.clk(clk),
	      .reset(reset),
	      .iot(iot),
	      .state(state),
	      .mb(mb),
	      .io_data_in(io_data_in),
	      .io_select(io_select),

	      .io_selected(rf_io_selected),
	      .io_data_out(rf_io_data_out),
	      .io_data_avail(rf_io_data_avail),
	      .io_interrupt(rf_io_interrupt),
	      .io_skip(rf_io_skip));

   assign io_data_out =
		       tt_io_selected ? tt_io_data_out :
		       rf_io_selected ? rf_io_data_out :
		       12'b0;

   assign io_data_avail =
			 tt_io_selected ? tt_io_data_avail :
			 rf_io_selected ? rf_io_data_avail :
			 1'b0;
   
   assign io_interrupt =
			tt_io_selected ? tt_io_interrupt :
			rf_io_selected ? rf_io_interrupt :
			1'b0;

   assign io_skip =
		   tt_io_selected ? tt_io_skip :
		   rf_io_selected ? rf_io_skip :
		   1'b0;

   assign io_clear_ac =
			tt_io_selected ? tt_io_clear_ac :
			rf_io_selected ? rf_io_clear_ac :
			1'b0;
   
endmodule
