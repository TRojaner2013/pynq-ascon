#!/bin/bash
iverilog -o  tb_hash_ascon_engine ./sim_1/new/tb_hash_ascon_engine.v ./sources_1/imports/new/ascon_engine.v ./sources_1/imports/new/ascon_permutation.v -Wall -I ./sources_1/new &
iverilog -o  tb_xof_ascon_engine ./sim_1/new/tb_xof_ascon_engine.v ./sources_1/imports/new/ascon_engine.v ./sources_1/imports/new/ascon_permutation.v -Wall -I ./sources_1/new &

iverilog -o  tb_enc128_ascon_engine ./sim_1/new/tb_enc128_ascon_engine.v ./sources_1/imports/new/ascon_engine.v ./sources_1/imports/new/ascon_permutation.v -Wall -I ./sources_1/new &
iverilog -o  tb_dec128_ascon_engine ./sim_1/new/tb_dec128_ascon_engine.v ./sources_1/imports/new/ascon_engine.v ./sources_1/imports/new/ascon_permutation.v -Wall -I ./sources_1/new &

iverilog -o  tb_enc128a_ascon_engine ./sim_1/new/tb_enc128a_ascon_engine.v ./sources_1/imports/new/ascon_engine.v ./sources_1/imports/new/ascon_permutation.v -Wall -I ./sources_1/new &
iverilog -o  tb_dec128a_ascon_engine ./sim_1/new/tb_dec128a_ascon_engine.v ./sources_1/imports/new/ascon_engine.v ./sources_1/imports/new/ascon_permutation.v -Wall -I ./sources_1/new &

wait

vvp tb_hash_ascon_engine
vvp tb_xof_ascon_engine

vvp tb_enc128_ascon_engine
vvp tb_dec128_ascon_engine

vvp tb_enc128a_ascon_engine
vvp tb_dec128a_ascon_engine

