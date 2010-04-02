#CVER_FLAGS = +loadvpi=../pli/ide/pli_ide.so:vpi_compat_bootstrap
CVER_FLAGS = 

RTESTS = test_tt test_rf test_io

#---------------------------------------------------------------------

define runone_verilog_regression
	cver $(CVER_FLAGS) $(1) >$(2);
	@if grep -q ERROR $(2); then exit 1; fi;
	@if grep -q FAILURE $(2); then exit 1; fi;
endef

RTEST_LOGS = $(addsuffix .log,$(RTESTS))

$(RTEST_LOGS) : %.log : %.v $(RTL)
	$(call runone_verilog_regression,$<,$@)

# verilog testbench regression tests
rgress: $(RTEST_LOGS)

test_tt: test_tt.v
	$(call runone_verilog_regression,$<,$@)

test_rf: test_rf.v
	$(call runone_verilog_regression,$<,$@)

test_io: test_io.v
	$(call runone_verilog_regression,$<,$@)


#
clean:
	rm -f verilog.log
	rm -f *.vcd
