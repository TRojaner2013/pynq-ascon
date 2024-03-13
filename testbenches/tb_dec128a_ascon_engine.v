`timescale 1ns / 1ps

`ifndef PARAMS
`include "ascon_constants.vh"
`define PARAMS
`endif

module tb_dec128a_ascon_engine(
    );

    localparam
        NO_AD = 0,
        WT_AD = 1;

    //wire testbench_mode = NO_AD;
    wire testbench_mode = WT_AD;

    reg clk;
    reg rst;
    
    reg [15:0] bd_in_data;
    reg [15:0] bd_in_config;
    
    wire [15:0] bd_out_data;
    wire [15:0] bd_out_config;

    ascon_engine ascon(.clk (clk),
                       .rst (rst),
                       .bd_in_data (bd_in_data),
                       .bd_in_config (bd_in_config),
                       .bd_out_data (bd_out_data),
                       .bd_out_config (bd_out_config)
                       );

    integer i;

    // ASCON128 has a block size of 128 bit!
    reg [127:0] key     = 128'h000102030405060708090A0B0C0D0E0F;
    reg [127:0] nonce   = 128'h000102030405060708090A0B0C0D0E0F;
    reg [127:0] ad_data = 128'h00800000000000000000000000000000;
    reg [127:0] plain;
    reg [127:0] cipher  = 128'hee480efdd1b652606f3c06d33047c1b2;
    reg [127:0] tag;

    reg [127:0] golden_plain    = 128'h80000000000000000000000000000000;
    reg [127:0] golden_tag      = 128'h7A834E6F09210957067B10FD831F0078;

    reg [127:0] golden_cipher_ad    = 128'h692c2866caec7478baf5c0917eb27611;
    reg [127:0] golden_tag_ad       = 128'hAF3031B07B129EC84153373DDCABA528;

    wire auth;
    assign auth = bd_out_config[3];
    reg prev_toggle;

    wire toggle;
    reg tx_toggle;
    assign toggle = bd_out_config[2];
  
    task reset();
        begin 

            rst = 1;

            bd_in_data = 16'b0;
            bd_in_config = 16'b0;
            prev_toggle = 1'b0;
            tx_toggle = 1'b0;

            rst = 0;
            #2
            rst = 1;
        end
    endtask

    // Reset module and start clock
    initial begin
        $dumpfile("tb_dec128a_ascon_engine.vcd");
        $dumpvars(0,tb_dec128a_ascon_engine);
        
        clk = 'b1;
        forever begin
            #1 clk = ~clk;
        end
    end

    // Test ASCON 128a Decryption
    initial begin
        // Make sure clock is available
        #2
        if (testbench_mode == NO_AD) begin
            tag = golden_tag;
        end
        if (testbench_mode == WT_AD) begin
            tag = golden_tag_ad;
            cipher = golden_cipher_ad;
        end

        reset;

        //Send start command
        bd_in_data = 16'b0;
        bd_in_config = {5'b0, `CONF, 1'b1, 1'b0, 1'b1, 1'b1, 1'b0, 1'b0, tx_toggle};
        //$display("Send data: %h %h", bd_in_data, bd_in_config);
        wait(toggle != prev_toggle);
        //$display("Recv: %h %h", bd_out_data, bd_out_config);

        // Send Key
        for (i = 0; i < 8; i=i+1) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = key[127:112];
            key = key << 16;
            if (i == 7) bd_in_config  = {5'b0, `KEY, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `KEY, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            //$display("Send key: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            //$display("Recv key: %h %h", bd_out_data, bd_out_config);
        end

        // Send Nonce
        for (i = 0; i < 8; i=i+1) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = nonce[127:112];
            nonce = nonce << 16;
            if (i == 7) bd_in_config  = {5'b0, `NONCE, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `NONCE, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            //$display("Send nonce: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            //$display("Recv nonce: %h %h", bd_out_data, bd_out_config);
        end

        // Send Tag
        for (i = 0; i < 8; i=i+1) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = tag[127:112];
            tag = tag << 16;
            if (i == 7) bd_in_config  = {5'b0, `TAG, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `TAG, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            //$display("Send tag: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            //$display("Recv tag: %h %h", bd_out_data, bd_out_config);
        end

        // Send additional data
        if (testbench_mode == NO_AD) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = 128'b0;
            bd_in_config  = {5'b0, `SKIP_AD, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            // $display("Send AD SKIP: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            // $display("Recv AD SKIP: %h %h", bd_out_data, bd_out_config);
        end else if (testbench_mode == WT_AD) begin
            for (i = 0; i < 8; i=i+1) begin
                prev_toggle = ~ prev_toggle;
                tx_toggle = ~tx_toggle;
                bd_in_data = ad_data[127:112];
                ad_data = ad_data << 16;
                if (i == 7) bd_in_config  = {5'b0, `AD, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                else bd_in_config  = {5'b0, `AD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                // $display("Send ad: %h %h", bd_in_data, bd_in_config);
                wait(toggle != prev_toggle);
                // $display("Recv ad: %h %h", bd_out_data, bd_out_config);
            end
        end

        // Send plaintext and receive ciphertext
        for (i = 0; i < 1; i=i+1) begin
            // Send plaintext to ascon engine in 64 bit block
            for (i = 0; i < 8; i=i+1) begin
                prev_toggle = ~ prev_toggle;
                tx_toggle = ~tx_toggle;
                bd_in_data = cipher[127:112];
                cipher = cipher << 16;
                if (i == 7) bd_in_config  = {5'b0, `CIPHER, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                else bd_in_config  = {5'b0, `CIPHER, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                //$display("Send cipher: %h %h", bd_in_data, bd_in_config);
                wait(toggle != prev_toggle);
                //$display("Recv cipher: %h %h", bd_out_data, bd_out_config);
            end

            // Receive ciphertext from ascon engine in 64 bit blocks
            for (i = 0; i < 8; i=i+1) begin
                prev_toggle = ~ prev_toggle;
                tx_toggle = ~tx_toggle;
                bd_in_data = 127'b0;
                if (i == 7) bd_in_config  = {5'b0, `OK, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                else bd_in_config  = {5'b0, `OK, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                //$display("Send plain: %h %h", bd_in_data, bd_in_config);
                wait(toggle != prev_toggle);
                plain = plain << 16;
                plain[15:0] = bd_out_data;
                //$display("Recv plain: %h %h", bd_out_data, bd_out_config);
            end
        end

        // Send OK To receive Auth results.
        prev_toggle = ~ prev_toggle;
        tx_toggle = ~tx_toggle;
        bd_in_data = 127'b0;
        bd_in_config  = {5'b0, `OK, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
        wait(toggle != prev_toggle);

        // Reset trigger for Ascon engine
        prev_toggle = ~ prev_toggle;
        tx_toggle = ~tx_toggle;
        bd_in_data = 16'b0;
        bd_in_config  = {5'b0, `OK, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
        #50
        
        // Validate tag
        if (auth) $display("ASCON 128a Tag:\tPASS");
        if (!auth) if (auth) $display("ASCON 128a Tag:\tFAILED");

        // Validate data
        if (plain == golden_plain) begin
            $display("ASCON 128a Dec:\tPASS");
        end else begin
            $display("ASCON 128a Dec:\tFAILED");
            $display("Exp:\t%h", golden_plain);
            $display("Got:\t%h", plain);
        end

        $finish;

    end
endmodule