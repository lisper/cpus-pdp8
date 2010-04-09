/*
  RF08

  2048 words/track
  128 tracks

  mapped to IDE drive;
    2048 x 12 bits -> 2048 x 16 bits = 8 blocks of 512 bytes
    each track is 8 blocks
    each disk is (128 * 8) = 1024 blocks
  
  ide_block = (track * 8) + (word / 256)
  ide_block_index = word % 256

  ema bits 7 & 8 select which rs08 disk
  ema bits 6 - 0 select disk head  (track #)
 
  dma contains lower disk word address

  writes to dma trigger; adc is asserted after match w/disk
 
  1       111
  98765432109876543210  
           wwwwwwwwwww

  -------------

  memory:

 	7750 word count
	7751 current address
 
  iot:
 
  660x
  661x
  662x
  664x

  6601 DCMA	Generates System Clear Pulse (SCLP) at IOP time 1.
		Clears disk memory eaddress(DMA), Parity Eror Flag (PEF),
		Data Request Late Flag (DRL), and sets logic to
		initial state for read or write. Does not clear
		interrupt enable or extended address register.
 
  6603 DMAR	Generate SCLP at IOP time 1. At IOP time 2, loads DMA
		with AC and clears AC. Read continues for number words
		in WC register (7750)
  
  6605 DMAW	Generate SCLP at IOP time 1. At IOP time 4, loads DMA
		with AC and clears AC. When the disk word address is located
		writing begins, disk address is incremented for each
		word written
  
  6611 DCIM	clears disk interrupt enable and the extended address
		registers at IOP time 1.

  6612 DSAC	At IOP time 2, skip if Address Confirmed (ADC) set indicating
		the DMA address and disk word address compare. AC is then
 		cleared.
 
  6615 DIML	At IOP time 1, clear interrupt enable and memory address
		extension registers. At IOP time 4, load interrupt enable
		and memory address extension register with AC, clear AC.
 
  6616 DIMA	Clear ??? at IOP time 2. At IOP time 4 load AC with status 
 		register.
 
  6621 DFSE	skip on error skip if DRL, PER WLS or NXD set
 
  6622 ???	skip if data completion DCF set
 
  6623 DISK	skip on error or data completion; enabled at IOP 2
 
  6626 DMAC	clear ac at IOP time 2 load AC from DMA  at IOP time 4.
 
  6641 DCXA	Clears EMA
 
  6643 DXAL	Clears and loads EMA from AC. At IOP time 1, clear EMA, at
		IOP time 2, load EMA with AC. Clear AC
 
  6645 DXAC	Clears AC and loads EMA into AC

  6646 DMMT	Maintenance

 uses 3 cycle data break
 
 ac 7:0, ac 11:0 => 20 bit {EMA,DMA}
 20 bit {EMA,DMA} = { disk-select, track-select 6:0, word-select 11:0 }

 status
*/

//  EIE = WLS | DRL | NXD | PER

