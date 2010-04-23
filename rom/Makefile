
all: rom.mem

rom.bin: rom.pal
	../utils/macro/macro8x rom.pal

rom.mem: rom.bin
	../utils/showbin/showbin rom.bin >rom.mem

clean:
	rm -rf *.lst *.bin *.mem
