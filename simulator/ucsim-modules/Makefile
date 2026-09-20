# Build the ROB3 ucSim hardware peripherals as LOADABLE plugins (.so).
#
# These are external plugins built against the INSTALLED ucSim SDK (see the
# ucSim tree's sdk/ and `make install`). Nothing here is compiled into
# ucsim_51 anymore; load them at runtime with `loadhw <name>.so`.
#
# Point UCSIM_PREFIX at where ucSim was installed (default /usr/local). For a
# non-installed ucSim source tree, set SDK to that tree's sdk/ dir instead:
#
#   make                                   # uses /usr/local installed SDK
#   make UCSIM_PREFIX=/opt/ucsim           # different install prefix
#   make SDK=/path/to/ucsim/sdk            # in-tree SDK (run its export-headers.sh first)
#
#   make clean

UCSIM_PREFIX ?= /usr/local
SDK          ?= $(UCSIM_PREFIX)/share/ucsim/sdk

include $(SDK)/ucsim-plugin.mk

MODULES = loopback adc teachbox rxd
PLUGINS = $(foreach m,$(MODULES),$(m)/$(m).so)

all: $(PLUGINS)

# Each module: <name>/<name>.so from <name>/<name>.cc (+ its cl.h).
loopback/loopback.so: SRCS = loopback/loopback.cc
adc/adc.so:           SRCS = adc/adc.cc
teachbox/teachbox.so: SRCS = teachbox/teachbox.cc
rxd/rxd.so:           SRCS = rxd/rxd.cc

$(PLUGINS):
	$(CXX) $(CXXFLAGS) $(UCSIM_PLUGIN_INCLUDES) -I$(@D) $(SRCS) -o $@

clean:
	rm -f $(PLUGINS)

.PHONY: all clean
