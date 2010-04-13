/* pli_rf.c */
/*
 * minimal implementation of rf08 disk controller,
 * designed to be shared by the rtl simulation and simh
 * so they both operate the same way
 * (to facilitate comparisons of cpu flow)
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <fcntl.h>

#ifdef unix
#include <unistd.h>
#endif

#ifdef _WIN32
#endif

#include "vpi_user.h"

#ifdef __CVER__
#include "cv_vpi_user.h"
#endif

#ifdef __MODELSIM__
#include "veriuser.h"
#endif

#define USE_DMA

//typedef int int32;
typedef unsigned short u16;
typedef unsigned int u22;

extern PLI_INT32 pli_ram(void);
PLI_INT32 pli_rk(void);

static char *instnam_tab[10]; 
static int last_evh;

static char last_iopr_bit;
static char last_iopw_bit;
static char last_dma_ack_bit;

static int io_rk_debug = 0;
static int rk_debug = 0;

static struct rk_context_s {
    u16 rkds;
    u16 rkcs;
    u16 rkda;
    u16 rkwc;
    u16 rkba;
    u16 rker;

    int rk_write_prot;
    int rk_func;
    int rk_fd;

    int track;
    int sect;
    int cyl;
    int rkintq;

    int has_init;

    int dma_cycle;
    int dma_write;
    int dma_read;
    int dma_wc;
    u22 dma_addr;
    int dma_index;

    u16 rkxb[256*256];

} rk_context[10];

#ifndef CSR_GO
#define CSR_GO		(1 << 0)
#define CSR_IE		(1 << 6)
#define CSR_DONE	(1 << 7)
#define CSR_BUSY	(1 << 11)
#endif

/* RKDS */

#define RKDS_SC		0000017	/* sector counter */
#define RKDS_ON_SC	0000020	/* on sector */
#define RKDS_WLK	0000040	/* write locked */
#define RKDS_RWS	0000100	/* rd/wr/seek ready */
#define RKDS_RDY	0000200	/* drive ready */
#define RKDS_SC_OK	0000400	/* SC valid */
#define RKDS_INC	0001000	/* seek incomplete */
#define RKDS_UNSAFE	0002000	/* unsafe */
#define RKDS_RK05	0004000	/* RK05 */
#define RKDS_PWR	0010000	/* power low */
#define RKDS_ID		0160000	/* drive ID */


#define RKER_WCE	0000001	/* write check */
#define RKER_CSE	0000002	/* checksum */
#define RKER_NXS	0000040	/* nx sector */
#define RKER_NXC	0000100	/* nx cylinder */
#define RKER_NXD	0000200	/* nx drive */
#define RKER_TE		0000400	/* timing error */
#define RKER_DLT	0001000	/* data late */
#define RKER_NXM	0002000	/* nx memory */
#define RKER_PGE	0004000	/* programming error */
#define RKER_SKE	0010000	/* seek error */
#define RKER_WLK	0020000	/* write lock */
#define RKER_OVR	0040000	/* overrun */
#define RKER_DRE	0100000	/* drive error */

#define RKER_SOFT	(RKER_WCE+RKER_CSE)		/* soft errors */
#define RKER_HARD	0177740				/* hard errors */

#define	 RKCS_CTLRESET	0
#define	 RKCS_WRITE	1
#define	 RKCS_READ	2
#define	 RKCS_WCHK	3
#define	 RKCS_SEEK	4
#define	 RKCS_RCHK	5
#define	 RKCS_DRVRESET	6
#define	 RKCS_WLK	7
#define RKCS_MEX	0000060	/* memory extension */
#define RKCS_SSE	0000400	/* stop on soft err */
#define RKCS_FMT	0002000	/* format */
#define RKCS_INH	0004000	/* inhibit increment */
#define RKCS_SCP	0020000	/* search complete */
#define RKCS_HERR	0040000	/* hard error */
#define RKCS_ERR	0100000	/* error */
#define RKCS_RW		0006576	/* read/write */

