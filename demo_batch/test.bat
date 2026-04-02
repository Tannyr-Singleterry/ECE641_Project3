@echo off
echo FPGA Configure...

set project_sof=golden_top.sof


REM ########################################################################
REM # Download sof file
REM ########################################################################
@ set QUARTUS_BIN=%QUARTUS_ROOTDIR%\bin
@ if not exist "%QUARTUS_BIN%" set QUARTUS_BIN=%QUARTUS_ROOTDIR%\bin64

REM if not exist "%QUARTUS_BIN%\\qpro.exe" (
REM	echo Your default Quartus specified by system variable QUARTUS_ROOT must be Quartus Pro. Edition for programming Agilex FPGA device.
REM	goto :Exit
REM

%QUARTUS_BIN%\\quartus_pgm.exe -m jtag -c 1 -o "p;%project_sof%"


pause


