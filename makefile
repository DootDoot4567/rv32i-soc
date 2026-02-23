YOSYS		?= yosys
NEXTPNR 	?= nextpnr-ice40

DEVICE		?= hx8k
PACKAGE		?= tq144:4k
#PROGRAMMER	?= ./spi_volatile_programmer.py
PROGRAMMER	?= ./spi_flash_programmer.sh
PCF_FILE	?= Go_Board_Constraints.pcf

TOP			?= soc
TOP_TB		?= instructions_tb
MODULES		?= processor.sv bram_sdp.sv decoder.sv alu.sv
MODULES_TB	?= instructions_tb.sv

# Use yosys to perform synthesis
%.json : %.sv
	$(YOSYS) -p "read_verilog -sv $(MODULES); synth_ice40 -top $(TOP) -json $@" $<

# Use nextpnr-ice40 to perform place-and-route
%.asc : %.json
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --pcf $(PCF_FILE) --asc $@ --json $<

# Use icepack to generate bitstream
%.bin : %.asc
	icepack $< $@

# Use Icarus to generate a simulator
%_tb.vvp : %_tb.sv $(MODULES)
	iverilog -g2012 -o $@ $^

# Use Icarus to run the simulation
run: $(TOP_TB).vvp
	vvp $(TOP_TB).vvp

# Graph (using GTKWave)
graph: $(TOP_TB).vcd
	gtkwave $^

# Generate bitstream
bitstream: $(TOP).bin

# Program (using GPIO/program.sh and flashrom)
program: $(TOP).bin
	$(PROGRAMMER) $^

# Clean
clean:
	rm -f *.bin *.vvp *.vcd *.asc *.blif *.json