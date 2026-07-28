# ==============================================================================
# Project:       0x00-uart
# File:          Makefile
# Target Device: CH32V003 (QingKe RV32EC)
# Description:   Cross-platform build for the 0x00-uart firmware.
#                Assembles all .s sources, links with link.ld, and produces a
#                raw binary for flashing via SWIO (wlink).
# ==============================================================================

# ------------------------------------------------------------------------------
# Usage
#   make              build build/0x00-uart.bin
#   make flash        build + flash the badge (SWIO on PD1 in debug mode)
#   make debug        start OpenOCD debug server (port 3333)
#   make gdb          connect GDB to a running OpenOCD session
#   make protect      enable flash read protection (debugger reads blocked)
#   make unprotect    disable read protection (mass-erases flash first)
#   make clean        remove build artifacts
#
# Override the toolchain prefix if yours differs, e.g.  make PREFIX=riscv-none-elf-
# ------------------------------------------------------------------------------

# ==============================================================================
# SECTION:     Toolchain detection  (Windows vs Linux/macOS)
# ==============================================================================
UNAME_S := $(shell uname -s 2>/dev/null || echo Windows_NT)

ifeq ($(UNAME_S),Windows_NT)
  # --------------------------------------------------------------------------
  # Pure Windows cmd.exe — standalone riscv-wch-elf toolchain
  # --------------------------------------------------------------------------
  SHELL   := cmd.exe
  PREFIX  ?= riscv-wch-elf-
  AS      := $(PREFIX)as.exe
  LD      := $(PREFIX)ld.exe
  OBJCOPY := $(PREFIX)objcopy.exe
  OBJDUMP := $(PREFIX)objdump.exe
  MKBUILD  = if not exist build mkdir build
  RMBUILD  = if exist build rmdir /s /q build
  FLASHCMD = wlink --chip CH32V003 flash $(TARGET).bin
  PROTECTCMD  = @echo "Use wlink for read protection on Windows"
  UNPROTECTCMD = @echo "Use wlink to disable read protection on Windows"
  SETUP_CMD = @echo "Please use MSYS2 to run make setup on Windows. Run: winget install MSYS2.MSYS2"
  WAVE_PRE =
else ifneq (,$(findstring MSYS,$(UNAME_S))$(findstring MINGW,$(UNAME_S))$(findstring CYGWIN,$(UNAME_S)))
  # --------------------------------------------------------------------------
  # Windows MSYS2 / MinGW64
  # --------------------------------------------------------------------------
  # Find xPack GCC and OpenOCD on Windows directly
  XPACK_GCC_DIR := $(firstword $(wildcard /c/Users/*/AppData/Roaming/xPacks/@xpack-dev-tools/riscv-none-elf-gcc/*/.content/bin))
  ifneq ($(XPACK_GCC_DIR),)
    PREFIX  ?= $(XPACK_GCC_DIR)/riscv-none-elf-
  else
    PREFIX  ?= riscv-none-elf-
  endif
  XPACK_OCD_DIR := $(firstword $(wildcard /c/Users/*/AppData/Roaming/xPacks/@xpack-dev-tools/openocd/*/.content/bin))
  ifneq ($(XPACK_OCD_DIR),)
    OPENOCD := $(XPACK_OCD_DIR)/openocd
  endif
  AS      := $(PREFIX)as
  LD      := $(PREFIX)ld
  OBJCOPY := $(PREFIX)objcopy
  OBJDUMP := $(PREFIX)objdump
  MKBUILD  = mkdir -p build
  RMBUILD  = rm -rf build
  FLASHCMD = wlink --chip CH32V003 flash $(TARGET).bin
  PROTECTCMD  = @echo "Use wlink for read protection"
  UNPROTECTCMD = @echo "Use wlink to disable read protection"
  # GTKWave segfaults on MSYS2 ("cannot register existing type 'GdkPixbuf'")
  # when the gdk-pixbuf loader cache is stale or mismatched. Refresh it before
  # launching GTKWave. Requires a full `pacman -Syu` + rebuild if MSYS2 itself
  # has mismatched gtk3/gdk-pixbuf packages.
  WAVE_PRE = gdk-pixbuf-query-loaders --update-cache 2>/dev/null || true
  SETUP_CMD = pacman -Syu --noconfirm && \
              pacman -S --noconfirm mingw-w64-x86_64-verilator mingw-w64-x86_64-gtk3 mingw-w64-x86_64-toolchain autoconf automake libtool gperf pkg-config mingw-w64-x86_64-nodejs mingw-w64-x86_64-python-pip mingw-w64-x86_64-ncurses git mingw-w64-x86_64-zlib mingw-w64-x86_64-bzip2 mingw-w64-x86_64-xz && \
              rm -f /usr/local/bin/gtkwave* && \
              rm -rf /tmp/gtkwave-custom && git clone -b udp-send https://github.com/buncram/gtkwave.git /tmp/gtkwave-custom && \
              sed -i.bak '/extern int getopt ();/d' /tmp/gtkwave-custom/gtkwave3-gtk3/src/gnu-getopt.h && \
              cd /tmp/gtkwave-custom/gtkwave3-gtk3 && python3 $(CURDIR)/sim/patch_gtkwave.py && \
              ./autogen.sh && ./configure --prefix=/mingw64 --enable-gtk3 --disable-tcl --disable-xz CFLAGS="-std=gnu17 -Wno-incompatible-pointer-types -Wno-int-conversion -Wno-implicit-function-declaration" LIBS="-lws2_32" && make -j$$(nproc) && make install && \
              npm install --location=global xpm@latest && \
              xpm install @xpack-dev-tools/riscv-none-elf-gcc@latest --global && \
              xpm install @xpack-dev-tools/openocd@latest --global
