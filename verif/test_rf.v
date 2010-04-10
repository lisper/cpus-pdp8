// run_rf.v
// testing top end for pdp8_rf.v
//

`include "../rtl/pdp8_rf.v"


`timescale 1ns / 1ns

module test;

   reg clk, reset;

   wire [11:0] io_data_out;
   wire        io_data_avail;
   wire        io_interrupt;
   wire        io_skip;

   wire        ram_read_req;
   wire        ram_write_req;
   reg 	       ram_done;

   wire [14:0] ram_ma;
   wire [11:0] ram_out;
   reg [11:0]  ram_in;

   reg [5:0]   io_select;
   reg [11:0]  io_data_in;
   reg 	       iot;
   reg [3:0]   state;
   reg [11:0]  mb_in;
   
   pdp8_rf rf(.clk(clk),
	      .reset(reset),
	      .iot(iot),
	      .state(state),
	      .mb(mb_in),
	      .io_data_in(io_data_in),
	      .io_data_out(io_data_out),
	      .io_select(io_select),
	      .io_data_avail(io_data_avail),
	      .io_interrupt(io_interrupt),
	      .io_skip(io_skip),
	      .ram_read_req(ram_read_req),
	      .ram_write_req(ram_write_req),
	      .ram_done(ram_done),
	      .ram_ma(ram_ma),
	      .ram_in(ram_in),
	      .ram_out(ram_out));

   //
   task write_rf_reg;
      input [11:0] isn;
      input [11:0] data;

      begin
	 @(posedge clk);
	 begin
	    state = 4'h0;
	    mb_in = isn;
	    io_select = isn[8:3];
	    io_data_in = data;
	    iot = 1;
	 end
	 #20 state = 4'h1;
	 #20 state = 4'h2;
	 #20 state = 4'h3;
	 #20 begin
	    state = 4'h0;
	    iot = 0;
	 end
      end
   endtask

   //
   task read_rf_reg;
      input [11:0] isn;
      output [11:0] data;

      begin
	 @(posedge clk);
	 begin
	    state = 4'h0;
	    mb_in = isn;
	    io_select = isn[8:3];
	    io_data_in = 0;
	    iot = 1;
	 end
	 #20 state = 4'h1;
	 #20 begin
	    data = io_data_out;
	    state = 4'h2;
	 end
	 #20 state = 4'h3;
	 #20 begin
	    state = 4'h0;
	    iot = 0;
	 end
      end
   endtask

   initial
     begin
	$timeformat(-9, 0, "ns", 7);
	
	$dumpfile("pdp8_rf.vcd");
	$dumpvars(0, test.rf);
     end

   reg [11:0]  data;

   initial
     begin
	clk = 0;
	reset = 0;
	ram_done = 1;
	ram_in = 0;

	#1 begin
           reset = 1;
	end

	#50 begin
           reset = 0;
	end

	write_rf_reg(12'o6000, 12'o0000);
	write_rf_reg(12'o6601, 12'o0000);
	write_rf_reg(12'o6611, 12'o0000);
	write_rf_reg(12'o6615, 12'o0000);
	write_rf_reg(12'o6641, 12'o0000);
	write_rf_reg(12'o6643, 12'o0000);
	read_rf_reg(12'o6616, data);

	write_rf_reg(12'o6603, 12'o0000);	// DMAR
	write_rf_reg(12'o6000, 12'o0000);
	write_rf_reg(12'o6000, 12'o0000);
  
	#3000 $finish;
     end

  always
    begin
      #10 clk = 0;
      #10 clk = 1;
    end

  //----
  integer cycle;

  initial
    cycle = 0;

  always @(posedge rf.clk)
    begin
      cycle = cycle + 1;
    end

endmodule

