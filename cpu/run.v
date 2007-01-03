
`include "pdp8.v"

`timescale 1ns / 1ns

module test;

  reg clk, reset_n;
  reg[11:0] switches;

  pdp8 cpu(clk, reset_n, switches);

  initial
    begin
      $timeformat(-9, 0, "ns", 7);

      $dumpfile("pdp8.vcd");
      $dumpvars(0, test.cpu);
    end

  initial
    begin
      clk = 0;
      reset_n = 1;

    #1 begin
         reset_n = 0;
       end

    #100 begin
         reset_n = 1;
       end
  
//    #1500000 $finish;
      #3000000 $finish;
    end

  always
    begin
      #100 clk = 0;
      #100 clk = 1;
    end

  //----
  integer cycle;

  initial
    cycle = 0;

  always @(posedge cpu.clk)
   if (cpu.state == 4'b0000)
    begin
      cycle = cycle + 1;
      #1 $display("cycle %d, r%b, pc %o, ir%o, ma %o, mb %o, jmp %b, l%b ac %o, i%b/%b",
		cycle, cpu.run, cpu.pc,
		cpu.ir, cpu.ma, cpu.mb, cpu.jmp, cpu.l, cpu.ac,
		cpu.interrupt_enable, cpu.interrupt);
    end

//  always @(posedge cpu.clk)
//    begin
//      #1 $display("state %b, runs %b, pc %o, ir %o, ma %o mb %o, jmp %b, l %b ac %o",
//		cpu.state, cpu.run, cpu.pc,
//		cpu.ir, cpu.ma, cpu.mb, cpu.jmp, cpu.l, cpu.ac);
//    end

endmodule