else
  # --------------------------------------------------------------------------
  # Linux / macOS — riscv64-unknown-elf-* + wlink flasher
  # --------------------------------------------------------------------------
  PREFIX  ?= riscv64-unknown-elf-
  ifeq ($(UNAME_S),Linux)
    # Linux setup installs the xPack riscv-none-elf-gcc toolchain; its
    # binaries are riscv-none-elf-* and live under ~/.local/xPacks.
    XPACK_GCC_DIR := $(firstword $(wildcard $(HOME)/.local/xPacks/@xpack-dev-tools/riscv-none-elf-gcc/*/.content/bin) $(wildcard $(HOME)/.xpack/@xpack-dev-tools/riscv-none-elf-gcc/*/.content/bin))
    ifneq ($(XPACK_GCC_DIR),)
      PREFIX = $(XPACK_GCC_DIR)/riscv-none-elf-
    endif
  endif
  AS      := $(PREFIX)as
  LD      := $(PREFIX)ld
  OBJCOPY := $(PREFIX)objcopy
  OBJDUMP := $(PREFIX)objdump
  MKBUILD  = mkdir -p build
  RMBUILD  = rm -rf build
  FLASHCMD = wlink --chip CH32V003 flash $(TARGET).bin
  PROTECTCMD  = @echo "Use wlink for read protection"
  UNPROTECTCMD = @echo "Use wlink to disable read protection"
  WAVE_PRE =
  ifeq ($(UNAME_S),Linux)
    SETUP_CMD = sudo apt-get update && sudo apt-get install -y verilator python3 python3-pip git build-essential libgtk-3-dev pkg-config autoconf automake libtool gperf texinfo libgmp-dev libmpfr-dev libmpc-dev libusb-1.0-0-dev nodejs npm && \
                sudo npm install --location=global xpm@latest && \
                xpm install @xpack-dev-tools/riscv-none-elf-gcc@latest --global && \
                xpm install @xpack-dev-tools/openocd@latest --global && \
                rm -rf /tmp/gtkwave-custom && git clone -b udp-send https://github.com/buncram/gtkwave.git /tmp/gtkwave-custom && \
                sed -i.bak '/extern int getopt ();/d' /tmp/gtkwave-custom/gtkwave3-gtk3/src/gnu-getopt.h && \
                cd /tmp/gtkwave-custom/gtkwave3-gtk3 && ./autogen.sh && ./configure --prefix=/usr/local --enable-gtk3 --disable-tcl --disable-xz CFLAGS="-std=gnu17 -Wno-incompatible-pointer-types -Wno-int-conversion -Wno-implicit-function-declaration" && make -j$$(nproc) && sudo make install
  endif
  ifeq ($(UNAME_S),Darwin)
    BREW_PREFIX := $(shell brew --prefix 2>/dev/null || echo /usr/local)
    UNAME_M := $(shell uname -m)
    MAC_ARCH_FLAGS :=
    ifeq ($(UNAME_M),arm64)
      ifeq ($(BREW_PREFIX),/usr/local)
        MAC_ARCH_FLAGS := -arch x86_64
      endif
    endif
    SETUP_CMD = brew install verilator python3 git autoconf automake libtool gperf gtk-mac-integration gtk+3 pkg-config libusb capstone && \
                brew tap riscv-software-src/riscv && (brew trust riscv-software-src/riscv || true) && brew install riscv-tools && \
                cargo install wlink && \
                rm -rf /tmp/riscv-openocd-wch && git clone --depth 1 https://github.com/Seneral/riscv-openocd-wch.git /tmp/riscv-openocd-wch && \
                cd /tmp/riscv-openocd-wch && git submodule update --init && autoreconf -f -i && git submodule foreach git reset --hard && ./configure --prefix=/usr/local --enable-wlinke --disable-ch347 --disable-werror CFLAGS="$(MAC_ARCH_FLAGS) -std=gnu17 -Wno-incompatible-pointer-types -Wno-int-conversion -Wno-implicit-function-declaration" CXXFLAGS="$(MAC_ARCH_FLAGS)" LDFLAGS="$(MAC_ARCH_FLAGS)" && make -j$$(sysctl -n hw.ncpu) && sudo make install && \
                rm -rf /tmp/gtkwave-custom && git clone -b udp-send https://github.com/buncram/gtkwave.git /tmp/gtkwave-custom && \
                sed -i '' '/extern int getopt ();/d' /tmp/gtkwave-custom/gtkwave3-gtk3/src/gnu-getopt.h && \
                cd /tmp/gtkwave-custom/gtkwave3-gtk3 && ./autogen.sh && ./configure --prefix=/usr/local --enable-gtk3 --disable-tcl --disable-xz CFLAGS="$(MAC_ARCH_FLAGS) -std=gnu17 -Wno-incompatible-pointer-types -Wno-int-conversion -Wno-implicit-function-declaration" CXXFLAGS="$(MAC_ARCH_FLAGS)" LDFLAGS="$(MAC_ARCH_FLAGS)" && make -j$$(sysctl -n hw.ncpu) && make install
  endif
