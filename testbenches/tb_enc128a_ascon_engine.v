`timescale 1ns / 1ps

`ifndef PARAMS
`include "ascon_constants.vh"
`define PARAMS
`endif

module tb_enc128a_ascon_engine(
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

    reg [127:0] key     = 128'h000102030405060708090A0B0C0D0E0F;
    reg [127:0] nonce   = 128'h000102030405060708090A0B0C0D0E0F;
    reg [127:0] ad_data = 128'h00800000000000000000000000000000;
    reg [127:0] plain   = 128'h80000000000000000000000000000000;
    reg [127:0] cipher;
    reg [127:0] tag;

    reg [127:0] golden_cipher    = 128'hee480efdd1b652606f3c06d33047c1b2;
    reg [127:0] golden_tag      = 128'h7A834E6F09210957067B10FD831F0078;

    reg [127:0] golden_cipher_ad = 128'h692c2866caec7478baf5c0917eb27611;
    reg [127:0] golden_tag_ad   = 128'hAF3031B07B129EC84153373DDCABA528;

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
        $dumpfile("tb_enc128a_ascon_engine.vcd");
        $dumpvars(0,tb_enc128a_ascon_engine);
        
        clk = 'b1;
        forever begin
            #1 clk = ~clk;
        end
    end

    // Test ASCON 128a Encryption
    initial begin
        // Make sure clock is available
        #2
        reset;

        //Send start command
        bd_in_data = 16'b0;
        bd_in_config = {5'b0, `CONF, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, tx_toggle};
        // $display("Send data: %h %h", bd_in_data, bd_in_config);
        wait(toggle != prev_toggle);
        // play("Recv: %h %h", bd_out_data, bd_out_config);

        // Send Key
        for (i = 0; i < 8; i=i+1) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = key[127:112];
            key = key << 16;
            if (i == 7) bd_in_config  = {5'b0, `KEY, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `KEY, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            // $display("Send key: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            // $display("Recv key: %h %h", bd_out_data, bd_out_config);
        end

        // Send Nonce
        for (i = 0; i < 8; i=i+1) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = nonce[127:112];
            nonce = nonce << 16;
            if (i == 7) bd_in_config  = {5'b0, `NONCE, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `NONCE, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            // $display("Send nonce: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            // $display("Recv nonce: %h %h", bd_out_data, bd_out_config);
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
                bd_in_data = plain[127:112];
                plain = plain << 16;
                if (i == 7) bd_in_config  = {5'b0, `PLAIN, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                else bd_in_config  = {5'b0, `PLAIN, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                // $display("Send plain: %h %h", bd_in_data, bd_in_config);
                wait(toggle != prev_toggle);
                // $display("Recv plain: %h %h", bd_out_data, bd_out_config);
            end

            // Receive ciphertext from ascon engine in 64 bit blocks
            for (i = 0; i < 8; i=i+1) begin
                prev_toggle = ~ prev_toggle;
                tx_toggle = ~tx_toggle;
                bd_in_data = 127'b0;
                if (i == 7) bd_in_config  = {5'b0, `OK, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                else bd_in_config  = {5'b0, `OK, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
                // $display("Send cipher: %h %h", bd_in_data, bd_in_config);
                wait(toggle != prev_toggle);
                cipher = cipher << 16;
                cipher[15:0] = bd_out_data;
                // $display("Recv cipher: %h %h", bd_out_data, bd_out_config); 
            end
        end

        // Receive tag
        for (i = 0; i < 8; i=i+1) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = 127'b0;
            if (i == 7) bd_in_config  = {5'b0, `OK, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `OK, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            // $display("Send tag: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            // $display("Recv tag: %h %h", bd_out_data, bd_out_config);
            tag = tag << 16;
            tag[15:0] = bd_out_data;
        end

        // Reset trigger for Ascon engine
        prev_toggle = ~ prev_toggle;
        tx_toggle = ~tx_toggle;
        bd_in_data = 16'b0;
        bd_in_config  = {5'b0, `OK, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
        #50

        if (testbench_mode == NO_AD) begin
            // Validate data
            if (cipher == golden_cipher) begin
                $display("ASCON 128a Enc Cipher:\tPASS");
            end else begin
                $display("ASCON 128a Enc Cipher:\tFAILED");
                $display("Exp:\t%h", golden_cipher);
                $display("Got:\t%h", cipher);
            end

            if (tag == golden_tag) begin
                $display("ASCON 128a Enc Tag:\tPASS");
            end else begin
                $display("ASCON 128a Enc Tag:\tFAILED");
                $display("Exp:\t%h", golden_tag);
                $display("Got:\t%h", tag);
            end
        end else if (testbench_mode == WT_AD) begin
            if (cipher == golden_cipher_ad) begin
                $display("ASCON 128a Enc Cipher:\tPASS");
            end else begin
                $display("ASCON 128a Enc Cipher:\tFAILED");
                $display("Exp:\t%h", golden_cipher_ad);
                $display("Got:\t%h", cipher);
            end

            if (tag == golden_tag_ad) begin
                $display("ASCON 128a Enc Tag:\tPASS");
            end else begin
                $display("ASCON 128a Enc Tag:\tFAILED");
                $display("Exp:\t%h", golden_tag_ad);
                $display("Got:\t%h", tag);
            end
        end
        #20;
        $finish;

    end
endmodule