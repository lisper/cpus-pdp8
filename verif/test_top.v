// run_top.v
// testing top end for pdp8.v
//

`include "../rtl/pdp8_tt.v"
`include "../rtl/pdp8_rf.v"
`include "../rtl/pdp8_io.v"
`include "../rtl/pdp8_ram.v"
`include "../rtl/pdp8.v"
`include "../rtl/top.v"
`include "../rtl/ram_32kx12.v"
`include "../rtl/ram_256x12.v"
`include "../rtl/debounce.v"

`timescale 1ns / 1ns

module test;

   wire	rs232_txd;
   wire rs232_rxd;

   reg [3:0] button;

   wire [7:0] led;
   reg 	      sysclk;

   wire [7:0] sevenseg;
   wire [3:0] sevenseg_an;

   reg [7:0]  slideswitch;

   wire [17:0] ram_a;
   wire        ram_oe_n;
   wire        ram_we_n;

   wire [15:0] ram1_io;
   wire        ram1_ce_n;
   wire        ram1_ub_n;
   wire        ram1_lb_n;

   wire [15:0] ram2_io;
   wire        ram2_ce_n;
   wire        ram2_ub_n;
   wire        ram2_lb_n;
   
   wire [15:0] ide_data_bus;
   wire        ide_dior, ide_diow;
   wire [1:0]  ide_cs;
   wire [2:0]  ide_da;

   top top(.rs232_txd(rs232_txd),
	   .rs232_rxd(rs232_rxd),
	   .button(button),
	   .led(led),
	   .sysclk(sysclk),
	   .sevenseg(sevenseg),
	   .sevenseg_an(sevenseg_an),
	   .slideswitch(slideswitch),
	   .ram_a(ram_a),
	   .ram_oe_n(ram_oe_n),
	   .ram_we_n(ram_we_n),

	   .ram1_io(ram1_io),
	   .ram1_ce_n(ram1_ce_n),
	   .ram1_ub_n(ram1_ub_n),
	   .ram1_lb_n(ram1_lb_n),

	   .ram2_io(ram2_io),
	   .ram2_ce_n(ram2_ce_n),
	   .ram2_ub_n(ram2_ub_n),
	   .ram2_lb_n(ram2_lb_n),

	   .ide_data_bus(ide_data_bus),
	   .ide_dior(ide_dior),
	   .ide_diow(ide_diow),
	   .ide_cs(ide_cs),
	   .ide_da(ide_da));

  initial
    begin
      $timeformat(-9, 0, "ns", 7);

      $dumpfile("pdp8.vcd");
      $dumpvars(0, test.top);
    end

  initial
    begin
       sysclk = 0;
      #3000000 $finish;
    end

  always
    begin
      #10 sysclk = 0;
      #10 sysclk = 1;
    end

  //----
  integer cycle;

  initial
    cycle = 0;

  always @(posedge top.cpu.clk)
   if (top.cpu.state == 4'b0000)
    begin
      cycle = cycle + 1;
      #1 $display("pc %o ir %o l %b ac %o ion %o",
		  top.cpu.pc, top.cpu.mb, top.cpu.l, top.cpu.ac,
		  top.cpu.interrupt_enable);

       if (top.cpu.state == 4'b1100)
	 $finish;
    end

endmodule

