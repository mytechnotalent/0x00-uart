`timescale 1ns/1ps

module tb (
    input clk,
    input resetn
);

    wire mem_valid;
    wire mem_instr;
    wire mem_ready;
    wire [31:0] mem_addr;
    wire [31:0] mem_wdata;
    wire [3:0] mem_wstrb;
    reg [31:0] mem_rdata;

    /* verilator lint_off PINMISSING */
    picorv32 #(
        .ENABLE_REGS_16_31(0),
        .COMPRESSED_ISA(1)
    ) cpu (
        .clk(clk),
        .resetn(resetn),
        .mem_valid(mem_valid),
        .mem_instr(mem_instr),
        .mem_ready(mem_ready),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .mem_wstrb(mem_wstrb),
        .mem_rdata(mem_rdata)
    );
    /* verilator lint_on PINMISSING */

    // Memory mapping:
    // FLASH: 0x00000000 - 0x00003FFF (16KB)
    // RAM:   0x20000000 - 0x200007FF (2KB)
    // Peripherals: 0x40000000+
    reg [31:0] flash [0:4095];
    reg [31:0] ram [0:511];

    initial begin
        $readmemh("build/0x00-uart.hex", flash);
    end

    // 1-wait state memory interface
    reg mem_ready_reg;
    assign mem_ready = mem_ready_reg;
    
    always @(posedge clk) begin
        if (!resetn) begin
            mem_ready_reg <= 0;
        end else begin
            mem_ready_reg <= mem_valid && !mem_ready_reg;
        end

        if (mem_valid && !mem_ready_reg) begin
            // writes
            if (|mem_wstrb) begin
                if (mem_addr >= 32'h00000000 && mem_addr < 32'h00004000) begin
                    if (mem_wstrb[0]) flash[mem_addr[13:2]][7:0]   <= mem_wdata[7:0];
                    if (mem_wstrb[1]) flash[mem_addr[13:2]][15:8]  <= mem_wdata[15:8];
                    if (mem_wstrb[2]) flash[mem_addr[13:2]][23:16] <= mem_wdata[23:16];
                    if (mem_wstrb[3]) flash[mem_addr[13:2]][31:24] <= mem_wdata[31:24];
                end else if (mem_addr >= 32'h20000000 && mem_addr < 32'h20000800) begin
                    if (mem_wstrb[0]) ram[mem_addr[10:2]][7:0]   <= mem_wdata[7:0];
                    if (mem_wstrb[1]) ram[mem_addr[10:2]][15:8]  <= mem_wdata[15:8];
                    if (mem_wstrb[2]) ram[mem_addr[10:2]][23:16] <= mem_wdata[23:16];
                    if (mem_wstrb[3]) ram[mem_addr[10:2]][31:24] <= mem_wdata[31:24];
                end else if (mem_addr == 32'h40013804) begin // USART_DATAR
                    // Print characters written to UART
                    $write("%c", mem_wdata[7:0]);
                    $fflush();
                end
            end

            // reads
            if (mem_addr >= 32'h00000000 && mem_addr < 32'h00004000) begin
                mem_rdata <= flash[mem_addr[13:2]];
            end else if (mem_addr >= 32'h20000000 && mem_addr < 32'h20000800) begin
                mem_rdata <= ram[mem_addr[10:2]];
            end else if (mem_addr == 32'h40013800) begin // USART_STATR
                // Return TXE and TC flags so firmware knows it can transmit
                mem_rdata <= 32'h00C0; 
            end else begin
                // Dummy read for other peripherals
                mem_rdata <= 32'h0;
            end
        end
    end

endmodule
