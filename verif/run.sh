cver +showpc +cycles=500000 +test=tss8_init.mem +pc=24200 +loadvpi=../pli/ide/pli_ide.so:vpi_compat_bootstrap test_pdp8.v >xx

#cver +showpc +test=../tests/diags/MAINDEC-08-D5FA.mem +pc=0150 +switches=0000 +cycles=200000 +loadvpi=../pli/ide/pli_ide.so:vpi_compat_bootstrap test_pdp8.v >zz

#cver +showpc +test=../tests/diags/MAINDEC-08-D5EB.mem +pc=0200 +switches=4000 +cycles=50000 +loadvpi=../pli/ide/pli_ide.so:vpi_compat_bootstrap test_pdp8.v >zz

#cver +cycles=1000000 +test=boot.mem +pc=7750 +loadvpi=../pli/ide/pli_ide.so:vpi_compat_bootstrap test_pdp8.v >yy2

#grep "rf: go\!" xx
#cat xx | ../utils/ushow/ushow 
