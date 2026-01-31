`timescale 1ns / 1ps

// Simple Day 17 FastPath simulation script

// Compile
exec xvlog -sv -prj day17_sources.prj

// Elaborate
exec xelab -debug typical tb_day17_fastpath -s sim_snapshot

// Simulate
exec xsim sim_snapshot -runall
