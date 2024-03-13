`timescale 1ns / 1ps

module ascon_permutation #(parameter ROUNDS = 6,
                           parameter RCON = 8'h3C)(
    input clk,
    input rst,
    
   // FIFO signals for receving data 
    input [319:0] state_in,
    output reg ready_out,
    input valid_in,

    // FIFO signals for passing data to ASCON module
    input ready_in,
    output reg valid_out,    
    output reg [319:0] state_out
    );

    // FSM-Sates for Permutation-Engine
    localparam
        WAIT = 0,
        ROUND = 1,
        DONE = 2,
        PC = 3,
        PS = 4,
        PL = 5;

    reg [2:0] internal_state;

    reg perm_done;
    reg [63:0] x_0;
    reg [63:0] x_1;
    reg [63:0] x_2;
    reg [63:0] x_3;
    reg [63:0] x_4;
    
    // Tmp register for sbox calculation
    reg [63:0] t_0;
    reg [63:0] t_1;
    reg [63:0] t_2;
    reg [63:0] t_3;
    reg [63:0] t_4;

    reg [5:0] counter;
    reg [1:0] pipelin_cnt;

    task reset();
    begin
        valid_out <= 1'b0;
            ready_out <= 1'b1;
            internal_state <= WAIT;
            state_out <= 320'b0;
            counter <= 0;
            pipelin_cnt <= 0;
    end
    endtask

    always @(posedge clk) begin
        if (!rst) begin
            reset;
        end else begin
            case (internal_state)
                WAIT : begin
                    valid_out <= 1'b0;
                    ready_out <= 1'b1;
                    counter <= 0;
                    if (valid_in) begin
                        ready_out <= 1'b0;
                        internal_state <= PC;

                        x_0 <= state_in[319:256];
                        x_1 <= state_in[255:192];
                        x_2 <= state_in[191:128];
                        x_3 <= state_in[127:064];
                        x_4 <= state_in[063:000];
                    end
                end
                PC : begin
                    if (counter != ROUNDS) begin
                        x_2 <= x_2 ^ (RCON + ('h0f*(ROUNDS-counter)));
                        pipelin_cnt <= 0;
                        internal_state <= PS;
                    end else begin
                        state_out <= {x_0, x_1, x_2, x_3, x_4};
                        internal_state <= DONE;
                        valid_out <= 'b1;
                        counter <= 0;
                    end
                end
                PS: begin
                    pipelin_cnt <= pipelin_cnt + 1;
                    if (pipelin_cnt == 0) begin
                            x_0 <= x_0 ^ x_4;
                            x_4 <= x_4 ^ x_3;
                            x_2 <= x_2 ^ x_1;
                            
                            t_0 <= ~(x_0 ^ x_4);
                            t_1 <= ~x_1;
                            t_2 <= ~(x_2 ^ x_1);
                            t_3 <= ~x_3;
                            t_4 <= ~(x_4 ^ x_3);
                    end else if (pipelin_cnt == 1) begin

                            t_0 <= t_0 & x_1;
                            t_1 <= t_1 & x_2;
                            t_2 <= t_2 & x_3;
                            t_3 <= t_3 & x_4;
                            t_4 <= t_4 & x_0;
                    end else if (pipelin_cnt == 2) begin
                            x_0 <= x_0 ^ t_1;
                            x_1 <= x_1 ^ t_2;
                            x_2 <= x_2 ^ t_3;
                            x_3 <= x_3 ^ t_4;
                            x_4 <= x_4 ^ t_0;
                    end else if (pipelin_cnt == 3) begin
                            x_1 <= x_1 ^ x_0;
                            x_0 <= x_0 ^ x_4;
                            x_3 <= x_3 ^ x_2;
                            x_2 <= ~x_2;
                            internal_state <= PL;
                    end
                end
                PL: begin
                    x_0 <= x_0 ^ {x_0[18:0], x_0[63:19]} ^ {x_0[27:0], x_0[63:28]};
                    x_1 <= x_1 ^ {x_1[60:0], x_1[63:61]} ^ {x_1[38:0], x_1[63:39]};
                    x_2 <= x_2 ^ {x_2[0:0], x_2[63:1]} ^ {x_2[5:0], x_2[63:6]};
                    x_3 <= x_3 ^ {x_3[9:0], x_3[63:10]} ^ {x_3[16:0], x_3[63:17]};
                    x_4 <= x_4 ^ {x_4[6:0], x_4[63:7]} ^ {x_4[40:0], x_4[63:41]};

                    counter <= counter + 1;
                    internal_state <= PC;
                end 
                DONE : begin
                    // Assert ready signal from sink
                    if (ready_in == 1) begin
                        internal_state <= WAIT;
                        ready_out <= 1'b1;
                        valid_out <= 'b0;
                    end
                end
                default : begin
                    reset;
                end
            endcase
        end 
    end
endmodule


