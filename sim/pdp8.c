/*
 * basic pdp-8i behavioral model
 * ment to look and act like the verilog model
 * brad@heeltoe.com
 */

#include <stdio.h>
#include <string.h>
#include <fcntl.h>

typedef unsigned char u8;
typedef unsigned short u12;
typedef unsigned short u15;
typedef unsigned char u3;

u8 binfile[16*1024];
int binfile_size;

#define MEMSIZE (32*1024)
u12 mem[32*1024];

int d_load = 0;
int d_fetch = 0;
int d_decode = 0;
int d_cycle = 0;
int d_mem = 0;
int d_trace = 0;

int loadbin(char *fn)
{
    int f, ch, o;
    int rubout, newfield, state, high, low, done;
    int word, csum;
    u12 origin, field;

    f = open(fn, O_RDONLY);
    if (f < 0) {
        perror(fn);
        return -1;
    }

    binfile_size = read(f, binfile, sizeof(binfile));

    if (d_load) printf("binload: %d bytes\n", binfile_size);

    done = 0;
    for (o = 0; o < binfile_size && !done; o++) {
        ch = binfile[o];

        if (rubout) {
            rubout = 0;
            continue;
        }

        if (ch == 0377) {
            rubout = 1;
            continue;
        }

        if (ch > 0200) {
            newfield = (ch & 070) << 9;
            continue;
        }

        switch (state) {
        case 0:
            /* leader */
            if ((ch != 0) && (ch != 0200)) state = 1;
            high = ch;
            break;

        case 1:
            /* low byte */
            low = ch;
            state = 2;
            break;

        case 2:
            /* high with test */
            word = (high << 6) | low;
            if (ch == 0200) {
                if ((csum - word) & 07777) {
                    printf("loadbin: checksum error\n");
                }
                done = 1;
                continue;
            }
            csum = csum + low + high;
            if (word >= 010000) {
                origin = word & 07777;
            } else {
                if ((field | origin) >= MEMSIZE) {
                    printf("loadbin: too big\n");
                }

                if (d_load) printf("mem[%o] = %o\n", field|origin, word&07777);

                mem[field | origin] = word & 07777;
                origin = (origin + 1) & 07777;
            }
            field = newfield;
            high = ch;
            state = 1;
            break;
        }
    }

    close(f);
    return 0;
}

char *disassem(int pc, int mb)
{
    static char buf[128];
    char b1[64];
    int i, b[12];

    for (i = 0; i < 12; i++)
        b[i] = mb & (1 << i);

    buf[0] = 0;

    switch ((mb & 07000) >> 9) {
    case 0: sprintf(buf, "and "); goto d;
    case 1: sprintf(buf, "tad "); goto d;;
    case 2: sprintf(buf, "isz "); goto d;;
    case 3: sprintf(buf, "dca "); goto d;;
    case 4: sprintf(buf, "jms "); goto d;;
    case 5: sprintf(buf, "jmp ");
    d:
        if (b[8]) strcat(buf, "I ");
        if (!b[7]) strcat(buf, "Z ");
        sprintf(b1, "%o", mb & 0177);
        strcat(buf, b1);
        break;

    case 6: sprintf(buf, "iot "); break;

    case 7:
        if (b[8] == 0) {
            if (b[7]) strcat(buf, "cla ");
            if (b[6]) strcat(buf, "clf ");
            if (b[5]) strcat(buf, "cma ");
            if (b[4]) strcat(buf, "cmla ");
            switch ((mb & 016) >> 1) {
            case 1: strcat(buf, "bsw "); break;
            case 2: strcat(buf, "ral "); break;
            case 3: strcat(buf, "rtl "); break;
            case 4: strcat(buf, "rar "); break;
            case 5: strcat(buf, "rtr "); break;
            }
            if (b[0]) strcat(buf, "iac ");
        } else 
            if (b[8] && b[0] == 0) {
                if (b[7]) strcat(buf, "cla ");

                if (b[6]) strcat(buf, "sma ");
                if (b[5]) strcat(buf, "sza ");
                if (b[4]) strcat(buf, "snl ");
                if (b[3]) strcat(buf, "skp ");

                if (b[2]) strcat(buf, "osr ");
                if (b[1]) strcat(buf, "hlt ");
            } else {
                if (b[7]) strcat(buf, "cla ");
                if (b[6]) strcat(buf, "mqa ");
                if (b[5]) strcat(buf, "sca ");
                if (b[4]) strcat(buf, "mql ");
            }
        break;
    }

    return buf;
}

