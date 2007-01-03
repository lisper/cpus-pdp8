// PDP-8
// Based on descriptions in "Computer Engineering"
// Nov 2005 Brad Parker brad@heeltoe.com
//	initial work; runs focal a bit
// Dec 2006
//	cleaned up a little; now runs focal to prompt
//	moved i/o out to pdp8_io.v
//	added IF, DF, user mode
//

// TODO:
// fully implement extended memory (IF & DF), user mode (KT8/I)
// add df32/rf08
// 6000 pws ac <= switches
//

//   
// Instruction format:
//
//  0  1  2   3   4   5   6   7   8   9  10  11
// 11 10  9   8   7   6   5   4   3   2   1   0
// |--op--|
// 0 and
// 1 tad
// 2 isz
// 3 dca
// 4 jms
// 5 jmp
// 6 iot
// 7 opr
// 11 10  9   8   7   6   5   4   3   2   1   0
// group 1
//            0
//               |cla|clf|       |          |
//               |   |   |cma cml|          |
//                               |bsw 001   |
//                               |ral 010   |
//                               |rtl 011   |
//                               |rar 100   |
//                               |rtr 101   |
//                               |          |iac
//
// 11 10  9   8   7   6   5   4   3   2   1   0
// group 2
//            1                               0
//                   |sma|sza|snl|skp|      |
//               |cla|
//                                   |osr|hlt
//
// group 3
// 11 10  9   8   7   6   5   4   3   2   1   0
// eae
//            1                               1
//               |cla|
//                   |mqa|sca|mql|
//                               |isn       |
// 
//

/*
 cpu states
 
  F0 fetch
  F1 incr pc
  F2 write
  F3 dispatch

  E0 read
  E1 decode
  E2 write
  E3 load

or

  D0 read
  D1 wait
  D2 write
  D3 load

 ------
 
  F0 fetch
	check for interrupt
  F1 incr pc
	if opr
		group 1 processing
 		group 2 processing
 
 	if iot
 
	incr pc or skip (incr pc by 2)
 
  F2 write
 	ma <= pc
 
  F3 dispatch
	if opr
		group1 processing
 
	if !opr && !iot
 		possible defer
 
 
  D0
	mb <= memory
  D1
*/

// extended memory
//
// 62n1	cdf	change data field; df <= mb[5:3]
// 62n2 cif	change instruction field; if <= mb[5:3], after next jmp or jms
// 6214	rdf     read df into ac[5:3]
// 6224	rif     read if into ac[5:3]
// 6234	rib     read sf into ac[5:0], which is {if,df}
// 6244	rmf     restore memory field, sf => ib, df
// 		(remember that on interrupt, sf <= {if,df})
//

