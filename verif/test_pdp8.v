// test_pdp8.v
// test bench top end for pdp8.v
//

`include "../rtl/pdp8_tt.v"
`include "../rtl/pdp8_rf.v"
`include "../rtl/pdp8_io.v"
`include "../rtl/pdp8_ram.v"
`include "../rtl/pdp8.v"
`include "../rtl/ram_32kx12.v"
`include "../rtl/ram_256x12.v"

`timescale 1ns / 1ns

module test;

   reg clk, reset;
   reg [11:0] switches;

   wire [11:0] ram_data_in;
   wire        ram_rd;
   wire        ram_wr;
   wire [11:0] ram_data_out;
   wire [14:0] ram_addr;
   wire [11:0] io_data_in;
   wire [11:0] io_data_out;
   wire [11:0] io_addr;
   wire        io_data_avail;
   wire        io_interrupt;
   wire        io_skip;
   wire [5:0]  io_select;
   
   wire        iot;
   wire [3:0]  state;
   wire [11:0] mb;
   
   wire        ext_ram_read_req;
   wire        ext_ram_write_req;
   wire [14:0] ext_ram_ma;
   wire [11:0] ext_ram_in;
   wire        ext_ram_done;
   wire [11:0] ext_ram_out;

  pdp8 cpu(.clk(clk),
	   .reset(reset),
	   .ram_addr(ram_addr),
	   .ram_data_in(ram_data_out),
	   .ram_data_out(ram_data_in),
	   .ram_rd(ram_rd),
	   .ram_wr(ram_wr),
	   .io_select(io_select),
	   .io_data_in(io_data_in),
	   .io_data_out(io_data_out),
	   .io_data_avail(io_data_avail),
	   .io_interrupt(io_interrupt),
	   .io_skip(io_skip),
	   .io_clear_ac(io_clear_ac),
	   .switches(switches),
	   .iot(iot),
	   .state(state),
	   .mb(mb),
	   .ext_ram_read_req(ext_ram_read_req),
	   .ext_ram_write_req(ext_ram_write_req),
	   .ext_ram_done(ext_ram_done),
	   .ext_ram_ma(ext_ram_ma),
	   .ext_ram_in(ext_ram_out),
	   .ext_ram_out(ext_ram_in));
   
   pdp8_io io(.clk(clk),
	      .reset(reset),
	      .iot(iot),
	      .state(state),
	      .mb(mb),
	      .io_data_in(io_data_out),
	      .io_data_out(io_data_in),
	      .io_select(io_select),
	      .io_data_avail(io_data_avail),
	      .io_interrupt(io_interrupt),
	      .io_skip(io_skip),
   	      .io_clear_ac(io_clear_ac),
   	      .io_ram_read_req(ext_ram_read_req),
	      .io_ram_write_req(ext_ram_write_req),
	      .io_ram_done(ext_ram_done),
	      .io_ram_ma(ext_ram_ma),
	      .io_ram_in(ext_ram_in),
	      .io_ram_out(ext_ram_out));

   pdp8_ram ram(.clk(clk),
	       .reset(reset), 
	       .addr(ram_addr),
	       .data_in(ram_data_in),
	       .data_out(ram_data_out),
	       .rd(ram_rd),
   	       .wr(ram_wr));

   reg [11:0]  starting_pc;

   reg [1023:0] arg;
   integer 	n;

  initial
    begin
      $timeformat(-9, 0, "ns", 7);

      $dumpfile("pdp8.vcd");
      $dumpvars(0, test.cpu);
    end

  initial
    begin

       clk = 0;
       reset = 0;
       switches = 0;
       max_cycles = 0;

       max_cycles = 100;
       starting_pc = 12'o0200;

`ifdef __ICARUS__
       n = $value$plusargs("pc=%o", arg);
	if (n > 0)
	  begin
	     starting_pc = arg;
	     $display("arg pc %o", starting_pc);
	  end

       n = $value$plusargs("switches=%o", arg);
	if (n > 0)
	  begin
	     switches = arg;
	     $display("arg swiches %o", switches);
	  end
       
       n = $value$plusargs("cycles=%d", arg);
	if (n > 0)
	  begin
	     max_cycles = arg;
	     $display("arg cycles %d", max_cycles);
	  end
`endif       

`ifdef __CVER__
       n = $scan$plusargs("pc=", arg);
	if (n > 0)
	  begin
	     n = $sscanf(arg, "%o", starting_pc);
	     $display("arg %s pc %o", arg, starting_pc);
	  end

       n = $scan$plusargs("switches=", arg);
	if (n > 0)
	  begin
	     n = $sscanf(arg, "%o", switches);
	     $display("arg %s switches %o", arg, switches);
	  end
       
       n = $scan$plusargs("cycles=", arg);
	if (n > 0)
	  begin
	     n = $sscanf(arg, "%o", max_cycles);
	     $display("arg %s cycles %o", arg, max_cycles);
	  end
`endif
       
       #1 begin
	  reset = 1;
       end

       #60 begin
          reset = 0;
       end

       cpu.pc = starting_pc;

//      #5000000 $finish;
    end

  always
    begin
      #10 clk = 0;
      #10 clk = 1;
    end

  //----
   integer cycle;
   integer max_cycles;
   integer sample;
   integer show_pc;
   integer show_state;

  initial
    begin
       cycle = 0;
       sample = 0;
       show_pc = 0;
       show_state = 0;
    end

  always @(posedge cpu.clk)
    begin
       if (cpu.state == 4'b0000)
	 begin
	    sample = sample + 1;
	    if (sample >= 50000)
	      begin
		 sample = 0;
		 show_pc = 1;
	      end

	    if (1) show_pc = 1;
	    if (0) show_state = 1;

	    cycle = cycle + 1;

	    if (max_cycles > 0 && cycle >= max_cycles)
	      $finish;

	    if (show_pc)
	      #1 $display("pc %o ir %o l%b ac %o ion %o (IF%o DF%o UF%o SF%o IB%o UB%o) %b",
			  cpu.pc, cpu.mb,
			  cpu.l, cpu.ac, cpu.interrupt_enable,
			  cpu.IF, cpu.DF, cpu.UF, cpu.SF, cpu.IB, cpu.UB,
			  cpu.interrupt_inhibit_delay);
	    show_pc = 0;
	 end

       if (cpu.state == 4'b1100)
	 begin
	    $display("HALTED @ %o", cpu.pc);
	    $display("cpu.io_interrupt %b io.io_interrupt %b tt.io_interrupt %b",
		     cpu.io_interrupt, 
		     io.io_interrupt, io.tt.io_interrupt);
	    $finish;
	 end

       if (show_state)
	 begin
	    #2 case (state)
		 4'b0000: $display("F0");
		 4'b0001: $display("F1");
		 4'b0010: $display("F2");
		 4'b0011: $display("F3");
		 4'b0100: $display("D0");
		 4'b0101: $display("D1");
		 4'b0110: $display("D2");
		 4'b0111: $display("D3");
		 4'b1000: $display("E0");
		 4'b1001: $display("E1");
		 4'b1010: $display("E2 %b%b%b%b%b r%bw%b",
				   cpu.i_and, cpu.tad, cpu.isz,
				   cpu.dca, cpu.jms,
				   cpu.ram_rd, cpu.ram_wr);
		 4'b1011: $display("E3");
	       endcase // case(state)
	 end
    end

endmodule