typedef unsigned char wire;
typedef unsigned char reg;

u15 pc;
u12 ac;
u3 UF, DF, IF, IB, SF;
reg l;

u12 ma;
u12 mq;

u12 switches;
wire run;
wire interrupt;
wire user_interrupt;
wire interrupt_enable;
wire interrupt_inhibit;
wire interrupt_cycle;
wire interrupt_skip;
wire ib_pending;
wire io_interrupt;
wire io_skip, condition_mux, skip_condition, pc_incr, pc_skip;

int tt_data;
int tt_countdown;
//int io_cycle_count;
wire io_data_avail;
u12 io_data;

wire ram_we;

void
execute(void)
{
    u12 memory_bus, mb;
    wire ir;
    wire and, tad, isz, dca, jms, jmp, iot, opr;
    u12 io_select;

F0:
    memory_bus = mem[(IF<<12) | pc];

    interrupt_skip = 0;
    if (interrupt && interrupt_enable &&
        !interrupt_inhibit && !interrupt_cycle)
    {
        interrupt_cycle = 1;
        interrupt = 0;
        interrupt_enable = 0;
        mb = 04000;
        memory_bus = mb;
        ir = 4;
        SF = (IF<<3)|DF;
        IF = 0;
        DF = 0;
        printf("xxx interrupt @ %o\n", pc);
    } else {
        interrupt_cycle = 0;
        mb = memory_bus;
    }

    if (d_fetch) {
        printf("\n");
        printf("fetch: if=%o, pc=%04o %04o %s\n", IF, pc, mb, disassem(pc, mb));
        printf("       l=%d ac=%04o\n", l, ac);
    }

    if (d_trace) {
        printf("pc %4o ir %4o l %o ac %4o ion %d\n",
               pc, mb, l, ac, interrupt_enable);
    }

#define bitmask(l) ((unsigned int)0xffffffff >> (31-(l)))
#define mb_bit(n)  ((mb & (1<<n)) ? 1 : 0)
#define mb_bits(h,l)  ((mb >> l) & bitmask(h-l))

    ir = (memory_bus >> 9) & 7;

    and = ir == 0;
    tad = ir == 1;
    isz = ir == 2;
    dca = ir == 3;
    jms = ir == 4;
    jmp = ir == 5;
    iot = ir == 6;
    opr = ir == 7;

    skip_condition =
        ((mb_bit(6) && (ac & 04000)) ||
         (mb_bit(5) && (ac == 0)) ||
         (mb_bit(4) && (l == 1))) ? 1 : 0;

    pc_incr =
        (opr & !mb_bit(8)) ||
        (opr && (mb_bit(8) && !mb_bit(0)) && (skip_condition == mb_bit(3))) ||
        iot ||
        (!(opr || iot) && !interrupt_cycle);

    pc_skip =
        (opr && (mb_bit(8) && !mb_bit(0)) && (skip_condition ^ mb_bit(3))) ||
        (iot && (io_skip || interrupt_skip));
//		(iot && mb_bit(0) && io_skip);

    if (d_decode) {
        printf("and %d tad %d isz %d dca %d jms %d jmp %d ito %d opr %d\n",
               and, tad, isz, dca, jms, jmp, iot, opr);
        printf("skip %d, pc_incr %d, pc_skip %d\n",
               skip_condition, pc_incr, pc_skip);

        printf("condition_mux %o, skip_condition %o; %o %o %o\n",
               condition_mux, skip_condition,
               mb_bit(3),
               (skip_condition == mb_bit(3)),
               (skip_condition ^ mb_bit(3)));
    }

F1:
    if (opr) {
        /* group 1 */
        if (mb_bit(8) == 0) {
            if (mb_bit(7)) ac = 0;
            if (mb_bit(6)) l = 0;
            if (mb_bit(5)) ac = ~ac & 07777;
            if (mb_bit(4)) l = ~l & 1;
        }
        /* group 2 */
        if (mb_bit(8) && !mb_bit(0)) {
            if (mb_bit(7)) ac = 0;
        }

        /* group 3 */
        if (mb_bit(8) & mb_bit(0)) {
            if (mb_bit(7)) ac = 0;
        }
    }

    io_select = (mb >> 3) & 077;

    if (iot) {
        if (d_cycle) printf("iot; io_select %o\n", io_select);

        switch (io_select) {
        case 0:	// ION, IOF
            switch (mb & 7) {
            case 1:
                //printf("xxx ints on\n");
                interrupt_enable = 1;
                break;
            case 2:
                if (d_fetch) printf("xxx ints off\n");
                interrupt_enable = 0;
                break;
            case 3: if (interrupt_enable) interrupt_skip = 1;  break;
            }
            break;

        case 020: case 021: case 022: case 023:	// CDF..RMF
        case 024: case 025: case 026: case 027:
            switch (mb & 7) {
            case 1:
                DF = (mb >> 3) & 7;	// CDF
                break;
            case 2:			// CIF
                IB = (mb >> 3) & 7;
                ib_pending = 1;
                interrupt_inhibit = 1;
                break;
            case 4:
                switch (io_select & 7) {
                case 1: ac = DF << 3;break;// RDF
                case 2: ac = IF << 3;break;// RIF
                case 3: ac = SF;break; // RIB
                case 4: // RMF
                    IB = (SF >> 3) & 7;
                    DF = SF & 7;
                    break;
                }
                break;
            }
        }

#if 1
        switch (io_select) {
        case 004:
            if (mb_bit(0)) {
                printf("tls; tt_countdown %d\n", tt_countdown);
                if (tt_countdown <= 0)
                    io_skip = 1;
            }
            if (mb_bit(1)) {
            }
            if (mb_bit(2)) {
                tt_data = ac;
                tt_countdown = 98/*100*/;
            }
            break;
        }

#endif
    }

    if (tt_countdown > 0) {
        tt_countdown--;
        if (tt_countdown == 0) {
            printf("xxx tx_data %o\n", tt_data);
            io_interrupt = 1;
        }
    }

//    io_cycle_count++;
//    if (io_cycle_count > 100) {
//        io_cycle_count = 0;
//        io_interrupt = 1;
//        //printf("xxx io_interrupt\n");
//    }

    if (io_interrupt) {
        interrupt = 1;
        io_interrupt = 0;
    }

    if (pc_skip || io_skip)
        pc = pc + 2;
    else
        if (pc_incr)
	    pc = pc + 1;

    io_skip = 0;

F2:
    if (opr) {

        ma = (IF<<12) | pc;

        // group 3
        if (mb_bit(8) & mb_bit(0))
            switch (mb_bits(6,4)) {
            case 1: mq = ac; break; 
            case 2: ac = ac | mq; break; 
//	case 5: tmq <= mq; break; 
            case 4: ac = mq; break; 
            case 5: ac = mq; break;
            }
    }
	     
    if (iot)
        ma = (IF<<12) | pc;

    if (!(opr || iot)) {
//        ma = (DF<<12) | ((mb_bit(7) ? (ma & 07600) : 0) | mb_bits(6,0));
        ma = (IF<<12) | ((mb_bit(7) ? (pc & 07600) : 0) | mb_bits(6,0));
        if (d_cycle) printf("ea if=%o df=%o, pc %o, ma=%05o (bits %o)\n", 
                            IF, DF, pc, ma, mb_bits(6,0));
    }

#define get_l_ac()  ( (l << 12) | ac )
#define set_l_ac(v)  do { unsigned int vv = (v); \
    			  l = (vv >> 12) & 1; ac = vv & 07777; } while(0);