/*
 3 cycle data break
 
 1. An address is read from the device to indicate the location of the
word count register. This location specifies the number of words in
the block yet to be transferred.  The address is always the same for a
given device.
 
 2. The content of the specficified word count register is read from
memory and incremented by one.  To transfer a block of n words, the
word count is set to -n during the programmed initialization of the
device.  When this register is incremented to 0, a pulse is sent to
the device to terminate the transfer.
 
 3. The location after the word count register contains the current
address register for the device transfer.  The content of this
register is set to 1 less than the location to be affected by the next
transfer. To transfer a block beginning at location A, the register is
originally set to A-1.

 4. The content of the current address register is incremented by 1
and then used to specify the location affected by the transfer.
 
 After the transfer of information has been accomplished through the
data break factility, input data (or new output data) is processed,
usually through the program interrupt facility.  An interrupt is
requested when the data transfer is completed and the service routine
will process the information.


 -----------    -----------    -----------    ----------- 

 external signals:

 ma_out
 ram_write_req
 ram_read_req
 ram_done
 mb_in
 mb_out 
 
 DISK STATE MACHINE:
  
 // setup
   wire [8:0] track;
   wire [11:0] ide_block;
   wire [7:0] ide_block_index;
 
   track = {ema[7:0], dma[11]};
   ide_block = {1'b0, track, 3'b0} + {8'b0, dma[11:8]}
   ide_block_index = dma[7:0];

 idle
 
 start-xfer
   read wc
   read addr

   if read
     goto check-xfer-read
   else
     goto begin-xfer-write
 
 check-xfer-read
   if disk-addr-page == memory-buffer-addr-page
      read memory-buffer-page[offset]
      goto next-xfer-read
   else
      if memory-buffer-dirty == 0
         goto read-new-page
      else
         goto write-old-page
 
 next-xfer-read
   write M[addr]
   goto next-xfer-incr
 
 next-xfer-incr
   incr addr
   incr wc
   if wc == 0
      goto done-xfer
   if read
     goto check-xfer-read
   else
     goto begin-xfer-write
 
 begin-xfer-write
   read data from memory
   goto check-xfer-write
  
 check-xfer-write
   if disk-addr-page == memory-buffer-addr-page
      write memory-buffer-page[offset]
      set memory-buffer-dirty = 1
      goto next-xfer-incr
   else
      if memory-buffer-dirty == 0
         goto read-new-page
      else
         goto write-old-page

 done-xfer
   write addr
   write wc
   set done/interrupt
   goto idle

 read-new-page
   read block from ide
   set memory-buffer-addr-page
   set memory-buffer-dirty = 0
   if read
     goto check-xfer-read
   else
     goto check-xfer-write
 
 write-old-page
   write block to ide
   set memory-buffer-dirty = 0
   goto read-new-page
 
 -----------    -----------    -----------    ----------- 
 
 DMA STATE MACHINE:

 wire [7:0] disk_buffer_index;
 wire databreak_done_req;
 wire databreak_notdone_req;

 reg databreak_done;
  
 always @(posedge clk)
   if (databreak_done_req)
     databreak_done <= 1;
   else
     if (databreak_notdone_req)
       databreak_done <= 0;

 always @(posedge clk)
   if (db_state == DB9)
     begin
 	ema <= new_da[18:11];
  	dma <= new_da[10:0];
     end
 
 db_done = 0; 
 db_eob = 0; 
 ram_write = 0;
 databreak_done_req = 0;
 databreak_notdone_req = 0;
 
 // idle
 DB_idle:
 
 // read word count
 DB_start_xfer1:
	ma_out = wc-address;
 	ram_read_req = 1;
 	if ram_done db_next_state = DB_start_xfer2;

 // read addr
 DB_start_xfer2:
 	wc = mb_in;
	ma_out = wc-address | 1;
 	ram_read_req = 1;
        db_next_state = DB_start_xfer3; 
 
 DB_start_xfer3:
 	ram_addr = mb_in
 	db_next_state = DB_check_xfer_read;

 // read buffer 
 DB_check_xfer_read:
 	buffer_addr = disk_addr_offset
        if disk-addr-page == memory-buffer-addr-page
  	  db_next_state = DB_next_xfer_read;
        else
          if buffer_dirty == 0
 	    db_next_state = DB_read_new_page;
          else
  	    db_next_state = DB_write_old_page;

 // advance
 DB_next_xfer_read: 
        ma_out = ram_addr
 	mb_out = buffer_out
        ram_write_req = 1
 	if ram_done db_next_state = DB_next_xfer_incr;
 
 DB_next_xfer_incr: 
        disk_addr <= disk_addr + 1
 	new_da = {ema, dma} + 19'b1;

        ram_addr <= ram_addr + 1
        wc <= wc + 1
 	done = wc == 07777
 	if done
  	    db_next_state = DB_done_xfer;
        else
            if read
 	      db_next_state = DB_check_xfer_read; 
            else
              db_next_state = DB_begin_xfer_write; 

 // write to ram
 DB7_begin_xfer_write:
        ma_out = ram_addr
 	mb_out = buffer_out
        ram_read_req = 1
 	if ram_done db_next_state = DB_check_xfer_write;

 // read buffer
 DB_check_xfer_write:
        buffer_addr = disk_addr_offset
        if disk-addr-page == memory-buffer-addr-page
           buffer_wr = 1
           buffer-dirty <= 1
           db_next_state = DB_next_xfer_incr; 
        else
           if buffer-dirty == 0
             db_next_state = DB_read_new_page
           else
             db_next_state = DB_write_old_page

 // done 
 DB_done_xfer:
	ma_out = wc-address;
        mb_out = ram_addr
 	ram_write_req = 1;
 	if ram_done db_next_state = DB_start_xfer1;
 
 DB_done_xfer1:
	ma_out = wc-address | 1;
        mb_out = wc
 	ram_write_req = 1;
 	if ram_done db_next_state = DB_done_xfer2;

 DB_done_xfer2:
   set done/interrupt
        db_next_state = DB_idle

 DB_read_new_page:
   read block from ide
   set memory-buffer-addr-page
        buffer-dirty <= 0
	if read
	  db_next_state = DB_check_xfer_read
 	else
	  db_next_state = DB_check_xfer_write
 
 DB_write_old_page:
   write block to ide
        buffer-dirty <= 0
	db_next_state = DB_read-new-page
 


------
 
 // finish read/write
 DB9:
	disk_buffer_index = disk_buffer_index + 1;
 
 	new_da = {ema, dma} + 19'b1;

	if (databreak_done)
	  begin
 	    db_done = 1;
 	    db_next_state = DB_idle;
 	  end
 	else
	  if (disk_buffer_index == 8'b0)
	    begin 
	      db_next_state = DB_idle;
 	      db_eob = 1;
 	    end
          else
            db_next_state = DB1;
 
 */