static struct {
    int ord;
    char *name;
    int preset;
    vpiHandle ref;
    vpiHandle aref;
    char bits[32];
    unsigned int value;
} argl[] = {
    { 1, "clk", 0 },
    { 2, "reset", 0 },
    { 3, "iopage_addr", 0 },
    { 4, "data_in", 0 },
    { 5, "data_out", 1 },
    { 6, "decode", 1 },
    { 7, "iopage_rd", 0 },
    { 8, "iopage_wr", 0 },
    { 9, "iopage_byte_op", 0 },
    { 10, "interrupt", 1 },
    { 11, "int_ack", 0 },
    { 12, "vector", 1 },
    { 13, "ide_data_bus", 1 },
    { 14, "ide_dior", 1 },
    { 15, "ide_diow", 1 },
    { 16, "ide_cs", 1 },
    { 17, "ide_da", 1 },
    { 18, "dma_req", 1 },
    { 19, "dma_ack", 0 },
    { 20, "dma_addr", 1 },
    { 21, "dma_data_in", 1 },
    { 22, "dma_data_out", 0 },
    { 23, "dma_rd", 1 },
    { 24, "dma_wr", 1 },
    { 0, NULL, 0 }
};
#define A_RESET (2-1)
#define A_IOPAGE_ADDR (3-1)
#define A_DATA_IN (4-1)
#define A_DATA_OUT (5-1)
#define A_DECODE (6-1)
#define A_IOPAGE_RD (7-1)
#define A_IOPAGE_WR (8-1)
#define A_IOPAGE_BYTE_OP (9-1)
#define A_INTERRUPT (10-1)
#define A_INT_ACK (11-1)
#define A_VECTOR (12-1)
#define A_DMA_REQ (18-1)
#define A_DMA_ACK (19-1)
#define A_DMA_ADDR (20-1)
#define A_DMA_DATA_IN (21-1)
#define A_DMA_DATA_OUT (22-1)
#define A_DMA_RD (23-1)
#define A_DMA_WR (24-1)

/* ----------------- */

void rk_raw_write_memory(struct rk_context_s *rk, int ma, u16 data)
{
    extern u16 *M;
    vpi_printf("dma %06o <- %06o\n", ma, data);

    if (ma > 1024*1024) {
        vpi_printf("pli_rk: dma write, address error %x\n", ma);
        while (1);
    }

    M[ma >> 1] = data;
}

u16 rk_raw_read_memory(struct rk_context_s *rk, int ma)
{
    extern u16 *M;

    if (ma > 1024*1024) {
        vpi_printf("pli_rk: dma read, address error %x\n", ma);
        while (1);
    }

    return M[ma >> 1];
}

/* ----------------- */

static void set_output_str(int ord, char *str)
{
    s_vpi_value outval;

#ifdef __CVER__
    if (argl[ord].aref == 0)
        argl[ord].aref = vpi_put_value(argl[ord].ref, NULL, NULL, vpiAddDriver);
#else
    argl[ord].aref = argl[ord].ref;
#endif

    outval.format = vpiBinStrVal;
    outval.value.str = str;

    if (0) vpi_printf("rk: set output %s %s\n", argl[ord].name, str);

    vpi_put_value(argl[ord].aref, &outval, NULL, vpiNoDelay);
}

static void set_output_int(int ord, int val)
{
    s_vpi_value outval;

#ifdef __CVER__
    if (argl[ord].aref == 0)
        argl[ord].aref = vpi_put_value(argl[ord].ref, NULL, NULL, vpiAddDriver);
#else
    argl[ord].aref = argl[ord].ref;
#endif

    outval.format = vpiIntVal;
    outval.value.integer = val;

    if (0) vpi_printf("rk: set output %s %d\n", argl[ord].name, val);

    vpi_put_value(argl[ord].aref, &outval, NULL, vpiNoDelay);
}

#ifdef USE_DMA
static void dma_start_write(struct rk_context_s *rk,
                    unsigned int ma, unsigned int wc)
{
    vpi_printf("rk: dma start write ma=%o, wc=%o\n", ma, wc);
    rk->dma_cycle++;
    rk->dma_addr = ma;
    rk->dma_write = 1;
    rk->dma_wc = wc;
    rk->dma_index = 0;

    set_output_int(A_DMA_DATA_OUT, rk->rkxb[rk->dma_index]);
    set_output_int(A_DMA_ADDR, rk->dma_addr);
    set_output_str(A_DMA_WR, "1");
    set_output_str(A_DMA_REQ, "1");
}

