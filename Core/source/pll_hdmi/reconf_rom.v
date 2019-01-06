module reconf_rom (
    input clock,
    input [7:0] address,
    input read_ena,
    input [7:0] data,
    input pll_reconf_busy,

    output q,
    output reconfig,
    output reg trigger_read
);

    reg _read_ena = 0;
    reg q_reg;
    reg q_reg_2;
    reg doReconfig;
    reg doReconfig_2;
    reg doReconfig_3;

    reg [7:0] data_req = 8'h_00;

    assign q = q_reg_2;
    assign reconfig = doReconfig_3;

    always @(posedge clock) begin
        _read_ena <= read_ena;

        if (_read_ena && ~read_ena) begin
            doReconfig <= 1;
        end else begin
            doReconfig <= 0;
        end

        if (~pll_reconf_busy && data != data_req) begin
            data_req <= data;
            trigger_read <= 1'b1;
        end else begin
            trigger_read <= 1'b0;
        end

        // RECONF
        case (data_req[6:0])
            7'h00: begin `include "config/1080p.v" end
            7'h01: begin `include "config/960p.v" end
            7'h02: begin `include "config/480p.v" end
            7'h03: begin `include "config/VGA.v" end
            7'h10: begin `include "config/240p_1080p.v" end
            7'h11: begin `include "config/960p.v" end
            7'h12: begin `include "config/480p.v" end
            7'h13: begin `include "config/VGA.v" end
            default: begin `include "config/480p.v" end
        endcase

        // delay output, to match ROM based timing
        q_reg_2 <= q_reg;
        doReconfig_2 <= doReconfig;
        doReconfig_3 <= doReconfig_2;
    end
endmodule