endif

# ==============================================================================
# SECTION:     Tool paths (debug)
# ==============================================================================
OPENOCD ?= wch-openocd
GDB     ?= riscv64-elf-gdb

# ==============================================================================
# SECTION:     Assembler and linker flags
# ==============================================================================
ASFLAGS  := -march=rv32ec_zicsr -mabi=ilp32e -g -Isrc
ifneq ($(filter sim,$(MAKECMDGOALS)),)
ASFLAGS  += --defsym SIMULATION=1
endif
LDFLAGS = -nostdlib -static -m elf32lriscv -T link.ld

# ==============================================================================
# SECTION:     Sources and objects
# ==============================================================================
SOURCES = src/start.s src/regs.s src/uart.s src/main.s
OBJS    = $(patsubst src/%.s,build/%.o,$(SOURCES))
TARGET = build/0x00-uart

# ==============================================================================
# SECTION:     Build rules
# ==============================================================================
all: $(TARGET).bin $(TARGET).lst $(TARGET).hex
build/%.o: src/%.s src/regs.s Makefile
	$(MKBUILD)
	"$(AS)" $(ASFLAGS) -o $@ $<
$(TARGET).elf: $(OBJS)
	"$(LD)" $(LDFLAGS) -o $@ $(OBJS)
$(TARGET).bin: $(TARGET).elf
	"$(OBJCOPY)" -O binary $< $@
$(TARGET).lst: $(TARGET).elf
	"$(OBJDUMP)" -d $< > $@
$(TARGET).hex: $(TARGET).elf
	"$(OBJCOPY)" -O verilog --verilog-data-width=4 $< $@

# ==============================================================================
# SECTION:     Flash, debug, and clean targets
# ==============================================================================
flash: $(TARGET).bin
	$(FLASHCMD)
debug: $(TARGET).elf
	pkill -f openocd 2>/dev/null || true
	$(OPENOCD) -f openocd.cfg
gdb: $(TARGET).elf
	$(GDB) -ex "target extended-remote :3333" -ex "monitor reset halt" -ex "load" $<
protect:
	$(PROTECTCMD)
unprotect:
	$(UNPROTECTCMD)
sim: $(TARGET).hex
	verilator -Wno-fatal -CFLAGS "-O2" --cc --exe --build --trace --top-module tb sim/picorv32.v sim/tb.v sim/sim_main.cpp -Mdir build/obj_dir
	./build/obj_dir/Vtb
wave: $(TARGET).lst
ifeq ($(UNAME_S),Darwin)
	osascript -e 'tell application "Terminal" to do script "cd $(PWD) && make codezoom"'
else ifeq ($(UNAME_S),Linux)
	x-terminal-emulator -e sh -c "make codezoom" &
else ifeq ($(UNAME_S),Windows_NT)
	start cmd.exe /c "make codezoom"
else
	# MSYS2 / MINGW64 / Cygwin: launch codezoom in a new mintty window so it
	# inherits the MSYS2 environment. A plain cmd.exe cannot find make/python3
	# because they live under /usr/bin and /mingw64/bin, not on the Windows PATH.
	mintty -e make codezoom &
	$(WAVE_PRE)
endif
	gtkwave -r sim/gtkwaverc -u 127.0.0.1:6502 build/trace.vcd sim/gtkwave_setup.gtkw
codezoom: $(TARGET).lst
	python3 sim/codezoom.py --file $(TARGET).lst
setup:
	$(SETUP_CMD)
clean:
	$(RMBUILD)
.PHONY: all flash debug gdb protect unprotect sim wave codezoom setup clean