static void dma_start_read(struct rk_context_s *rk,
                    unsigned int ma, unsigned int wc)
{
    vpi_printf("rk: dma start read ma=%o, wc=%o\n", ma, wc);
    rk->dma_cycle++;
    rk->dma_addr = ma;
    rk->dma_read = 1;
    rk->dma_wc = wc;

    set_output_int(A_DMA_ADDR, rk->dma_addr);
    set_output_str(A_DMA_RD, "1");
    set_output_str(A_DMA_REQ, "1");
}

static void dma_next(struct rk_context_s *rk)
{
    if (rk_debug > 1)
        vpi_printf("rk: dma next dma_addr=%o, dma_wc=%o\n",
                   rk->dma_addr, rk->dma_wc);

    if (!(rk->rkcs & RKCS_INH))
        rk->dma_addr += 2;

    if (rk->dma_read) {
        if (rk->rk_func == RKCS_WCHK) {
            if (rk->rkxb[rk->dma_index] != argl[A_DMA_DATA_IN].value) {
                rk->rker |= 1;
            }
        } else {
            rk->rkxb[rk->dma_index] = argl[A_DMA_DATA_IN].value;
        }
    }

    rk->dma_wc--;
    rk->dma_index++;

    if (rk->dma_write) {
        set_output_int(A_DMA_DATA_OUT, rk->rkxb[rk->dma_index]);
    }

    set_output_int(A_DMA_ADDR, rk->dma_addr);

    if (rk->dma_read) {
        set_output_str(A_DMA_RD, "1");
    }
    if (rk->dma_write) {
        set_output_str(A_DMA_WR, "1");
    }

    set_output_str(A_DMA_REQ, "1");
}

static void rk_set_done(struct rk_context_s *rk, int error);

static void dma_done(struct rk_context_s *rk)
{
    int wc, track, sector, da;

    vpi_printf("rk: XXX dma done\n");

    wc = 0200000 - rk->rkwc;

    track = (rk->rkda >> 4) & 0777;
    sector = rk->rkda & 017;
    da = ((track * 12) + sector) * 256;

    rk->rkwc = 0;
    rk->rkba = rk->dma_addr & 0xffff;
    rk->rkcs = (rk->rkcs & ~RKCS_MEX) | ((rk->dma_addr >> (16 - 4)) & RKCS_MEX);

    if ((rk->rk_func == RKCS_READ) && (rk->rkcs & RKCS_FMT))
        da = da + (wc * 256);
    else
        da = da + wc + (256 - 1);

    rk->track = (da / 256) / 12;
    rk->sect = (da / 256) % 12;

    rk->rkda = (rk->track << 4) | rk->sect;

    rk_set_done(rk, 0);

    rk->dma_cycle = 0;
    rk->dma_read = 0;
    rk->dma_write = 0;
    set_output_str(A_DMA_REQ, "0");
}
#endif

void
io_rk_reset(struct rk_context_s *rk)
{
    rk->rkcs = CSR_DONE;

    if (rk->rk_fd) {
        close(rk->rk_fd);
        rk->rk_fd = 0;
    }

    vpi_printf("io_rk_reset() opening file\n");

    rk->rk_fd = open("rk.dsk", O_RDONLY);
    rk->has_init = 1;
}

void io_rk_cpu_int_set(struct rk_context_s *rk)
{
    vpi_printf("io_rk_cpu_int_set() intset seek\n");

    set_output_str(A_INTERRUPT, "1");
    set_output_int(A_VECTOR, 0220);
}

void io_rk_cpu_int_clear(struct rk_context_s *rk)
{
    vpi_printf("io_rk_cpu_int_clear() intset seek\n");

    set_output_str(A_INTERRUPT, "0");
    set_output_int(A_VECTOR, 0);
}

