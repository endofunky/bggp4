TARGET ?= bios.rom
NASM ?= nasm

all: $(TARGET)
.PHONY: all

$(TARGET): bios.asm
	$(NASM) -f bin -o $(TARGET) bios.asm

clean:
	rm -f $(TARGET)
.PHONY: clean