module pdp8_rf(clk, reset, iot, state, mb,
	       io_data_in, io_data_out, io_select, io_selected,
	       io_data_avail, io_interrupt, io_skip);
   
   input clk, reset, iot;
   input [11:0] io_data_in;
   input [11:0]      mb;
   input [3:0] 	     state;
   input [5:0] 	     io_select;

   output reg 	     io_selected;
   output reg [11:0] io_data_out;
   output reg 	     io_data_avail;
   output 	     io_interrupt;
   output reg 	     io_skip;
   
   parameter 	     F0 = 4'b0000;
   parameter 	     F1 = 4'b0001;
   parameter 	     F2 = 4'b0010;
   parameter 	     F3 = 4'b0011;

   parameter PCA_bit = 12'o4000;	// photocell status
   parameter DRE_bit = 12'o2000;	// data req enable
   parameter WLS_bit = 12'o1000;	// write lock status
   parameter EIE_bit = 12'o0400;	// error int enable
   parameter PIE_bit = 12'o0200;	// photocell int enb
   parameter CIE_bit = 12'o0100;	// done int enable
   parameter MEX_bit = 12'o0070;	// memory extension
   parameter DRL_bit = 12'o0004;	// data late error
   parameter NXD_bit = 12'o0002;	// non-existent disk
   parameter PER_bit = 12'o0001;	// parity error

   wire      ADC;
   wire      DCF;
   reg [11:0] DMA;
   reg [7:0]  EMA;
   reg 	      PEF;
   reg 	      rf08_rw;
   reg 	      rf08_start_io;
   reg 	      CIE, DRE, DRL, EIE, MEX, NXD, PCA, PER, PIE, WLS;
   
   assign DCF = 1'b0;
   assign ADC = DMA == /*DWA??*/0;

   parameter DB_idle = 4'b0000;
   parameter DB1 = 4'b0001;
   parameter DB2 = 4'b0010;
   parameter DB3 = 4'b0011;
   parameter DB4 = 4'b0100;
   parameter DB5 = 4'b0101;
   parameter DB6 = 4'b0110;
   parameter DB7 = 4'b0111;
   parameter DB8 = 4'b1000;
   parameter DB9 = 4'b1001;

   wire [3:0] db_next_state;
   reg [3:0]  db_state;
   reg 	      dma_start;

   //
   assign io_interrupt = 1'b0;

   // combinatorial
   always @(state or
	    ADC or DRL or PER or WLS or NXD or DCF)
     begin
	// sampled during f1
	io_skip = 0;
	io_data_out = io_data_in;
	io_data_avail = 1'b1;
	dma_start = 1'b0;
	io_selected = 1'b0;
	
	if (state == F1 && iot)
	  case (io_select)
	    6'o60:
	      begin
		 io_selected = 1'b1;
		 case (mb[2:0])
		   6'o03: // DMAR
		     begin
			io_data_out = 0;
			dma_start = 1;
		     end
		   6'o03: // DMAW
		     begin
			io_data_out = 0;
			dma_start = 1;
		     end
		 endcase
	      end // case: 6'o60
	    
	    6'o61:
	      begin
		 io_selected = 1'b1;
		 case (mb[2:0])
		   3'o2: // DSAC
		     if (ADC)
		       begin
			  io_skip = 1;
			  io_data_out = 0;
		       end
		   3'o6: // DIMA
		     io_data_out = { PCA,
				     DRE,WLS,EIE,
				     PIE,CIE,MEX, 
				     DRL,NXD,PER };
		   3'o5: // DIML
		     io_data_out = 0;
		 endcase // case(mb[2:0])
	      end
	    
	    6'o62:
	      begin
		 io_selected = 1'b1;
		 case (mb[2:0])
		   3'o1: // DFSE
		     if (DRL | PER | WLS | NXD)
		       io_skip = 1;
		   3'o2: // ???
		     if (DCF)
		       io_skip = 1;
		   3'o3: // DISK
		     if (DRL | PER | WLS | NXD | DCF)
		       io_skip = 1;
		   3'o6: // DMAC
		     io_data_out = DMA;
		 endcase 
	      end
		   
	    6'o64:
	      begin
		 io_selected = 1'b1;
		 case (mb[2:0])
		   3: // DXAL
		     io_data_out = 0;
		   5: // DXAC
		     io_data_out = EMA;
		 endcase // case(mb[2:0])
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
	       
	       if (iot)
		 case (io_select)
		   6'o60: // DCMA
		     if (mb[2:0] == 3'b001)
		       begin
			  DMA <= 0;
			  PEF <= 0;
			  DRL <= 0;
		       end
		   6'o61:
		     case (mb[2:0])
		       3'o1: // DCIM
			 begin
			    CIE <= 0;
			    EMA <= 0;
			 end
		       3'o2: // DSAC
			 begin
			 end
		       3'o5: // DIML
			 begin
			    CIE <= io_data_in[8];
			    EMA <= io_data_in[7:0];
			 end
		     endcase // case(mb[2:0])
		 endcase
	    end

	  F1:
	    if (iot)
	      begin
		 if (io_select == 6'o60 || io_select == 6'o64)
		 $display("iot2 %t, state %b, mb %o, io_select %o",
			  $time, state, mb, io_select);

		 case (io_select)
		   6'o60:
		     case (mb[2:0])
		       6'o03: // DMAR
			 begin
			    // clear ac
			    DMA <= io_data_in;
			    rf08_start_io <= 1;
			    rf08_rw <= 0;
			 end

		       6'o03: // DMAW
			 begin
			    // clear ac
			    DMA <= io_data_in;
			    rf08_start_io <= 1;
			    rf08_rw <= 1;
			 end
		     endcase // case(mb[2:0])

		   6'o64:
		     case (mb[2:0])
		       1: // DCXA
			 EMA <= 0;
		       3: // DXAL
			 // clear ac
			 EMA <= io_data_in;
		     endcase
		   
                 endcase

	      end // if (iot)

//	  F2:
//	    begin
//	       if (io_interrupt)
//	       	 $display("iot2 %t, reset io_interrupt", $time);
//
//	       // sampled during f0
//	       io_interrupt <= 0;
//	    end

       endcase // case(state)

   //
   assign db_next_state =
			 dma_start ? DB1 :
			 DB_idle;
   
   always @(posedge clk)
     if (reset)
       db_state <= DB_idle;
     else
       db_state <= db_next_state;
   
	  
endmodule