u16 _io_rk_read(struct rk_context_s *rk, u22 addr)
{
    if (io_rk_debug) 
        vpi_printf("io_rk_read %o decode %o\n", addr, ((addr >> 1) & 07));

    switch ((addr >> 1) & 07) {			/* decode PA<3:1> */

    case 0:						/* RKDS: read only */
        rk->rkds = (rk->rkds & RKDS_ID) | RKDS_RK05 | RKDS_SC_OK;
        return rk->rkds;

    case 1:						/* RKER: read only */
        return rk->rker;

    case 2:						/* RKCS */
        if (rk->rker) rk->rkcs |= RKCS_ERR;
        if (rk->rker & RKER_HARD) rk->rkcs |= RKCS_HERR;
        return rk->rkcs;

    case 3:						/* RKWC */
        return rk->rkwc;

    case 4:						/* RKBA */
        return rk->rkba;

    case 5:						/* RKDA */
        return rk->rkda;

    default:
        return 0;
    }
}

static void rk_set_done(struct rk_context_s *rk, int error)
{
    if (1) vpi_printf("rk: done; error %o  seek\n", error);

    rk->rkcs |= CSR_DONE;
    if (error != 0) {
        rk->rker |= error;
        if (rk->rker)
            rk->rkcs |= RKCS_ERR;
        if (rk->rker & RKER_HARD)
            rk->rkcs |= RKCS_HERR;
    }

    if (rk->rkcs & CSR_IE) {
        rk->rkintq |= 1;
        io_rk_cpu_int_set(rk);
    } else {
        rk->rkintq = 0;
        io_rk_cpu_int_clear(rk);
    }
}

static void rk_clr_done(struct rk_context_s *rk)
{
    if (rk_debug > 1) vpi_printf("rk: not done\n");

    rk->rkcs &= ~CSR_DONE;
    rk->rkintq &= ~1;
    io_rk_cpu_int_clear(rk);
}