`include "pdp8_io.v"

module pdp8(clk, reset_n, switches);

input clk, reset_n;
input[11:0] switches;

// memory buffer, holds data, instructions
reg[11:0] mb;

// hold address of work in memory being accessed
reg[14:0] ma;

// accumulator & link
reg[11:0] ac;
reg l;

// MQ
reg [11:0] mq;
   
// program counter
reg[11:0] pc;
wire pc_incr, pc_skip;

// instruction register
reg[2:0] ir;

// extended memory - instruction field & data field
reg [2:0] IF;
reg [2:0] DF;
reg [2:0] IB;
reg [5:0] SF;
reg ib_pending;
   
// user mode
reg UB;
reg UF;
   
//
wire[11:0] memory_bus;
reg ram_we_n;

// processor state
reg[3:0] state, next_state;

reg run;
reg interrupt_enable;
reg interrupt_cycle;
reg interrupt_inhibit;
reg interrupt_skip;

reg interrupt;
reg user_interrupt;

reg io_pulse_1, io_pulse_2, io_pulse_4;

wire [11:0] io_data;
wire io_data_avail;
wire io_interrupt;
wire io_skip;

wire[5:0] io_select;
assign io_select = mb[8:3];

wire skip_condition;

wire fetch;	// memory cycle to fetch instruction
wire deferred;	// memory cycle to get address of operand
wire execute;	// memory cycle to getch (store) operand and execute isn

assign {fetch, deferred, execute} =
	(state[3:2] == 2'b00) ? 3'b100 :
	(state[3:2] == 2'b01) ? 3'b010 :
	(state[3:2] == 2'b10) ? 3'b001 :
				3'b000 ;

wire and,tad,isz,dca,jms,jmp,iot,opr;

assign {and,tad,isz,dca,jms,jmp,iot,opr} =
	(ir == 3'b000) ? 8'b10000000 :
	(ir == 3'b001) ? 8'b01000000 :
	(ir == 3'b010) ? 8'b00100000 :
	(ir == 3'b011) ? 8'b00010000 :
	(ir == 3'b100) ? 8'b00001000 :
	(ir == 3'b101) ? 8'b00000100 :
	(ir == 3'b110) ? 8'b00000010 :
                         8'b00000001 ;


//-------------

parameter F0 = 4'b0000;
parameter F1 = 4'b0001;
parameter F2 = 4'b0010;
parameter F3 = 4'b0011;

parameter D0 = 4'b0100;
parameter D1 = 4'b0101;
parameter D2 = 4'b0110;
parameter D3 = 4'b0111;

parameter E0 = 4'b1000;
parameter E1 = 4'b1001;
parameter E2 = 4'b1010;
parameter E3 = 4'b1011;

ram_4kx12 ram(
	.A(ma),
	.DI(mb),
	.DO(memory_bus),
	.CE_N(1'b0),
	.WE_N(ram_we_n));

/*
 * note: bit numbering is opposite that used in "Computer Engineering"
 * 
 * F1
 *	if opr
 * 	  if MB[8] and !MB[0]
 * 	    begin
 * 		if skip.conditions ^ MB[3]
 * 			pc <= pc + 2
 * 		if skip.conditions == MB[3]
 * 			pc <= pc + 1 next
 * 		if MB[7]
 * 			ac <= 0
 */
assign skip_condition =
		(mb[6] && ac[11]) ||
		(mb[5] && ac == 0) ||
		(mb[4] && l == 1);

assign pc_incr =
		(opr & !mb[8]) ||
		(opr && (mb[8] && !mb[0]) && (skip_condition == mb[3])) ||
		iot ||
		(!(opr || iot) && !interrupt_cycle);

assign pc_skip =
		(opr && (mb[8] && !mb[0]) && (skip_condition ^ mb[3])) ||
		(iot && (io_skip || interrupt_skip));
//		(iot && mb[0] && io_skip);
   

pdp8_io io(.clk(clk), .reset_n(reset_n),
	   .iot(iot), .state(state), .pc(pc), .ac(ac), .mb(mb),
	   .io_select(io_select),
	   .io_data_out(io_data),
	   .io_data_avail(io_data_avail),
	   .io_interrupt(io_interrupt),
	   .io_skip(io_skip));

always @(reset_n)
  if (reset_n == 0)
    begin
       pc <= 0;
       ma <= 0;
       mb <= 0;
       ac <= 0;
       mq <= 0;
       l <= 0;
       ir <= 0;
       ram_we_n <= 1;
       state <= 0;
       next_state <= 0;
       run <= 1;
       interrupt_enable <= 0;
       interrupt_cycle <= 0;
       interrupt_inhibit <= 0;
       interrupt_skip <= 0;
       interrupt <= 0;
       user_interrupt <= 0;
       io_pulse_1 <= 0;
       io_pulse_2 <= 0;
       io_pulse_4 <= 0;
       IF <= 0;
       DF <= 0;
       IB <= 0;
       SF <= 0;
       UF <= 0;
       UB <= 0;
       ib_pending <= 0;
    end

initial
  begin
     ram_we_n = 1;
  end

/*
 * cpu state state machine
 * 
 * clock next cpu state at rising edge of clock
 */

always @(posedge clk)
  state <= #1 next_state;

always @(state)
  begin
    case (state)

      // FETCH 
      F0:
	begin
	  interrupt_skip <= 0;
	   
	  if (interrupt && interrupt_enable &&
	      !interrupt_inhibit && !interrupt_cycle)
	    begin
	       $display("interrupt; %b %b %b",
			interrupt, interrupt_enable, interrupt_cycle);
	       interrupt_cycle <= 1;
	       interrupt <= 0;
	       mb <= 12'o4000;
	       ir <= 3'o4;
	       SF <= {IF,DF};
	       IF <= #1 3'b000;
	       DF <= #1 3'b000;
	    end
	  else
	    begin
	      interrupt_cycle <= 0;
	      mb <= memory_bus;
	      ir <= memory_bus[11:9];
	    end

	  next_state <= F1;
	end

      F1:
	begin
//$display("f1: io_skip %b", io_skip);
//$display("f1 - ma %o, mb %o, ir %o", ma, mb, ir);
	   if (opr)
	     begin
		// group 1
		if (!mb[8])
		  begin
//		    $display("f1/g1 - ma %o, mb %o, ac %o l %o", ma, mb, ac,l);

		     if (mb[7]) ac <= 0;
		     if (mb[6]) l <= 0;
		     if (mb[5]) ac <= ~ac;
		     if (mb[4]) l <= ~l;
		  end

		// group 2
		if (mb[8] & !mb[0])
		  begin
//		     $display("f1/g2 - ma %o, mb %o, sc %o, i %o s %o, ac %o l %o",
//			      ma, mb, skip_condition, pc_incr, pc_skip, ac, l);

		     if (mb[7])
		       ac <= 0;
		  end

		// group 3
		if (mb[8] & mb[0])
		  begin
		     if (mb[7]) ac <= 0;
		  end
	     end

	if (iot)
	  begin

	     $display("iot %t, run %b, state %b, pc %o, ir %o, mb %o, io_select %o",
		      $time, run, state, pc, ir, mb, io_select);

	     if (mb[0]) io_pulse_1 <= 1;
	     if (mb[1]) io_pulse_2 <= 1;
	     if (mb[2]) io_pulse_4 <= 1;

	     case (io_select)
	       6'b000000:	// ION, IOF
		 case (mb[2:0])
		   3'b001: interrupt_enable <= 1;
		   3'b010: interrupt_enable <= 0;
		   3'b011: if (interrupt_enable) interrupt_skip <= 1;
		 endcase // case(mb[2:0])

	       6'b010xxx:	// CDF..RMF
		 begin
		    case (mb[2:0])
		      3'b001: DF <= mb[5:3];	// CDF
		      3'b010:			// CIF
			begin
			   IB <= mb[5:3];
			   ib_pending <= 1;
			   interrupt_inhibit <= 1;
			end
		      3'b100:
			case (io_select[2:0])
			  3'b001: ac <= { 6'b0, DF, 3'b0 };	// RDF
			  3'b010: ac <= { 6'b0, IF, 3'b0 };	// RIF
			  3'b011: ac <= { 6'b0, SF };		// RIB
			  3'b100: begin				// RMF
				     IB <= SF[5:3];
				     DF <= SF[2:0];
			  	  end
			endcase // case(io_select[2:0])
		    endcase // case(mb[2:0])
		 end
	     endcase

	     if (io_data_avail)
	       begin
		  ac <= io_data;
	       end
	  end

	if (io_interrupt)
	  interrupt <= 1;

	//$display("f1 io_skip %b skip %b, incr %b", io_skip, pc_skip, pc_incr);
	if (pc_skip)
	  pc <= pc + 2;
	else
	  if (pc_incr)
	    pc <= pc + 1;

	next_state <= F2;
	end

	F2:
	  begin
	    io_pulse_1 <= 0;
	    io_pulse_2 <= 0;
	    io_pulse_4 <= 0;
	    
	    if (opr)
	      begin
		 ma <= {IF,pc};

	     	 // group 3
		if (mb[8] & mb[0])
		  begin
		     $display("f2/g3 - ma %o, mb %o, ac %o l %o", ma, mb, ac,l);
		 
		     case ({mb[6:4]})
		       3'b001: mq <= ac; 
		       3'b100: ac <= ac | mq;
//		       3'b101: tmq <= mq;
		       3'b100: ac <= mq;
		       3'b101: ac <= mq;
		     endcase // case({mb[6:4]})
		  end // if (mb[8] & mb[0])
	      end // if (opr)
	     
	    if (iot)
		ma <= {IF,pc};

	    if (!(opr || iot))
	      begin
		ma[6:0] <= mb[6:0];
		if (!mb[7])
		  ma[11:7] <= 0;
	      end

	  next_state <= F3;
	  end

	F3:
	  begin
	    if (opr)
	      begin
		// group 1
		if (!mb[8])
		  begin
		    if (mb[0])			// IAC
		      {l,ac} <= {l,ac} + 1'b1;
		    if (mb[3:1] == 3'b001)	// BSW
		      {l,ac} <= {l,ac[5:0],ac[11:6]};
		    if (mb[3] && !mb[1])	// RAR
		      {l,ac} <= {ac[0],l,ac[11:1]};
		    if (mb[3] && mb[1])		// RTR
		      {l,ac} <= {ac[1:0],l,ac[11:2]};
		    if (mb[2] && !mb[1])	// RAL
		      {l,ac} <= {ac[11:0],l};
		    if (mb[2] && mb[1])		// RTL
		      {l,ac} <= {ac[10:0],l,ac[11]};
		  end

		 if (!UF)
		   begin
		      // group 2
		      if (mb[8] & !mb[0])
			if (mb[2])
			  ac <= ac | switches;
		      if (mb[1])
			run <= 0;
		   end

		 if (UF)
		   begin
		      // group 2 - user mode (halt & osr)
		      if (mb[8] & !mb[0])
			if (mb[2])
			  user_interrupt <= 1;
		      if (mb[1])
			user_interrupt <= 1;
		   end

		 // group 3
		if (mb[8] & mb[0])
		  begin
		     if (mb[7:4] == 4'b1101) mq <= 0;
		  end
		 
		ir <= 0;
		mb <= 0;
		next_state <= F0;
	      end

	    if (iot)
	      begin
		ir <= 0;
		mb <= 0;
		next_state <= F0;
	      end

	    if (!(opr || iot))
	      begin
		if (!mb[8] & jmp)
		  begin
		    pc <= ma;
		    ir <= 0;
		    mb <= 0;
		    next_state <= F0;
		  end
		
		if (mb[8])
		  begin
		    mb <= 0;
		    next_state <= D0; /* defer */
		  end

		if (!mb[8] & !jmp)
		  begin
		    mb <= 0;
		    next_state <= E0;
		  end
	      end
	end

      // DEFER

      D0:
	begin
	  mb <= memory_bus;
	  next_state <= D1;
	end

      D1:
	begin
	  // auto increment regs
	  if (ma[11:3] == 8'h01)
	    mb <= mb + 1;

	  next_state <= D2;
	end

      D2:
	begin
	  // write back
	  if (ma[11:3] == 8'h01)
	    ram_we_n <= 0;

	  ma <= #1 {DF,mb};
	  next_state <= D3;
	end

      D3:
	begin
	  ram_we_n <= 1;

	  if (jmp)
	    begin
	      pc <= mb;
	      ir <= 0;
	      mb <= 0;
	      next_state <= F0;
	    end

	  if (!jmp)
	    begin
	      mb <= 0;
	      next_state <= E0;
	    end
	end

      // EXECUTE

      E0:
	begin
	  mb <= memory_bus;
	  next_state <= E1;
	end

      E1:
	begin
	  if (and)
	    ;

	  if (isz)
	    begin
	      mb <= mb + 1;
	      if (mb == 12'b111111111111)
	        pc <= pc + 1;
	    end

	  if (dca)
	    mb <= ac;

	  if (jms)
	    mb <= pc;

	  next_state <= E2;
	end

      E2:
	begin
	  if (isz || dca || jms)
	    ram_we_n <= 0;

	  if (~jms)
	    ma <= #1 {IF,pc};

	  if (jms)
	    ma <= #1 {ma[14:12], ma[11:0] + 1};

	  next_state <= E3;
	end

      E3:
	begin
	  ram_we_n <= 1;

	  if (and)
	    ac <= ac & mb;

	  if (tad)
	    {l,ac} <= ac + mb;

	   //if (tad) $display("tad - mb %o, ac %o l %o", mb, ac, l);

	  if (dca)
	    ac <= 0;

	  if (jms)
	    pc <= ma;

	  ir <= 0;
	  next_state <= F0;
	end
    endcase
  end

endmodule

/* 4kx12 static ram */
module ram_4kx12(A, DI, DO, CE_N, WE_N);

  input[14:0] A;
  input[11:0] DI;
  input CE_N, WE_N;
  output[11:0] DO;

  reg[11:0] ram [0:32767];
  integer i;

  initial
    begin
      for (i = 0; i < 32768; i=i+1)
        ram[i] = 12'b0;

	ram[15'o0000] = 12'o5177;
	ram[15'o0200] = 12'o7300;
	ram[15'o0201] = 12'o1300;
	ram[15'o0202] = 12'o1301;
	ram[15'o0203] = 12'o3302;
	ram[15'o0204] = 12'o7402;
	ram[15'o0205] = 12'o5200;

`include "focal.v"
	ram[15'o0000] = 12'o5404;
	ram[15'o0004] = 12'o0200;
    end

  always @(negedge WE_N)
    begin
       if (CE_N == 0)
        begin
	   $display("ram: write [%o] <- %o", A, DI);
           ram[ A ] = DI;
        end
    end

//always @(A)
//  begin
//    $display("ram: ce %b, we %b [%o] -> %o", CE_N, WE_N, A, ram[A]);
//  end

//  assign DO = ram[ A ];
assign DO = (^A === 1'bX || A === 1'bz) ? ram[0] : ram[A];

endmodule

