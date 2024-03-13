`timescale 1ns / 1ps
`ifndef PARAMS
`include "ascon_constants.vh"
`define PARAMS
`endif

module tb_xof_ascon_engine(
    );
    
    reg clk;
    reg rst;
    
    reg [15:0] bd_in_data;
    reg [15:0] bd_in_config;
    
    wire [15:0] bd_out_data;
    wire [15:0] bd_out_config;

    ascon_engine ascon( .clk (clk),
                        .rst (rst),
                        .bd_in_data (bd_in_data),
                        .bd_in_config (bd_in_config),
                        .bd_out_data (bd_out_data),
                        .bd_out_config (bd_out_config)
                        );

    //reg [255:0] testHash = 384'h54686520717569636B2062726F776E20666F78206A756D7073206F76657220746865206C617A7920646F67;
    reg [63:0] null_msg = 64'h8000000000000000;
    reg [383:0] test_msg = 384'h54686520717569636b2062726f776e20666f78206a756d7073206f76657220746865206c617a7920646f678000000000;
    reg [255:0] golden_hash = 256'h5d4cbde6350ea4c174bd65b5b332f8408f99740b81aa02735eaefbcf0ba0339e;

    reg [255:0] hash_256;
    reg [31:0] length;
    integer i;

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
        $dumpfile("tb_xof_ascon_engine.vcd");
        $dumpvars(0,tb_xof_ascon_engine);
        
        clk = 1'b1;
        forever begin
            #1 clk = ~clk;
        end
    end
    
    // Test procedure for ASCON-XOF
    initial begin
        // Wait for clock
        length = 'd256;
        #2

        reset;

        //Send start sequence
        bd_in_data = 16'b0;
        bd_in_config = {5'b0, `CONF, 1'b1, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0, tx_toggle};
        //$display("Send data: %h %h", bd_in_data, bd_in_config);
        wait(toggle != prev_toggle);
        //$display("Recv: %h %h", bd_out_data, bd_out_config);
        
        // Transfer length of required hash
        for (i =0; i < 2; i = i+1) begin
            tx_toggle = ~tx_toggle;
            prev_toggle = ~ prev_toggle;
            bd_in_data = length[31:16];
            length = length << 16;
            if (i == 1) bd_in_config  = {5'b0, `LEN, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `LEN, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            
            //$display("Send data: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
        end

        // Send data to hash
        for (i =0; i < 4; i = i+1) begin
            tx_toggle = ~tx_toggle;
            prev_toggle = ~ prev_toggle;
            bd_in_data = null_msg[63:48];
            null_msg = null_msg << 16;
            if (i == 3) bd_in_config  = {5'b0, `MSG, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            else bd_in_config  = {5'b0, `MSG, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            wait(toggle != prev_toggle);
            
        end

        for (i = 0; i < 16; i=i+1) begin
            prev_toggle = ~ prev_toggle;
            tx_toggle = ~tx_toggle;
            bd_in_data = 16'b0;
            bd_in_config  = {5'b0, `OK, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
            //$display("Send data: %h %h", bd_in_data, bd_in_config);
            wait(toggle != prev_toggle);
            //$display("Recv hash: %h %h", bd_out_data, bd_out_config);
            hash_256[15:0] = bd_out_data;
            if (i < 15) hash_256 = hash_256 << 16;
            ////$display("Part that was send: %h", bd_out_data );
            ////$display("Recovered hash: %h", hash_256);
        end

        // Reset trigger for Ascon engine
        prev_toggle = ~ prev_toggle;
        tx_toggle = ~tx_toggle;
        bd_in_data = 16'b0;
        bd_in_config  = {5'b0, `OK, 1'b1, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, tx_toggle};
        #50

        if (hash_256 == golden_hash) begin
            $display("XOF:\tPASS");
        end else begin
            $display("XOF:\tFAILED.");
            $display("Exp:\t%h", golden_hash);
            $display("Got:\t%h", hash_256);
        end
        //$display("Hash is: %h", hash_256);
        #20;
        $finish;
    end 

endmodule
