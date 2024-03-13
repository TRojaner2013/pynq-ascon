`timescale 1ns / 1ps

`ifndef PARAMS
`include "ascon_constants.vh"
`define PARAMS
`endif

module ascon_engine(
    input clk,
    input rst, 
    
    // Input for block data
    input [15:0] bd_in_data,
    input [15:0] bd_in_config,
    
    output reg [15:0] bd_out_data,
    output reg [15:0] bd_out_config
    );  
    

    // FSM-States for ASCON-Engine
    localparam
        WAIT_INIT = 0,
        INIT_ENC_DEC = 1,
        WAIT_MSG = 2,
        SEND_HASH = 3,
        WAIT_KEY = 4,
        WAIT_NONCE = 5,
        WAIT_TAG = 6,
        ENC = 7,
        DEC = 8,
        ENC_DEC_WRAPUP = 9,
        RST = 10,
        WAIT_LEN = 11,
        SEND_TAG = 12;

    // MODES for ASCON-Engine 
    localparam
        MODE_ENC_128 = 0,
        MODE_DEC_128 = 1,
        MODE_ENC_128a = 2,
        MODE_DEC_128a = 3,
        MODE_HASH = 4,
        MODE_XOF = 5;

    // Parameters for ASCON Engine communicaton with Permutation Engine.
    localparam
        PERM_INIT = 0,
        PERM_INV = 1,
        PERM_WAIT = 2,
        PERM_DONE = 3;

    localparam
        R06 = 0,
        R08 = 1,
        R12 = 2;

    reg [2:0] fsm_perm;
    
    // Block_data_input
    reg [127:000] in_data; // Represents data from MMIO
    wire [3:0] data_type; // Represents data type from MMIO
    wire end_of_type; // Represents 
    wire end_of_input; // Represents last data block for operation
    wire ascon_128a;
    wire decrypt; // Will use decrypt
    wire extend; // Will use extended hash function.
    wire hash; // Will use hash
    wire toggle;

    assign data_type = bd_in_config[10:7]; // Represents data type from DMA
    assign end_of_type = bd_in_config[6]; // Represents 
    assign end_of_input = bd_in_config[5]; // Represents last data block for operation
    assign decrypt = bd_in_config[4]; // Will use decrypt
    assign ascon_128a = bd_in_config[3];
    assign extend = bd_in_config[2]; // Will use extended hash function.
    assign hash = bd_in_config[1]; // Will use hash
    assign toggle = bd_in_config[0];

     reg prev_toggle;
     reg prev_out_toggle;
     reg eot_in;
    
    
    // Block data output
    reg [127:000] data_out;
    reg [3:0] out_data_type;
    reg do_end_of_type;
    reg do_end_of_output; 
    reg auth; 
    reg toggle_out;
    reg out_valid;
    reg error;

    reg [3:0] internal_state;
    reg [2:0] op_mode;
    reg [4:0]reset_cnt;

    reg [31:0] length_ctrl; // This allows a maximum of 2>>32 blocks to be created with XOF.
    reg [3:0] rx_cnt;
    reg [3:0] tx_cnt;
    reg [3:0] rx_cnt_goal;
    reg [3:0] tx_cnt_goal;
    reg send;
    reg xored;
    
    // ASCON-128, ASCON-Hash, ASCON Xof (r=64)
    reg [319:0] ascon_state;
    reg [127:0] key;
    reg [127:0] nonce;
    reg [127:0] tag;
    reg [127:0] tag_res;
    reg [1:0] mode_a;
    reg [1:0] mode_b;

    // Permutation instance these should be mostly regs
    wire [319:000] state_out_12;
    wire [319:000] state_out_08;
    wire [319:000] state_out_06;
    reg [319:0] perm_state_in;
    wire ready_out_12;
    wire ready_out_08;
    wire ready_out_06;
    reg valid_in_12;
    reg valid_in_08;
    reg valid_in_06;
    wire valid_out_12;
    wire valid_out_08;
    wire valid_out_06;
    reg  ready_in;
    reg [1:0] perm_mode;
    reg perm_ena;
    reg [319:0] buffer;
    
    ascon_permutation #(.ROUNDS(12)) perm_12(.clk (clk),
                                             .rst (rst),
                                             .state_in (ascon_state),
                                             .ready_out (ready_out_12),
                                             .valid_in (valid_in_12),
                                             .ready_in (ready_in),
                                             .valid_out (valid_out_12),
                                             .state_out (state_out_12)
                                            );

    ascon_permutation #(.ROUNDS(8)) perm_08(.clk (clk),
                                             .rst (rst),
                                             .state_in (ascon_state),
                                             .ready_out (ready_out_08),
                                             .valid_in (valid_in_08),
                                             .ready_in (ready_in),
                                             .valid_out (valid_out_08),
                                             .state_out (state_out_08)
                                            );

    ascon_permutation #(.ROUNDS(6)) perm_06(.clk (clk),
                                             .rst (rst),
                                             .state_in (ascon_state),
                                             .ready_out (ready_out_06),
                                             .valid_in (valid_in_06),
                                             .ready_in (ready_in),
                                             .valid_out (valid_out_06),
                                             .state_out (state_out_06)
                                            );
    task send_error ();
        // Task that updates internal state & registers on error.
        begin
            internal_state <= RST;
            ascon_state <= 0;
            out_data_type <= `ABORT;
            do_end_of_type <= 1'b1;
            do_end_of_output <= 1'b1; 
            auth <= 1'b0;
            toggle_out <= ~toggle_out;
            out_valid <= 1'b1;
            error <= 1'b1;
            bd_out_data <= 0;
            perm_ena <= 0;
            send <= 1'b0;
            xored <= 1'b0;
        end
    endtask
    
    task send_ACK ();
        // Task that updates internal state & registers on error.
        begin
            out_data_type <= `OK;
            do_end_of_type <= 1'b1;
            do_end_of_output <= 1'b1; 
            auth <= 1'b0;
            toggle_out <= ~toggle_out;
            out_valid <= 1'b1;
            error <= 1'b0;
            bd_out_data <= 0;
        end
    endtask

        task send_plain ();
        // Task that updates internal state & registers on error.
        begin
            out_data_type <= `OK;
            do_end_of_type <= 1'b1;
            do_end_of_output <= 1'b1; 
            auth <= 1'b0;
            toggle_out <= ~toggle_out;
            out_valid <= 1'b1;
            error <= 1'b0;
            bd_out_data <= 0;
        end
    endtask

    task send_cipher ();
        // Task that updates internal state & registers on error.
        begin
            out_data_type <= `CIPHER;
            do_end_of_output <= 1'b0; 
            auth <= 1'b0;
            toggle_out <= ~toggle_out;
            out_valid <= 1'b1;
            error <= 1'b0;
            bd_out_data <= data_out;
        end
    endtask

    task set_rx_tx_cnt ();
        begin
            rx_cnt <= 0;
            tx_cnt <= 0;
        end
    endtask
    
    task reset();
        begin
            internal_state <= WAIT_INIT;
            bd_out_data <= 32'b0;
            out_data_type <= 3'b0;
            do_end_of_type <= 1'b0;
            do_end_of_output <= 1'b0;
            auth <= 1'b0;
            toggle_out <= 1'b0;
            prev_out_toggle <= 1'b0;
            out_valid <= 1'b0;
            ascon_state <= 320'b0;
            prev_toggle <= 1'b0;
            set_rx_tx_cnt;
            rx_cnt_goal <= 4;
            tx_cnt_goal <= 4;
            error <= 1'b0;
            eot_in <= 1'b0;
            perm_ena <= 0;
            key <= 128'b0;
            nonce <= 128'b0;
            mode_a <= R12;
            mode_b <= R06;
            send <= 1'b0;
            xored <= 1'b0;
            reset_cnt <= 0;

            tag <= 0;
            tag_res <= 0;
            in_data <= 0;
            data_out <= 0;
            perm_mode <= mode_a;
            length_ctrl <= 0;
            op_mode <= 0;
            bd_out_config <= 0;

        end
    endtask

    always @(posedge clk) begin
    
        if (rst == 0) begin
            reset;            
        end else begin        
            if (prev_out_toggle != toggle_out) begin // Send out buffer on new data
                bd_out_config <= {6'b000000, out_data_type, do_end_of_type, do_end_of_output, auth, toggle_out, out_valid, error};
                prev_out_toggle <= toggle_out;
            end

            case (internal_state)
                // FSM FOR ASCON CIPHER SUITE (128, 1288, HASH, XOF)
                WAIT_INIT: begin
                    // Start communication with PS via CONFIG block
                    set_rx_tx_cnt;

                    if (data_type == `CONF && !hash && !extend && !decrypt && !ascon_128a) begin
                        /*
                         * ENCRYPTION ASCON 128
                         */
                        op_mode <= MODE_ENC_128;
                        mode_a <= R12;
                        mode_b <= R06;
                        send_ACK;
                        internal_state <= WAIT_KEY;
                    end else if (data_type == `CONF && !hash && !extend && decrypt && !ascon_128a) begin
                        /*
                         * DECRYPTION ASCON 128
                         */
                        op_mode <= MODE_DEC_128;
                        mode_a <= R12;
                        mode_b <= R06;
                        send_ACK;
                        internal_state <= WAIT_KEY;
                    end else if (data_type == `CONF && !hash && !extend && !decrypt && ascon_128a) begin
                        /*
                         * ENCRYPTION ASCON 128A
                         */
                        op_mode <= MODE_ENC_128a;
                        mode_a <= R12;
                        mode_b <= R08;
                        send_ACK;
                        internal_state <= WAIT_KEY;
                        rx_cnt_goal <= 8;
                        tx_cnt_goal <= 8;
                    end else if (data_type == `CONF && !hash && !extend && decrypt && ascon_128a) begin
                        /*
                         * DECYPTION ASCON 128A
                         */
                        op_mode <= MODE_DEC_128a;
                        mode_a <= R12;
                        mode_b <= R08;
                        send_ACK;
                        internal_state <= WAIT_KEY;
                        rx_cnt_goal <= 'd8;
                        tx_cnt_goal <= 'd8;
                    end else if (data_type == `CONF && hash && !extend && !decrypt && !ascon_128a) begin
                         /*
                         * ASCON HASH
                         */
                        op_mode <= MODE_HASH;
                        mode_a <= R12;
                        mode_b <= R12;
                        ascon_state <= 320'hee9398aadb67f03d8bb21831c60f1002b48a92db98d5da6243189921b8f8e3e8348fa5c9d525e140;
                        length_ctrl <= 32'd256;
                        send_ACK;
                        internal_state <= WAIT_MSG;
                    end else if (data_type == `CONF && !hash && extend && !decrypt && !ascon_128a) begin
                        /*
                         * ASCON XOF
                         */
                        op_mode <= MODE_XOF;
                        mode_a <= R12;
                        mode_b <= R12;
                        ascon_state <= 320'hb57e273b814cd4162b51042562ae242066a3a7768ddf22185aad0a7a8153650c4f3e0e32539493b6;
                        length_ctrl <= 32'b0;
                        send_ACK;
                        internal_state <= WAIT_LEN;
                    end else if (data_type == `CONF) send_error;
                end
                WAIT_LEN: begin
                    if ((toggle != prev_toggle))begin
                        prev_toggle <= toggle;
                        // Check for correct block data type
                        if (data_type != `LEN) begin
                            send_error;
                        end else  begin 
                            send_ACK;
                            length_ctrl <= {length_ctrl[15:0], bd_in_data};
                            if (end_of_type) internal_state <= WAIT_MSG;
                        end
                    end
                end
                WAIT_MSG: begin
                    // ToDo: Rename state to AWAIT DATA
                    if ((toggle != prev_toggle) && (rx_cnt < rx_cnt_goal) )begin
                        prev_toggle <= toggle;
                        if (data_type == `SKIP_AD && rx_cnt == 0) begin
                            // No additional data is used -> Skip directly
                            send_ACK;
                            set_rx_tx_cnt;
                            if (op_mode == MODE_DEC_128 || op_mode == MODE_DEC_128a) begin 
                                internal_state <= DEC;
                                ascon_state[0] <= ascon_state[0] ^ 1'b1;
                            end else if (op_mode == MODE_ENC_128 || op_mode == MODE_ENC_128a) begin
                                internal_state <= ENC;
                                ascon_state[0] <= ascon_state[0] ^ 1'b1;
                            end else send_error;
                        end else if (data_type == `MSG || data_type == `AD) begin 
                            send_ACK;
                            in_data <= {in_data[112:0], bd_in_data};
                            rx_cnt <= rx_cnt + 1;
                            perm_ena <= 0;
                            eot_in <= end_of_type;
                        end else send_error;
                    end else if (rx_cnt == rx_cnt_goal) begin
                        if (fsm_perm == PERM_INIT && !perm_ena) begin
                            if (op_mode == MODE_ENC_128a || op_mode == MODE_DEC_128a) ascon_state <= {ascon_state[319:192]^in_data, ascon_state[191:0]};
                            else ascon_state <= {ascon_state[319:256]^in_data[63:0], ascon_state[255:0]};

                            perm_mode <= mode_b;
                            perm_ena <= 1;
                        end else if (fsm_perm == PERM_DONE) begin
                            perm_ena <= 0;
                            ascon_state <= buffer;
                            set_rx_tx_cnt;
                            if (eot_in) begin
                                eot_in <= 0;
                                if (op_mode == MODE_DEC_128 || op_mode == MODE_DEC_128a) begin 
                                    internal_state <= DEC;
                                    ascon_state <= buffer ^ 1'b1;
                                end else if (op_mode == MODE_ENC_128 || op_mode == MODE_ENC_128a) begin 
                                    internal_state <= ENC;
                                    ascon_state <= buffer ^ 1'b1;
                                end else internal_state <= SEND_HASH;
                            end
                        end
                    end
                end
                SEND_HASH: begin
                    if (rx_cnt == 0) begin
                        //Computation already done -> Send directly
                        data_out[63:0] <= ascon_state[319:256];
                        rx_cnt <= rx_cnt_goal;
                    end else if (rx_cnt < rx_cnt_goal) begin
                        // Accumulate date for send buffer
                        if (fsm_perm == PERM_INIT && !perm_ena) begin
                            perm_mode <= mode_a;
                            perm_ena <= 1;
                        end else if (fsm_perm == PERM_DONE) begin
                            perm_ena <= 0;
                            ascon_state <= buffer;
                            data_out[63:0] <= buffer[319:256];
                            rx_cnt <= rx_cnt_goal;
                        end                   
                    end else if ((toggle != prev_toggle) && rx_cnt == rx_cnt_goal && tx_cnt < tx_cnt_goal) begin
                        // Ready for transmission
                        prev_toggle <= toggle;

                        length_ctrl <= length_ctrl - 16;
                        tx_cnt <= tx_cnt + 1;
                        bd_out_data <= data_out[63:48];
                        data_out <= data_out << 16;
                        out_data_type <= `HASH;
                        do_end_of_type <= 1'b0;
                        do_end_of_output <= 1'b0; 
                        auth <= 1'b0;
                        toggle_out <= ~toggle_out;
                        out_valid <= 1'b1;
                        error <= 1'b0;

                        if (tx_cnt == tx_cnt_goal-1) begin
                            // Reset counter
                            set_rx_tx_cnt;
                            rx_cnt <= 1;
                        end
                        if (length_ctrl <= 16) begin
                            // Signal end of transmission
                            do_end_of_type <= 1'b1;
                            do_end_of_output <= 1'b1;
                            internal_state <= RST;
                        end
                    end
                end
                WAIT_KEY: begin
                    if ((toggle != prev_toggle) && (rx_cnt < 8) )begin
                        prev_toggle <= toggle;
                        // Check for correct block data type
                        if (data_type != `KEY) begin
                            send_error;
                        end else begin
                            send_ACK;
                            key <= key<<16 ^ bd_in_data;
                            rx_cnt <= rx_cnt + 1;
                            perm_ena <= 0;
                            eot_in <= end_of_type;
                        end                    
                    end else if (rx_cnt == 8) begin
                        if (eot_in) internal_state <= WAIT_NONCE;
                        set_rx_tx_cnt;
                    end
                end
                WAIT_NONCE: begin
                        if ((toggle != prev_toggle) && (rx_cnt < 8) )begin
                        prev_toggle <= toggle;
                        if (data_type != `NONCE) begin
                            send_error;
                        end else begin
                            send_ACK;
                            nonce <= nonce<<16 ^ bd_in_data;
                            rx_cnt <= rx_cnt + 1;
                            perm_ena <= 0;
                            eot_in <= end_of_type;
                        end                    
                    end else if (rx_cnt == 8) begin
                        if (eot_in) begin
                            if (op_mode == MODE_DEC_128 || op_mode == MODE_DEC_128a) internal_state <= WAIT_TAG;
                            else internal_state <= INIT_ENC_DEC;
                        end
                        set_rx_tx_cnt;
                    end
                end
                WAIT_TAG: begin
                    if ((toggle != prev_toggle) && (rx_cnt < 8) )begin
                        prev_toggle <= toggle;
                        if (data_type != `TAG) begin
                            send_error;
                        end else begin
                            send_ACK;
                            tag <= tag<<16 ^ bd_in_data;
                            rx_cnt <= rx_cnt + 1;
                            perm_ena <= 0;
                            eot_in <= end_of_type;
                        end                    
                    end else if (rx_cnt == 8) begin
                        if (eot_in) internal_state <= INIT_ENC_DEC;
                        set_rx_tx_cnt;
                    end
                end
                INIT_ENC_DEC: begin
                    if (fsm_perm == PERM_INIT && !perm_ena) begin
                        if (op_mode == MODE_ENC_128 || op_mode == MODE_DEC_128) ascon_state <= {64'h80400c0600000000, key,nonce};
                        else ascon_state <= {64'h80800c0800000000, key, nonce};
                        perm_mode <= mode_a;
                        perm_ena <= 1;
                    end else if (fsm_perm == PERM_DONE) begin
                        perm_ena <= 0;
                        ascon_state <= buffer ^ {192'b0, key};
                        internal_state <= WAIT_MSG;
                    end
                end
                ENC: begin
                    // First await plaintext from PS
                    if ((toggle != prev_toggle) && (rx_cnt < rx_cnt_goal))begin
                        prev_toggle <= toggle;
                        if (data_type != `PLAIN) begin
                            send_error;
                        end else begin 
                            send_ACK;
                            in_data <= in_data<<16 ^ bd_in_data;
                            rx_cnt <= rx_cnt + 1;
                            perm_ena <= 0;
                            eot_in <= end_of_type;
                        end
                    end else if (rx_cnt == rx_cnt_goal && !xored && !send) begin
                    // Plain text is there, we can xor to get cipher text.
                        if (op_mode == MODE_ENC_128) begin
                             ascon_state <= {ascon_state[319:256] ^ in_data[63:0], ascon_state[255:0]};
                             if (eot_in) ascon_state <= {ascon_state[319:256] ^ in_data[63:0], ascon_state[255:0] ^ {key, 128'b0}};
                        end else begin 
                            ascon_state <= {ascon_state[319:192] ^ in_data, ascon_state[191:0]};
                            if (eot_in) ascon_state <= {ascon_state[319:192] ^ in_data, ascon_state[191:0] ^ {key, 64'b0}};
                        end
                        xored <= 1'b1;
                    end else if (rx_cnt == rx_cnt_goal && xored && send) begin
                    // Wait for ACK from PS to send next piece of Plaintext
                        if ((toggle != prev_toggle) && rx_cnt == rx_cnt_goal && tx_cnt < tx_cnt_goal) begin
                            // Ready for transmission
                            prev_toggle <= toggle;
                            tx_cnt <= tx_cnt + 1;

                            if (op_mode == MODE_ENC_128) bd_out_data <= data_out[63:48];
                            else bd_out_data <= data_out[127:112];
                            
                            data_out <= data_out << 16;
                            out_data_type <= `CIPHER;
                            do_end_of_type <= 1'b0;
                            do_end_of_output <= 1'b0; 
                            auth <= 1'b0;
                            toggle_out <= ~toggle_out;
                            out_valid <= 1'b1;
                            error <= 1'b0;

                            if (tx_cnt == tx_cnt_goal-1) begin
                                // Reset counter after full transmision
                                set_rx_tx_cnt;
                                send <= 0;
                                xored <= 0;
                                if (eot_in) begin
                                    // Got last piece of ciphertext
                                    length_ctrl <= 'd128; // Set length for sending 128 bit tag
                                    do_end_of_type <= 1'b1;
                                    internal_state <= SEND_TAG;
                                end
                            end
                        end 
                    end else if ((rx_cnt == rx_cnt_goal && xored && !send)) begin
                        // Compute new state
                        if (fsm_perm == PERM_INIT && !perm_ena) begin
                            // Save old state for output
                            if (op_mode == MODE_ENC_128) data_out <= ascon_state[319:256];
                            else data_out <= ascon_state[319:192];

                            perm_mode <= mode_b;
                            if (eot_in) perm_mode <= mode_a;
                            perm_ena <= 1;
                        end else if (fsm_perm == PERM_DONE) begin
                            perm_ena <= 0;
                            ascon_state <= buffer;
                            if (eot_in) tag_res <= buffer[127:0] ^ key;
                            send <= 1;
                        end
                    end
                end
                DEC: begin
                    // First await ciphertext from PS
                    if ((toggle != prev_toggle) && (rx_cnt < rx_cnt_goal))begin
                        prev_toggle <= toggle;
                        if (data_type != `CIPHER) begin
                            send_error;
                        end else begin 
                            send_ACK;
                            in_data <= in_data<<16 ^ bd_in_data;
                            rx_cnt <= rx_cnt + 1;
                            perm_ena <= 0;
                            eot_in <= end_of_type;
                        end
                    end else if (rx_cnt == rx_cnt_goal && !xored && !send) begin
                    // Plain text is there, we can xor to get cipher text.
                        if (op_mode == MODE_DEC_128) begin
                            data_out <= ascon_state[319:256] ^ in_data[63:0];
                             ascon_state <= {in_data[63:0], ascon_state[255:0]};
                             if (eot_in) ascon_state <= {in_data[63:0], ascon_state[255:0] ^ {key, 128'b0}}; ;
                        end else begin 
                            data_out <= ascon_state[319:192] ^ in_data;
                            ascon_state <= {in_data, ascon_state[191:0]};
                            if (eot_in) ascon_state[191:00] <= ascon_state[191:00] ^ {key, 64'b0};
                        end
                        xored <= 1'b1;
                    end else if (rx_cnt == rx_cnt_goal && xored && send) begin
                    // Wait for ACK from PS to send next piece of Plaintext
                        if ((toggle != prev_toggle) && rx_cnt == rx_cnt_goal && tx_cnt < tx_cnt_goal) begin
                            // Ready for transmission
                            prev_toggle <= toggle;
                            tx_cnt <= tx_cnt + 1;

                            if (op_mode == MODE_DEC_128) bd_out_data <= data_out[63:48];
                            else bd_out_data <= data_out[127:112];
                            
                            data_out <= data_out << 16;
                            out_data_type <= `PLAIN;
                            do_end_of_type <= 1'b0;
                            do_end_of_output <= 1'b0; 
                            auth <= 1'b0;
                            toggle_out <= ~toggle_out;
                            out_valid <= 1'b1;
                            error <= 1'b0;

                            if (tx_cnt == tx_cnt_goal-1) begin
                                // Reset counter after full transmision
                                set_rx_tx_cnt;
                                send <= 0;
                                xored <= 0;
                                if (eot_in) begin
                                    // Got last piece of ciphertext
                                    do_end_of_type <= 1'b1;
                                    internal_state <= ENC_DEC_WRAPUP;
                                end
                            end
                        end 
                    end else if ((rx_cnt == rx_cnt_goal && xored && !send)) begin
                        // Compute new state
                        if (fsm_perm == PERM_INIT && !perm_ena) begin
                            perm_mode <= mode_b;
                            if (eot_in) perm_mode <= mode_a;
                            perm_ena <= 1;
                        end else if (fsm_perm == PERM_DONE) begin
                            perm_ena <= 0;
                            ascon_state <= buffer;
                            if (eot_in) tag_res <= buffer[127:0] ^ key;
                            send <= 1;
                        end
                    end
                end
                SEND_TAG: begin
                    if ((toggle != prev_toggle) && (length_ctrl >= 16)) begin
                        // Ready for transmission
                        prev_toggle <= toggle;
                        length_ctrl <= length_ctrl - 16;

                        // Check for correct block data type
                        bd_out_data <= tag_res[127:112];
                        tag_res <= tag_res << 16;
                        out_data_type <= `TAG;
                        do_end_of_type <= 1'b0;
                        do_end_of_output <= 1'b0; 
                        auth <= 1'b0;
                        toggle_out <= ~toggle_out;
                        out_valid <= 1'b1;
                        error <= 1'b0;
                        
                        if (length_ctrl <= 16) begin
                            // Signal end of transmission
                            do_end_of_type <= 1'b1;
                            do_end_of_output <= 1'b1;
                            internal_state <= RST;
                        end
                    end
                end
                ENC_DEC_WRAPUP: begin
                    if (toggle != prev_toggle) begin
                        prev_toggle <= toggle;
                        internal_state <= RST;
                        out_data_type <= `TAG;
                        do_end_of_type <= 1'b1;
                        do_end_of_output <= 1'b1;
                        toggle_out <= ~toggle_out;
                        out_valid <= 1'b1;
                        error <= 1'b0;
                        bd_out_data <= 0;

                        if ((op_mode == MODE_DEC_128 || op_mode == MODE_DEC_128a) && tag != tag_res) begin
                            // Ceck provided tag and calculated tag for decryption.
                            // Note that normally we must do this before providing plaintext to
                            // receiver.
                            auth <= 1'b0;
                        end else begin
                            // Tag matched the one calculated during decryption
                            auth <= 1'b1;
                        end
                    end
                end
                RST: begin
                     if (toggle != prev_toggle) begin
                        reset;
                     end 
                end
                default: begin
                    reset;
                end
            endcase
        end
    end
    
   // Handle comunication with permutation engine 
    always @(posedge clk) begin
        if (!rst) begin
            fsm_perm <= PERM_INIT;
            valid_in_12 <= 0;
            valid_in_08 <= 0;
            valid_in_06 <= 0;
            ready_in <= 0;
            buffer <= 0;
        end else if (perm_ena) begin
            case (fsm_perm)
                PERM_INIT: begin
                    case (perm_mode)
                        R12: begin
                            if (ready_out_12) begin
                                valid_in_12 <= 1;
                                ready_in <= 1;
                                fsm_perm <= PERM_WAIT;
                            end
                        end
                        R08: begin
                            if (ready_out_08) begin
                                valid_in_08 <= 1;
                                ready_in <= 1;
                                fsm_perm <= PERM_WAIT;
                            end
                        end
                        R06: begin
                            if (ready_out_06) begin
                                valid_in_06 <= 1;
                                ready_in <= 1;
                                fsm_perm <= PERM_WAIT;
                            end
                        end
                        default: begin
                            if (ready_out_12) begin
                                valid_in_12 <= 1;
                                ready_in <= 1;
                                fsm_perm <= PERM_WAIT;
                            end
                        end
                    endcase
                end
                PERM_WAIT: begin
                    valid_in_12 <= 0;
                    valid_in_08 <= 0;
                    valid_in_06 <= 0;
                    case (perm_mode)
                        R12: begin
                            if (valid_out_12) begin
                                buffer <= state_out_12;
                                ready_in <= 0;
                                fsm_perm <= PERM_DONE;
                            end
                        end
                        R08: begin
                            if (valid_out_08) begin
                                buffer <= state_out_08;
                                ready_in <= 0;
                                fsm_perm <= PERM_DONE;
                            end
                        end
                        R06: begin
                            if (valid_out_06) begin
                                buffer <= state_out_06;
                                ready_in <= 0;
                                fsm_perm <= PERM_DONE;
                            end
                        end
                        default: begin
                            if (valid_out_12) begin
                                buffer <= state_out_12;
                                ready_in <= 0;
                                fsm_perm <= PERM_DONE;
                            end
                        end
                    endcase
                end
                PERM_DONE: begin
                    fsm_perm <= PERM_INIT;
                end
                default: begin
                    fsm_perm <= PERM_INIT;
                    valid_in_12 <= 0;
                    valid_in_08 <= 0;
                    valid_in_06 <= 0;
                    ready_in <= 0;
                    buffer <= 0;
                end
            endcase
        end 
    end


endmodule
