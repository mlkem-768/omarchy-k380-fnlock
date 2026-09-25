CC       ?= cc
CFLAGS   ?= -O2 -Wall -Wextra -Wpedantic
HID_PKG  ?= hidapi-hidraw
TARGET   := build/omarchy-k380-fnlock-engine
SOURCE   := src/omarchy-k380-fnlock.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCE)
	mkdir -p build
	$(CC) $(CFLAGS) $$(pkg-config --cflags $(HID_PKG)) \
		-o $@ $< $$(pkg-config --libs $(HID_PKG))

clean:
	rm -rf build
