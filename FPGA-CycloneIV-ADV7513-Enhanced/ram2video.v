`include "config.inc"

module ram2video(
    input [23:0] rddata,
    input starttrigger,

    input clock,
    input reset,
    
    input line_doubler,
    input add_line,

    output [11:0] rdaddr,
    
    output [7:0] red,
    output [7:0] green,
    output [7:0] blue,
    
    output hsync,
    output vsync,
    
    output DrawArea,
    output videoClock
);

    reg [10:0] vlines; // vertical lines per frame
    
    reg [7:0] red_reg;
    reg [7:0] green_reg;
    reg [7:0] blue_reg;

    reg hsync_reg_q = 1'b1;
    reg vsync_reg_q = 1'b1;

    reg [11:0] counterX_reg;
    reg [11:0] counterX_reg_q;
    reg [11:0] counterX_reg_q_q;
    
    reg [11:0] counterY_reg;
    reg [11:0] counterY_reg_q;
    reg [11:0] counterY_reg_q_q;
    
    reg trigger = 1'b0;
    reg line_doubler_reg = 1'b0;
    reg add_line_reg = 1'b0;
    
    initial begin
        counterX_reg <= 0;
        counterY_reg <= 0;
        hsync_reg_q <= ~`HORIZONTAL_SYNC_ON_POLARITY;
        vsync_reg_q <= ~`VERTICAL_SYNC_ON_POLARITY;
    end
    
    task doReset;
        input triggered;
    
        begin
            trigger <= triggered;
            counterX_reg <= 0;
            counterY_reg <= 0;
            hsync_reg_q <= ~`HORIZONTAL_SYNC_ON_POLARITY;
            vsync_reg_q <= ~`VERTICAL_SYNC_ON_POLARITY;
        end
    endtask	

    always @(*) begin
        if (add_line) begin
            vlines = `VERTICAL_LINES_INTERLACED;
        end else begin
            vlines = `VERTICAL_LINES;
        end
    end
    
    always @(posedge clock) begin
        if (~reset) begin
            doReset(1'b0);
        end else begin
            if (!trigger && starttrigger) begin
                doReset(1'b1);
            end
            
            line_doubler_reg <= line_doubler;
            if (line_doubler != line_doubler_reg) begin
                doReset(1'b0);
            end

            add_line_reg <= add_line;
            if (add_line != add_line_reg) begin
                doReset(1'b0);
            end
        
            if (trigger) begin
                
                if (counterX_reg < `HORIZONTAL_PIXELS_PER_LINE - 1) begin
                    counterX_reg <= counterX_reg + 1'b1;
                end else begin
                    counterX_reg <= 0;
                
                    if (counterY_reg < vlines - 1) begin
                        counterY_reg <= counterY_reg + 1'b1;
                    end else begin
                        counterY_reg <= 0;
                    end
                end

                if (counterX_reg_q >= `HORIZONTAL_SYNC_START && counterX_reg_q < `HORIZONTAL_SYNC_START + `HORIZONTAL_SYNC_WIDTH) begin
                    hsync_reg_q <= `HORIZONTAL_SYNC_ON_POLARITY;
                end else begin
                    hsync_reg_q <= ~`HORIZONTAL_SYNC_ON_POLARITY;
                end

                if (counterY_reg_q >= `VERTICAL_SYNC_START && counterY_reg_q < `VERTICAL_SYNC_START + `VERTICAL_SYNC_WIDTH + 1) begin // + 1: synchronize last vsync period with hsync negative edge
                    if ((counterY_reg_q == `VERTICAL_SYNC_START && counterX_reg_q < `HORIZONTAL_SYNC_START) 
                     || (counterY_reg_q == `VERTICAL_SYNC_START + `VERTICAL_SYNC_WIDTH && counterX_reg_q >= `HORIZONTAL_SYNC_START)) begin
                        vsync_reg_q <= `VERTICAL_SYNC_ON_POLARITY;
                    end else begin
                        vsync_reg_q <= ~`VERTICAL_SYNC_ON_POLARITY;
                    end
                end else begin
                    vsync_reg_q <= `VERTICAL_SYNC_ON_POLARITY;
                end
                
                counterX_reg_q <= counterX_reg;
                counterY_reg_q <= counterY_reg;
                counterX_reg_q_q <= counterX_reg_q;
                counterY_reg_q_q <= counterY_reg_q;
            end
        end
    end
    
    assign rdaddr = (
        counterX_reg >= `HORIZONTAL_START_OFFSET 
        ? (
            line_doubler_reg 
            ? { counterY_reg[2:1], counterX_reg[9:0] - (`HORIZONTAL_START_OFFSET / `PIXEL_FACTOR) } 
            : { 1'b0, (`PIXEL_FACTOR == 2 ? counterX_reg[11:1] : counterX_reg[10:0]) - (`HORIZONTAL_START_OFFSET / `PIXEL_FACTOR) }
        ) 
        : 12'd1023
    );
    assign red = rddata[23:16];
    assign green = rddata[15:8];
    assign blue = rddata[7:0];
    assign hsync = hsync_reg_q;
    assign vsync = vsync_reg_q;
    assign DrawArea = counterX_reg_q_q >= 0 && counterX_reg_q_q < `HORIZONTAL_PIXELS_VISIBLE && counterY_reg_q_q >= 0 && counterY_reg_q_q < `VERTICAL_LINES_VISIBLE;
    assign videoClock = clock; 

endmodule