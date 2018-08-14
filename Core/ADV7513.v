`include "config.inc"

module ADV7513(
    input clk,
    input reset,
    input hdmi_int,
    input VSYNC,
    input DE,

    inout sda,
    inout scl,
    input restart,
    output reg ready,
    output DebugData debugData_out,

    input HDMIVideoConfig hdmiVideoConfig
);

reg [6:0] i2c_chip_addr;
reg [7:0] i2c_reg_addr;
reg [7:0] i2c_value;
reg i2c_enable;
reg i2c_is_read;

wire [7:0] i2c_data;
wire i2c_done;
wire i2c_ack_error;

I2C I2C(
    .clk           (clk),
    .reset         (1'b1),

    .chip_addr     (i2c_chip_addr),
    .reg_addr      (i2c_reg_addr),
    .value         (i2c_value),
    .enable        (i2c_enable),
    .is_read       (i2c_is_read),

    .sda           (sda),
    .scl           (scl),

    .data          (i2c_data),
    .done          (i2c_done),
    .i2c_ack_error (i2c_ack_error),

    .divider       (hdmiVideoConfig.divider)
);

(* syn_encoding = "safe" *)
reg [1:0] state;
reg [7:0] cmd_counter;

reg VSYNC_reg = 0;
reg DE_reg = 0;

DebugData debugData = { 8'h00, 8'h00, 10'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00, 8'h00 };

localparam CHIP_ADDR = 7'h39;
localparam  s_start  = 0,
            s_wait   = 1,
            s_wait_2 = 2,
            s_idle   = 3;

localparam INIT_START    = 8'd0;
localparam PLL_CHECK_1   = 8'd32;
localparam INIT_NEXT     = 8'd15;
localparam CHIP_REVISION = 8'd40;
localparam ID_CHECK_H    = 8'd42;
localparam ID_CHECK_L    = 8'd44;
localparam PLL_CHECK_2   = 8'd46;
localparam CTS_CHECK_1   = 8'd48;
localparam CTS_CHECK_2   = 8'd50;
localparam CTS_CHECK_3   = 8'd52;
localparam VIC_CHECK_1   = 8'd54;
localparam VIC_CHECK_2   = 8'd56;
localparam MISC_CHECK    = 8'd58;
localparam CTS_CHECK_3_2 = 8'd60;
// CSC
localparam CSC = 8'd127;

localparam GOTO_READY    = 8'b11111111;

initial begin
    ready <= 0;
end

assign debugData_out = debugData;

always @ (posedge clk) begin

    if (restart) begin
        debugData.restart_count <= debugData.restart_count + 1'b1;
    end

    if (~reset) begin
        state <= s_start;
        cmd_counter <= 0;
        i2c_enable <= 1'b0;
        ready <= 0;
    end else begin
        VSYNC_reg <= VSYNC;
        DE_reg <= DE;
        case (state)
            
            s_start: begin
                if (i2c_done) begin
                    
                    case (cmd_counter)
                    
                         0: write_i2c(CHIP_ADDR, 16'h_41_10); // [6]:   power down = 0b0, all circuits powered up
                                                              // [5]:   fixed = 0b0
                                                              // [4]:   reserved = 0b1
                                                              // [3:2]: fixed = 0b00
                                                              // [1]:   sync adjustment enable = 0b0, disabled
                                                              // [0]:   fixed = 0b0
                         1: write_i2c(CHIP_ADDR, 16'h_98_03); // Fixed register
                         2: write_i2c(CHIP_ADDR, 16'h_9A_E0); // Fixed register
                         3: write_i2c(CHIP_ADDR, 16'h_9C_30); // Fixed register
                         4: write_i2c(CHIP_ADDR, 16'h_9D_01); // Fixed register
                         5: write_i2c(CHIP_ADDR, 16'h_A2_A4); // Fixed register
                         6: write_i2c(CHIP_ADDR, 16'h_A3_A4); // Fixed register
                         7: write_i2c(CHIP_ADDR, 16'h_E0_D0); // Fixed register
                         8: write_i2c(CHIP_ADDR, 16'h_F9_00); // Fixed register	
                         9: write_i2c(CHIP_ADDR, 16'h_15_00); // [7:4]: I2S Sampling Frequency = 0b0000, 44.1kHz
                                                              // [3:0]: Video Input ID = 0b0000, 24 bit RGB 4:4:4 (separate syncs)
                        10: write_i2c(CHIP_ADDR, { 8'h_17, hdmiVideoConfig.adv_reg_17 });
                                                            // [7]:   fixed = 0b0
                                                            // [6]:   vsync polarity = 0b0, sync polarity pass through (sync adjust is off in 0x41)
                                                            // [5]:   hsync polarity = 0b0, sync polarity pass through
                                                            // [4:3]: reserved = 0b00
                                                            // [2]:   4:2:2 to 4:4:4 interpolation style = 0b0, use zero order interpolation
                                                            // [1]:   input video aspect ratio = 0b0, 4:3; 0b10 for 16:9
                                                            // [0]:   DE generator = 0b0, disabled
                        11: write_i2c(CHIP_ADDR, 16'h_16_30 | `OUTPUT_FMT);
                                                            // [7]:   output format = 0b0, 4:4:4, (4:2:2, if OUTPUT_4_2_2 is set)
                                                            // [6]:   reserved = 0b0
                                                            // [5:4]: color depth = 0b11, 8bit
                                                            // [3:2]: input style = 0b0, not valid
                                                            // [1]:   ddr input edge = 0b0, falling edge
                                                            // [0]:   output colorspace for blackimage = 0b0, RGB (YCbCr, if OUTPUT_4_2_2 is set)