F3:
    if (opr) {

        // group 1
        if (!mb_bit(8)) {
            if (mb_bit(0))			// IAC
                set_l_ac( get_l_ac() + 1 );

            switch (mb_bits(3,1)) {
            case 1:		// BSW
                set_l_ac( ((get_l_ac() & 077) << 6) |
                          ((get_l_ac() & 07700) >> 6) );
                break;

            case 2:		// RAL
                //printf("ral\n");
                set_l_ac( ((get_l_ac() & 010000) >> 12) |
                          (ac << 1) );
                break;

            case 3:		// RTL
                //printf("rtl\n");
                set_l_ac( ((get_l_ac() & 010000) ? 2 : 0) |
                          ((get_l_ac() & 004000) ? 1 : 0) |
                          (ac << 2) );
                break;

            case 4:		// RAR
                //printf("rar\n");
                set_l_ac( ((ac & 1) << 12) |
                          (get_l_ac() >> 1) );
                break;

            case 5:		// RTR
                //printf("rtr\n");
                set_l_ac( ((ac & 1) ? 004000 : 0) |
                          ((ac & 2) ? 010000 : 0) |
                          (get_l_ac() >> 2) );
                break;
            }
        }

        if (!UF) {
            // group 2
            if (mb_bit(8) & !mb_bit(0)) {
                if (mb_bit(2))
                    ac = ac | switches;
                if (mb_bit(1)) {
                    printf("halt!\n");
                    run = 0;
                }
            }
        }

        if (UF) {
            // group 2 - user mode (halt & osr)
            if (mb_bit(8) & !mb_bit(0)) {
                if (mb_bit(2))
                    user_interrupt = 1;
                if (mb_bit(1))
                    user_interrupt = 1;
            }
        }

        // group 3
        if (mb_bit(8) && mb_bit(0))
            if (mb_bits(7,4) == 016) mq = 0;
		 
        ir = 0;
        mb = 0;
        return;
    }

    if (iot) {
        ir = 0;
        mb = 0;
        return;
    }

    if (!(opr || iot)) {
                
        if (!mb_bit(8) & jmp) {
            pc = ma;
            ir = 0;
            mb = 0;
            return;
        }
		
        if (mb_bit(8)) {
            mb = 0;
            goto D0;
        }

        if (!mb_bit(8) & !jmp) {
            mb = 0;
            goto E0;
        }
    }

    // DEFER