void rk_service(struct rk_context_s *rk)
{
    int i, err, wc, cda;
    int da, cyl, track, sector;
    unsigned int ma;

#ifndef USE_DMA
    int awc, cma, ret;
    unsigned short comp;
#endif

    vpi_printf("rk_service; func %o\n", rk->rk_func);

    if (rk->rk_func == RKCS_SEEK) {
        rk->rkcs |= RKCS_SCP;
        if (rk->rkcs & CSR_IE) {
            rk->rkintq |= 2;
            if (rk->rkcs & CSR_DONE)
                io_rk_cpu_int_set(rk);
        } else {
            rk->rkintq = 0;
            io_rk_cpu_int_clear(rk);
        }

        return;
    }

    cyl = (rk->rkda >> 5) & 0377;
    track = (rk->rkda >> 4) & 0777;
    sector = rk->rkda & 017;

    ma = ((rk->rkcs & RKCS_MEX) << (16 - 4)) | rk->rkba;

    if (sector >= 12) {
        rk_set_done(rk, RKER_NXS);
        return;
    }

    if (cyl >= 203) {
        rk_set_done(rk, RKER_NXC);
        return;
    }

    da = ((track * 12) + sector) * 256;
    wc = 0200000 - rk->rkwc;

    vpi_printf("rk: seek %d (read %d)\n", da * sizeof(short), wc*2);

    err = lseek(rk->rk_fd, da * sizeof(short), SEEK_SET);
    if (wc && (err >= 0)) {
        err = 0;

        switch (rk->rk_func) {

        case RKCS_READ:
            if (rk->rkcs & RKCS_FMT) {
                for (i = 0, cda = da; i < wc; i++) {
                    rk->rkxb[i] = (cda / 256) / (2 * 12);
                    cda = cda + 256;
                }
            } else {
                vpi_printf("rk: read() wc %d\n", wc);
                i = read(rk->rk_fd, rk->rkxb, sizeof(short)*wc);

                vpi_printf("rk: read() ret %d\n", i);
                if (i >= 0 && i < sizeof(short)*wc) {
                    i /= 2;
                    for (; i < wc; i++)
                        rk->rkxb[i] = 0;
                }
            }

#ifdef USE_DMA
            vpi_printf("rk: read(), dma ma=%o, wc=%d\n", ma, wc);
            vpi_printf("rk: buffer %06o %06o %06o %06o\n",
                       rk->rkxb[0], rk->rkxb[1], rk->rkxb[2], rk->rkxb[3]);
            dma_start_write(rk, ma, wc);
            return;
#else
            if (rk->rkcs & RKCS_INH) {
                rk_raw_write_memory(rk, ma, rk->rkxb[wc - 1]);
            } else {
                //int oldma = ma;
                vpi_printf("rk: read(), dma wc=%d, ma=%o\n", wc, ma);
                vpi_printf("rk: buffer %06o %06o %06o %06o\n",
                       rk->rkxb[0], rk->rkxb[1], rk->rkxb[2], rk->rkxb[3]);
                for (i = 0; i < wc; i++) {
                    rk_raw_write_memory(rk, ma, rk->rkxb[i]);
                    ma += 2;
                }
		//show(oldma);
            }
#endif
            break;

        case RKCS_WRITE:
#ifdef USE_DMA
            if (rk->rkcs & RKCS_INH) {
                dma_start_read(rk, ma, 1);
            } else {
                dma_start_read(rk, ma, wc);
            }
            return;
#else
            if (rk->rkcs & RKCS_INH) {
                comp = rk_raw_read_memory(rk, ma);
                for (i = 0; i < wc; i++)
                    rk->rkxb[i] = comp;
            } else {
                for (i = 0; i < wc; i++) {
                    rk->rkxb[i] = rk_raw_read_memory(rk, ma);
                    ma += 2;
                }
            }

            awc = (wc + (256 - 1)) & ~(256 - 1);
            vpi_printf("rk: write(), wc=%d\n", awc*2);
	    ret = write(rk->rk_fd, rk->rkxb, awc*2);
#endif
            break;

        case RKCS_WCHK:
            i = read(rk->rk_fd, rk->rkxb, sizeof(short)*wc);
            if (i < 0) {
                wc = 0;
                break;
            }

            if (i >= 0 && i < sizeof(short)*wc) {
                i /= 2;
                for (; i < wc; i++)
                    rk->rkxb[i] = 0;
            }

#ifdef USE_DMA
            dma_start_read(rk, 0, wc);
            return;
#else
            awc = wc;
            for (wc = 0, cma = ma; wc < awc; wc++)  {
                comp = rk_raw_read_memory(rk, cma);
                if (comp != rk->rkxb[wc])  {
                    rk->rker |= rk->rker;
                    if (rk->rkcs & RKCS_SSE)
                        break;
                }
                if (!(rk->rkcs & RKCS_INH))
                    cma += 2;
            }
#endif
            break;

        default:
            break;
        }
    }

    rk->rkwc = (rk->rkwc + wc) & 0177777;
    if (!(rk->rkcs & RKCS_INH))
        ma = ma + (wc << 1);

    rk->rkba = ma & 0xffff;
    rk->rkcs = (rk->rkcs & ~RKCS_MEX) | ((ma >> (16 - 4)) & RKCS_MEX);

    if ((rk->rk_func == RKCS_READ) && (rk->rkcs & RKCS_FMT))
        da = da + (wc * 256);
    else
        da = da + wc + (256 - 1);

    rk->track = (da / 256) / 12;
    rk->sect = (da / 256) % 12;

    rk->rkda = (rk->track << 4) | rk->sect;
    rk_set_done(rk, 0);

    if (err != 0) {
        vpi_printf("RK I/O error\n");
    }
}