`ifdef OUTPUT_4_2_2
                        12: write_i2c(CHIP_ADDR, 16'h_56_A8); // Colorimetry ITU709, aspect ratio 16:9, active format aspect ratio same as aspect ratio
                        13: write_i2c(CHIP_ADDR, 16'h_55_30); // YCbCr 4:2:2 in AVI InfoFrame, active format information valid
                        14: cmd_counter <= CSC;
`else
                        12: write_i2c(CHIP_ADDR, 16'h_55_00); // RGB in AVI InfoFrame
                        13: write_i2c(CHIP_ADDR, 16'h_18_46); // [7]:   CSC enable = 0b0, disabled
                                                              // [6:5]: default = 0b10
                                                              // [4:0]: default = 0b00110
                        14: cmd_counter <= INIT_NEXT;
`endif
                        INIT_NEXT: write_i2c(CHIP_ADDR, 16'h_AF_06); // [7]:   HDCP enable = 0b0, disabled
                                                              // [6:5]: fixed = 0b00
                                                              // [4]:   frame encryption = 0b0, current frame not encrypted
                                                              // [3:2]: fixed = 0b01
                                                              // [1]:   HDMI/DVI mode select = 0b1, HDMI mode
                                                              // [0]:   fixed = 0b0
                        INIT_NEXT+1: write_i2c(CHIP_ADDR, 16'h_BA_60); // [7:5]: clock delay, 0b011 no delay
                                                              // [4]:   hdcp eprom, 0b0 external
                                                              // [3]:   fixed, 0b0
                                                              // [2]:   display aksv, 0b0 don't show
                                                              // [1]:   Ri two point check, 0b0 hdcp Ri standard
                        INIT_NEXT+2: write_i2c(CHIP_ADDR, 16'h_0A_00); // [7]:   CTS selet = 0b0, automatic
                                                              // [6:4]: audio select = 0b000, I2S
                                                              // [3:2]: audio mode = 0b00, default (HBR not used)
                                                              // [1:0]: MCLK Ratio = 0b00, 128xfs
                        INIT_NEXT+3: write_i2c(CHIP_ADDR, 16'h_01_00); // [3:0] \
                        INIT_NEXT+4: write_i2c(CHIP_ADDR, 16'h_02_18); // [7:0]  |--> [19:0]: audio clock regeneration N value, 44.1kHz@automatic CTS = 0x1880 (6272)
                        INIT_NEXT+5: write_i2c(CHIP_ADDR, 16'h_03_80); // [7:0] /
                        INIT_NEXT+6: write_i2c(CHIP_ADDR, 16'h_0B_0E); // [7]:   SPDIF enable = 0b0, disable
                                                              // [6]:   audio clock polarity = 0b0, rising edge
                                                              // [5]:   MCLK enable = 0b0, MCLK internally generated
                                                              // [4:1]: fixed = 0b0111
                        INIT_NEXT+7: write_i2c(CHIP_ADDR, 16'h_0C_05); // [7]:   audio sampling frequency select = 0b0, use sampling frequency from I2S stream
                                                              // [6]:   channel status override = 0b0, use channel status bits from I2S stream
                                                              // [5]:   I2S3 enable = 0b0, disabled
                                                              // [4]:   I2S2 enable = 0b0, disabled
                                                              // [3]:   I2S1 enable = 0b0, disabled
                                                              // [2]:   I2S0 enable = 0b1, enabled
                                                              // [1:0]: I2S format = 0b01, right justified mode
                        INIT_NEXT+8: write_i2c(CHIP_ADDR, 16'h_0D_10); // [4:0]: I2S bit width = 0b10000, 16bit
                        INIT_NEXT+9: write_i2c(CHIP_ADDR, 16'h_94_C0); // [7]:   HPD interrupt = 0b1, enabled
                                                              // [6]:   monitor sense interrupt = 0b1, enabled
                                                              // [5]:   vsync interrupt = 0b0, disabled
                                                              // [4]:   audio fifo full interrupt = 0b0, disabled
                                                              // [3]:   fixed = 0b0
                                                              // [2]:   EDID ready interrupt = 0b0, disabled
                                                              // [1]:   HDCP authenticated interrupt = 0b0, disabled
                                                              // [0]:   fixed = 0b0
                        INIT_NEXT+10: write_i2c(CHIP_ADDR, 16'h_96_C0); // [7]:   HPD interrupt = 0b1, interrupt detected
                                                              // [6]:   monitor sense interrupt = 0b1, interrupt detected
                                                              // [5]:   vsync interrupt = 0b0, no interrupt detected
                                                              // [4]:   audio fifo full interrupt = 0b0, no interrupt detected
                                                              // [3]:   fixed = 0b0
                                                              // [2]:   EDID ready interrupt = 0b0, no interrupt detected
                                                              // [1]:   HDCP authenticated interrupt = 0b0, no interrupt detected
                                                              // [0]:   fixed = 0b0
                                                              // -> clears interrupt state
                        INIT_NEXT+11: write_i2c(CHIP_ADDR, { 8'h_3B, hdmiVideoConfig.adv_reg_3b });
                                                            // [7]:   fixed = 0b1
                                                            // [6:5]: PR Mode = 0b10, manual mode
                                                            // [4:3]: PR PLL Manual = 0b01, x2
                                                            // [2:1]: PR Value Manual = 0b00, x1 to rx
                                                            // [0]:   fixed = 0b0
                        INIT_NEXT+12: write_i2c(CHIP_ADDR, { 8'h_3C, hdmiVideoConfig.adv_reg_3c });
                                                            // [5:0]: VIC Manual = 010000, VIC#16: 1080p-60, 16:9
                                                            //                     000000, VIC#0: VIC Unavailable
                        INIT_NEXT+13: cmd_counter <= PLL_CHECK_1;
                        PLL_CHECK_1: read_i2c(CHIP_ADDR, 8'h_9E);
                        (PLL_CHECK_1+1): begin
                            if (i2c_data[4]) begin
                                cmd_counter <= GOTO_READY;
                            end else begin
                                debugData.pll_errors <= debugData.pll_errors + 1'b1;
                                cmd_counter <= INIT_START;
                            end
                        end

                        CHIP_REVISION: read_i2c(CHIP_ADDR, 8'h_00);
                        (CHIP_REVISION+1): begin
                            debugData.chip_revision <= i2c_data;
                            cmd_counter <= ID_CHECK_H;
                        end

                        ID_CHECK_H: read_i2c(CHIP_ADDR, 8'h_F5);
                        (ID_CHECK_H+1): begin
                            debugData.id_check_high <= i2c_data;
                            cmd_counter <= ID_CHECK_L;
                        end

                        ID_CHECK_L: read_i2c(CHIP_ADDR, 8'h_F6);
                        (ID_CHECK_L+1): begin
                            debugData.id_check_low <= i2c_data;
                            cmd_counter <= PLL_CHECK_2;
                        end

                        PLL_CHECK_2: read_i2c(CHIP_ADDR, 8'h_9E);
                        (PLL_CHECK_2+1): begin
                            debugData.pll_status <= i2c_data;
                            cmd_counter <= CTS_CHECK_1;
                             if (!i2c_data[4]) begin
                                debugData.pll_errors <= debugData.pll_errors + 1'b1;
                             end
                        end

                        CTS_CHECK_1: read_i2c(CHIP_ADDR, 8'h_04);
                        (CTS_CHECK_1+1): begin
                            do_cts(CTS_CHECK_2, debugData.cts1_status, debugData.max_cts1_status, debugData.max_cts1_status, debugData.summary_cts1_status, debugData.summary_cts1_status);
                        end

                        CTS_CHECK_2: read_i2c(CHIP_ADDR, 8'h_05);
                        (CTS_CHECK_2+1): begin
                            do_cts(CTS_CHECK_3, debugData.cts2_status, debugData.max_cts2_status, debugData.max_cts2_status, debugData.summary_cts2_status, debugData.summary_cts2_status);
                        end

                        CTS_CHECK_3: read_i2c(CHIP_ADDR, 8'h_06);
                        (CTS_CHECK_3+1): begin
                            do_cts(VIC_CHECK_1, debugData.cts3_status, debugData.max_cts3_status, debugData.max_cts3_status, debugData.summary_cts3_status, debugData.summary_cts3_status);
                        end

                        CTS_CHECK_3_2: read_i2c(CHIP_ADDR, 8'h_06);
                        (CTS_CHECK_3_2+1): begin
                            do_cts(GOTO_READY, debugData.cts3_status, debugData.max_cts3_status, debugData.max_cts3_status, debugData.summary_cts3_status, debugData.summary_cts3_status);
                        end

                        VIC_CHECK_1: read_i2c(CHIP_ADDR, 8'h_3E);
                        (VIC_CHECK_1+1): begin
                            debugData.vic_detected <= i2c_data;
                            cmd_counter <= VIC_CHECK_2;
                        end

                        VIC_CHECK_2: read_i2c(CHIP_ADDR, 8'h_3D);
                        (VIC_CHECK_2+1): begin
                            debugData.vic_to_rx <= i2c_data;
                            cmd_counter <= MISC_CHECK;
                        end

                        MISC_CHECK: read_i2c(CHIP_ADDR, 8'h_42);
                        (MISC_CHECK+1): begin
                            debugData.misc_data <= i2c_data;
                            cmd_counter <= GOTO_READY;
                        end
`ifdef OUTPUT_4_2_2
                        // ADV Programmer's Handbook, page 54
                        // Table 37 RGB (Full Range) to HDTV YCbCr (Limited Range)
                        CSC: write_i2c(CHIP_ADDR, 16'h_18_86);
                        CSC+1: write_i2c(CHIP_ADDR, 16'h_19_FF);
                        CSC+2: write_i2c(CHIP_ADDR, 16'h_1A_19);
                        CSC+3: write_i2c(CHIP_ADDR, 16'h_1B_A6);
                        CSC+4: write_i2c(CHIP_ADDR, 16'h_1C_1F);
                        CSC+5: write_i2c(CHIP_ADDR, 16'h_1D_5B);
                        CSC+6: write_i2c(CHIP_ADDR, 16'h_1E_08);
                        CSC+7: write_i2c(CHIP_ADDR, 16'h_1F_00);
                        CSC+8: write_i2c(CHIP_ADDR, 16'h_20_02);
                        CSC+9: write_i2c(CHIP_ADDR, 16'h_21_E9);
                        CSC+10: write_i2c(CHIP_ADDR, 16'h_22_09);
                        CSC+11: write_i2c(CHIP_ADDR, 16'h_23_CB);
                        CSC+12: write_i2c(CHIP_ADDR, 16'h_24_00);
                        CSC+13: write_i2c(CHIP_ADDR, 16'h_25_FD);
                        CSC+14: write_i2c(CHIP_ADDR, 16'h_26_01);
                        CSC+15: write_i2c(CHIP_ADDR, 16'h_27_00);
                        CSC+16: write_i2c(CHIP_ADDR, 16'h_28_1E);
                        CSC+17: write_i2c(CHIP_ADDR, 16'h_29_66);
                        CSC+18: write_i2c(CHIP_ADDR, 16'h_2A_1A);
                        CSC+19: write_i2c(CHIP_ADDR, 16'h_2B_9B);
                        CSC+20: write_i2c(CHIP_ADDR, 16'h_2C_06);
                        CSC+21: write_i2c(CHIP_ADDR, 16'h_2D_FF);
                        CSC+22: write_i2c(CHIP_ADDR, 16'h_2E_08);
                        CSC+23: write_i2c(CHIP_ADDR, 16'h_2F_00);
                        CSC+24: cmd_counter <= INIT_NEXT;
`endif

                        default: begin
                            cmd_counter <= INIT_START;
                            state <= s_idle;
                            ready <= 1;
                        end
                    endcase
                end
            end
            
            s_wait: begin
                state <= s_wait_2;
            end
            
            s_wait_2: begin
                i2c_enable <= 1'b0;
                
                if (i2c_done) begin
                    if (~i2c_ack_error) begin
                        cmd_counter <= cmd_counter + 1'b1;
                    end 
                    state <= s_start;
                end
            end

            s_idle: begin
                if (~hdmi_int) begin
                    state <= s_start;
                    ready <= 0;
                end else if (~DE_reg && DE) begin
                    cmd_counter <= CTS_CHECK_3_2;
                    state <= s_start;
                end else if (~VSYNC_reg && VSYNC) begin
                    cmd_counter <= CHIP_REVISION;
                    state <= s_start;
                    debugData.frame_counter <= debugData.frame_counter + 1'b1;
                end

                if (debugData.frame_counter == 1023) begin
                    debugData.max_cts1_status <= 0;
                    debugData.max_cts2_status <= 0;
                    debugData.max_cts3_status <= 0;
                    debugData.summary_cts1_status <= 0;
                    debugData.summary_cts2_status <= 0;
                    debugData.summary_cts3_status <= 0;
                    debugData.summary_summary_cts3_status <= debugData.summary_cts3_status;
                    debugData.frame_counter <= 0;
                    debugData.test <= debugData.test + 1'b1;
                end
            end
            
        endcase
    end
end

task do_cts;
    input [5:0] next_cmd;
    
    output [7:0] cts_out;

    input [7:0] max_cts_in;
    output [7:0] max_cts_out;

    input [7:0] offset_cts_in;
    output [7:0] offset_cts_out;

    begin
        cmd_counter <= next_cmd;
        cts_out <= i2c_data;
        if (i2c_data >= max_cts_in) begin
            max_cts_out <= i2c_data;
        end else begin
            max_cts_out <= max_cts_in;
        end
        calculate_offset(i2c_data, max_cts_in, offset_cts_in, offset_cts_out);
    end
endtask

task calculate_offset;
    input [7:0] cur;
    input [7:0] max;
    input [7:0] offset_cts_in;
    output [7:0] offset_cts_out;

    begin
        if (max > cur && (max - cur) > offset_cts_in) begin
            offset_cts_out <= max - cur;
        end else begin
            offset_cts_out <= offset_cts_in;
        end
    end
endtask

task write_i2c;
    input [6:0] t_chip_addr;
    input [15:0] t_data;

    begin
        i2c_chip_addr <= t_chip_addr;
        i2c_reg_addr  <= t_data[15:8];
        i2c_value     <= t_data[7:0];
        i2c_enable    <= 1'b1;
        i2c_is_read   <= 1'b0;
        state         <= s_wait;
    end
endtask

task read_i2c;
    input [6:0] t_chip_addr;
    input [7:0] t_addr;

    begin
        i2c_chip_addr <= t_chip_addr;
        i2c_reg_addr  <= t_addr;
        i2c_enable    <= 1'b1;
        i2c_is_read   <= 1'b1;
        state         <= s_wait;
    end
endtask

endmodule
