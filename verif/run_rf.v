// run_rf.v
// testing top end for pdp8_rf.v
//

`include "pdp8_rf.v"


`timescale 1ns / 1ns

module test;

   reg clk, reset;

   wire [11:0] io_data_in;
   wire [11:0] io_data_out;
   wire        io_data_avail;
   wire        io_interrupt;
   wire        io_skip;
   wire [5:0]  io_select;
   
   wire        iot;
   wire [3:0]  state;
   wire [11:0] mb;
   
   pdp8_rf rf(.clk(clk),
	      .reset(reset),
	      .iot(iot),
	      .state(state),
	      .mb(mb),
	      .io_data_in(io_data_out),
	      .io_data_out(io_data_in),
	      .io_select(io_select),
	      .io_data_avail(io_data_avail),
	      .io_interrupt(io_interrupt),
	      .io_skip(io_skip));

  initial
    begin
      $timeformat(-9, 0, "ns", 7);

      $dumpfile("pdp8_rf.vcd");
      $dumpvars(0, test.rf);
    end

  initial
    begin
      clk = 0;
      reset = 0;

    #1 begin
         reset = 1;
       end

    #50 begin
         reset = 0;
       end
  
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