static void rk_go(struct rk_context_s *rk)
{
    if (rk_debug > 1) vpi_printf("rk_go!\n");

    rk->rk_func = (rk->rkcs >> 1) & 7;
    if (rk->rk_func == RKCS_CTLRESET) {
        rk->rker = 0;
        rk->rkda = 0;
        rk->rkba = 0;
        rk->rkcs = CSR_DONE;
        rk->rkintq = 0;
        io_rk_cpu_int_clear(rk);
        return;
    }

    rk->rker &= ~RKER_SOFT;
    if (rk->rker == 0)
        rk->rkcs &= ~RKCS_ERR;

    rk->rkcs &= ~RKCS_SCP;
    rk_clr_done(rk);

    if ((rk->rkcs & RKCS_FMT) &&
        (rk->rk_func != RKCS_READ) && (rk->rk_func != RKCS_WRITE)) {
	rk_set_done(rk, RKER_PGE);
	return;
    }

    if ((rk->rk_func == RKCS_WRITE) && rk->rk_write_prot) {
        rk_set_done(rk, RKER_WLK);
        return;
    }

    if (rk->rk_func == RKCS_WLK) {
        rk_set_done(rk, 0);
        return;
    }

    if (rk->rk_func == RKCS_DRVRESET) {
        rk->cyl = 0;
        rk->sect = 0;
        rk->rk_func = RKCS_SEEK;
    } else {
        rk->sect = rk->rkda & 017;
        rk->cyl = (rk->rkda >> 5) & 0377;
    }

    if (rk->sect >= 12) {
        rk_set_done(rk, RKER_NXS);
        return;
    }

    if (rk->cyl >= 203) {
        rk_set_done(rk, RKER_NXC);
        return;
    }

    if (rk->rk_func == RKCS_SEEK) {
        rk_set_done(rk, 0);
    }

    rk_service(rk);
}

void _io_rk_write(struct rk_context_s *rk, u22 addr, u16 data, int writeb)
{
    if (0) vpi_printf("_io_rk_write %o %d decode %o\n",
                  addr, writeb, ((addr >> 1) & 07));

    switch ((addr >> 1) & 07) {			/* decode PA<3:1> */

    case 2:						/* RKCS */
        vpi_printf("rk: rkcs <- %o\n", data);
        if (writeb) {
            data = (addr & 1)? (rk->rkcs & 0377) |
                (data << 8): (rk->rkcs & ~0377) | data;
        }
        if ((data & CSR_IE) == 0) {		/* int disable? */
            rk->rkintq = 0;			/* clr int queue */
            io_rk_cpu_int_clear(rk);
        } else 
            if ((rk->rkcs & (CSR_DONE | CSR_IE)) == CSR_DONE) {
                rk->rkintq |= 1;
                io_rk_cpu_int_set(rk);
            }

        rk->rkcs = (rk->rkcs & ~RKCS_RW) | (data & RKCS_RW);
        vpi_printf("rk: rkcs %o\n", rk->rkcs);

        if ((rk->rkcs & CSR_DONE) && (data & CSR_GO))
            rk_go(rk);
        return;
		
    case 3:						/* RKWC */
        if (writeb)  {
            data = (addr & 1) ?
                (rk->rkwc & 0377) | (data << 8) :
                (rk->rkwc & ~0377) | data;
        }
        rk->rkwc = data;
        vpi_printf("rk: rkwc <- %o\n", rk->rkwc);
        return;

    case 4:						/* RKBA */
        if (writeb) {
            data = (addr & 1)?
                (rk->rkba & 0377) | (data << 8) :
                (rk->rkba & ~0377) | data;
        }
        rk->rkba = data;
        vpi_printf("rk: rkba <- %o\n", rk->rkba);
        return;

    case 5:						/* RKDA */
        if ((rk->rkcs & CSR_DONE) == 0)
            return;
        if (writeb) {
            data = (addr & 1) ?
                (rk->rkda & 0377) | (data << 8) :
                (rk->rkda & ~0377) | data;
        }
        rk->rkda = data;
        vpi_printf("rk: XXX rkda <- %o\n", rk->rkda);
        return;

    default:
        vpi_printf("rk: ??\n");
        return;
    }
}

/* ------------------------------------------------------ */

static int getadd_inst_id(vpiHandle mhref)
{
    register int i;
    char *chp;
 
    chp = vpi_get_str(vpiFullName, mhref);

    for (i = 1; i <= last_evh; i++) {
        if (strcmp(instnam_tab[i], chp) == 0)
            return(i);
    }

    vpi_printf("pli_rk: adding instance %d, %s\n", last_evh+1, chp);

    instnam_tab[++last_evh] = malloc(strlen(chp) + 1);
    strcpy(instnam_tab[last_evh], chp);

    return(last_evh);
} 

/*
 *
 */