D0:
    memory_bus = mem[ma];
    if (d_cycle) printf("D0: ");
    if (d_mem) printf("mem read [%o] -> %o\n", ma, memory_bus);
    mb = memory_bus;

    ram_we = 0;
    // auto increment regs

    if (((ma >> 3) & 0377) == 1) {
	mb++;
        ram_we = 1;
    }

    if (ram_we) {
        if (d_cycle) printf("D0: ");
        if (d_mem) printf("mem write [%o] <- %o\n", ma, mb);
        mem[ma] = mb & 07777;
    }
    ram_we = 0;

    ma = (DF << 12) | mb;

    if (jmp) {
        pc = mb;
        ir = 0;
        mb = 0;
        return;
    }

    if (!jmp) {
        mb = 0;
    }

    // EXECUTE
E0:
    mb = mem[ma];
    if (d_cycle) printf("E0: ");
    if (d_mem) printf("mem read [%o] -> %o\n", ma, mb);

    if (isz) {
        if (mb == 07777) pc++;
        mb++;
    }

    if (dca)
        mb = ac;

    if (jms)
        mb = pc;

    if (isz || dca || jms) {
        ram_we = 1;
    }

    if (ram_we) {
        if (d_cycle) printf("E0: ");
        if (d_mem) printf("mem write [%o] <- %o\n", ma, mb);
        mem[ma] = mb & 07777;
    }
    ram_we = 0;

    // note timing here; ma above is different

    if (!jms)
        ma = (IF << 12) | pc;

    if (jms)
        ma = ((ma & 070000) << 12) | ((ma & 07777) + 1);

    if (and)
        ac = ac & mb;

    if (tad) {
        set_l_ac( get_l_ac() + mb );
    }

    if (dca)
        ac = 0;

    if (jms) {
        if (d_fetch) printf("jms - ma %o\n", ma);
        pc = ma;
    }

    ir = 0;

}

void
loop(void)
{
    run = 1;

    IF = (pc & 070000) >> 12;
    DF = IF;
    pc &= 07777;

    while (1) {
        if (!run)
            break;
        execute();
    }
}

main()
{
    if (1) {
        d_load = 0;
        d_fetch = 0;
        d_decode = 0;
        d_cycle = 0;
        d_trace = 1;
        d_mem = 1;
    }

    if (0) {
        d_load = 0;
        d_fetch = 1;
        d_decode = 1;
        d_cycle = 1;
        d_trace = 0;
        d_mem = 1;
    }

    if (0) {
        loadbin("../tss8/tss8_init.bin");
        pc = 024200;
    }

    if (1) {
        loadbin("../images/focal569.bin");
        pc = 0200;
    }

    loop();
}


/*
 * Local Variables:
 * indent-tabs-mode:nil
 * c-basic-offset:4
 * End:
*/