PLI_INT32 pli_rk(void)
{
    vpiHandle href, iter, mhref;
    int numargs, inst_id;
    s_vpi_value tmpval;
    int i, badarg;
    char iopr_bit, iopw_bit, dma_ack_bit;
    struct rk_context_s *rk;
    unsigned int addr, decode;

    int read_start, read_stop, write_start, write_stop;
    int dma_ack_start, dma_ack_stop;

    //vpi_printf("pli_rk:\n");

    href = vpi_handle(vpiSysTfCall, NULL); 
    if (href == NULL) {
        vpi_printf("** ERR: $pli_rk PLI 2.0 can't get systf call handle\n");
        return(0);
    }

#if 0
    mhref = vpi_handle(vpiScope, href);

    if (vpi_get(vpiType, mhref) != vpiModule) {
        vpiHandle old_mhref = mhref;
        mhref = vpi_handle(vpiModule, mhref); 
//        vpi_free_object(old_mhref);
    }

    inst_id = getadd_inst_id(mhref);
#else
    inst_id = 1;
#endif
    rk = &rk_context[inst_id];

    //vpi_printf("pli_rk: inst_id %d\n", inst_id);

    iter = vpi_iterate(vpiArgument, href);

    numargs = vpi_get(vpiSize, iter);

    badarg = 0;
    for (i = 0; argl[i].ord; i++) {
        argl[i].ref = vpi_scan(iter);
        if (argl[i].ref == NULL)
            badarg++;
        else {
            tmpval.format = vpiBinStrVal; 
            vpi_get_value(argl[i].ref, &tmpval);
            strcpy(argl[i].bits, tmpval.value.str);

            tmpval.format = vpiIntVal; 
            vpi_get_value(argl[i].ref, &tmpval);
            argl[i].value = tmpval.value.integer;
        }
    }

    vpi_free_object(iter);
    vpi_free_object(href);

    if (badarg)
    {
        vpi_printf("**ERR: $pli_rk bad args\n");
        return(0);
    }

    if (!rk->has_init) {
        io_rk_reset(rk);

        for (i = 0; argl[i].ord; i++) {
            if (argl[i].preset) {
                if (0) vpi_printf("pli_rk: preset %s\n", argl[i].name);
                set_output_str(i, "0");
            }
        }
    }

    /* */
    read_start = 0;
    read_stop = 0;
    write_start = 0;
    write_stop = 0;
    dma_ack_start = 0;
    dma_ack_stop = 0;

    iopr_bit = argl[A_IOPAGE_RD].bits[0];
    iopw_bit = argl[A_IOPAGE_WR].bits[0];
    dma_ack_bit = argl[A_DMA_ACK].bits[0];

    if (iopr_bit != last_iopr_bit) {
        if (iopr_bit == '1') read_start = 1;
        if (iopr_bit == '0') read_stop = 1;
    }

    if (iopw_bit != last_iopw_bit) {
        if (iopw_bit == '1') write_start = 1;
        if (iopw_bit == '0') write_stop = 1;
    }

    if (dma_ack_bit != last_dma_ack_bit) {
        if (dma_ack_bit == '1') dma_ack_start = 1;
        if (dma_ack_bit == '0') dma_ack_stop = 1;
    }

    last_iopr_bit = iopr_bit;
    last_iopw_bit = iopw_bit;
    last_dma_ack_bit = dma_ack_bit;

    addr = argl[A_IOPAGE_ADDR].value;
    decode = 017400 <= addr && addr <= 017412;
    if (0) vpi_printf("pli_rk: decode %o %d\n", addr, decode);

    if (0) {
        if (read_start) vpi_printf("pli_rk: read start\n");
        if (read_stop) vpi_printf("pli_rk: read stop\n");
        if (write_start) vpi_printf("pli_rk: write start\n");
        if (write_stop) vpi_printf("pli_rk: write stop\n");
        if (dma_ack_start) vpi_printf("pli_rk: dma_ack start\n");
        if (dma_ack_stop) vpi_printf("pli_rk: dma_ack stop\n");
    }

    /* */
    if (argl[A_RESET].value == 1) {
        vpi_printf("pli_rk: reset\n");
        io_rk_reset(rk);
    }

    if (argl[A_INT_ACK].value == 1) {
        vpi_printf("pli_rk: intack\n");
        io_rk_cpu_int_clear(rk);
    }

#ifdef USE_DMA
    if (!dma_ack_start && !dma_ack_stop) {
        if (0) vpi_printf("pli_rk: dma waiting\n");
    }

    if (dma_ack_stop) {
        if (rk_debug > 1)
            vpi_printf("pli_rk: dma ack stop (func=%o)\n", rk->rk_func);

        if (rk->dma_read) {

            switch (rk->rk_func) {
            case RKCS_WRITE:
                dma_next(rk);

                if (rk->dma_wc == 0) {
                    int wc, awc, ret;
                    wc = 0200000 - rk->rkwc;
                    awc = (wc + (256 - 1)) & ~(256 - 1);
                    vpi_printf("rk: XXX wc=0, write() %d\n", awc*2);
                    ret = write(rk->rk_fd, rk->rkxb, awc*2);
                }
                break;

            case RKCS_WCHK:
                dma_next(rk);
                break;
            }
        }

        if (rk->dma_write) {
            dma_next(rk);
        }

        if (rk->dma_wc == 0) {
            dma_done(rk);
        }
    }
#endif

    set_output_str(A_DECODE, decode ? "1" : "0");

    if (write_start && decode) {
        unsigned data, writeb;

        data = argl[A_DATA_IN].value;
        writeb = argl[A_IOPAGE_BYTE_OP].value;

        vpi_printf("pli_rk: write %o <- %o (b%d)\n", addr, data, writeb);

        _io_rk_write(rk, addr, data, writeb);
    }

    if (read_start && decode) {
        unsigned value;

        addr = argl[A_IOPAGE_ADDR].value;

        if (rk_debug > 1) vpi_printf("pli_rk: read %o\n", addr);

        value = _io_rk_read(rk, addr);

        set_output_int(A_DATA_OUT, value);
    }

    if (read_stop && decode) {
//        set_output_str(A_DATA_OUT, "16'bzzzzzzzzzzzzzzzz");
        set_output_str(A_DATA_OUT, "16'b0000000000000000");
    }

    /* free argument handles */
    for (i = 0; argl[i].ord; i++) {
        if (argl[i].ref != NULL)
            vpi_free_object(argl[i].ref);
        argl[i].ref = NULL;
        argl[i].aref = NULL;
    }

    return(0);
}

/*
 * register all vpi_ PLI 2.0 style user system tasks and functions
 */
static void register_my_systfs(void)
{
    p_vpi_systf_data systf_data_p;

    /* use predefined table form - could fill systf_data_list dynamically */
    static s_vpi_systf_data systf_data_list[] = {
        { vpiSysTask, 0, "$pli_rk", pli_rk, NULL, NULL, NULL },
        { vpiSysTask, 0, "$pli_ram", pli_ram, NULL, NULL, NULL },
        { 0, 0, NULL, NULL, NULL, NULL, NULL }
    };

    systf_data_p = &(systf_data_list[0]);
    while (systf_data_p->type != 0) {
        vpi_register_systf(systf_data_p++);
    }
}

#ifdef unix
/* all routines are called to register system tasks */
/* called just after all PLI 1.0 tf_ veriusertfs table routines are set up */
/* before source is read */ 
static void (*rk_vlog_startup_routines[]) () =
{
 register_my_systfs, 
 0
};

/* dummy +loadvpi= boostrap routine - mimics old style exec all routines */
/* in standard PLI vlog_startup_routines table */
void rk_vpi_compat_bootstrap(void)
{
    int i;

    io_rk_debug = 0;
    rk_debug = 1;

    for (i = 0;; i++) {
        if (rk_vlog_startup_routines[i] == NULL)
            break; 
        rk_vlog_startup_routines[i]();
    }
}

void vpi_compat_bootstrap(void)
{
    rk_vpi_compat_bootstrap();
}

#ifndef BUILD_ALL
void __stack_chk_fail_local() {}
#endif

#endif

#ifdef __MODELSIM__
static void (*vlog_startup_routines[]) () =
{
 register_my_systfs, 
 0
};
#endif


/*
 * Local Variables:
 * indent-tabs-mode:nil
 * c-basic-offset:4
 * End:
*/
