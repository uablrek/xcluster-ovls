##
## Makefile for tserver. Builds lib and executable
##
## Targets;
##  help - This printout
##  all (default) - Build the lib and the executable
##  test - Build the lib and test programs and run them
##  test_progs - Build the lib and test programs
##  clean - Remove built files
##
## Beside the usual CFLAGS and LDFLAGS some usable variables;
##  O - The output directory. Default /tmp/$USER/tserver
##  X - The executable.  Default $(O)/bin/tserver
##  VERSION - Version. Default current time in semver format
##
## Examples;
##  make clean
##  make -j$(nproc)
##  make -j$(nproc) X=/tmp/tserver
##  make -j$(nproc) O=.       # (you *can*, but don't do that!)
##  make test
##  make clean; make -j$(nproc) static
##  make clean; make -j$(nproc) VERSION=1.0.0-rc.1
##

# Use one Makefile
# https://www.google.se/search?q=recursive+make+harmful

CC := $(TARGET)cc
STRIP := $(TARGET)strip

PROG=tserver
O ?= /tmp/$(USER)/$(PROG)
X ?= $(O)/bin/$(PROG)
LIB ?= $(O)/lib/lib$(PROG).a
VERSION ?= $(shell date +%Y.%m.%d-%H.%M)

DIRS := $(O)/lib $(O)/obj $(O)/bin $(O)/test/lib $(O)/test/cmd
SRC := $(filter-out $(wildcard cmd/*test.c),$(wildcard cmd/*.c))
LIB_SRC := $(filter-out $(wildcard lib/*test.c),$(wildcard lib/*.c))
TEST_SRC := $(wildcard cmd/*test.c lib/*test.c)
OBJ := $(SRC:cmd/%.c=$(O)/obj/%.o)
LIB_OBJ := $(LIB_SRC:%.c=$(O)/%.o)
TEST_PROGS := $(TEST_SRC:%.c=$(O)/test/%)

$(O)/%.o : %.c
	$(CC) -c $(XCFLAGS) $(CFLAGS) -DVERSION=$(VERSION) -Wall -Werror -Ilib $< -o $@
$(O)/obj/%.o : cmd/%.c
	$(CC) -c $(XCFLAGS) $(CFLAGS) -DVERSION=$(VERSION) -Wall -Werror -Ilib $< -o $@

.PHONY: all static
all: $(X)
static: $(X)

# https://stackoverflow.com/questions/47905554/segmentation-fault-appears-when-i-use-shared-memory-only-from-statically-build-p
static: XLDFLAGS := -static -Wl,--whole-archive -lpthread -Wl,--no-whole-archive
static: XCFLAGS := -static

$(X): $(LIB) $(OBJ)
	$(CC) -o $(X) $(OBJ) $(XLDFLAGS) $(LDFLAGS) -pthread -L$(O)/lib  -l$(PROG)
	$(STRIP) $(X)

# https://stackoverflow.com/questions/4440500/depending-on-directories-in-make
$(OBJ): | $(DIRS)
$(LIB): $(LIB_OBJ)
	@rm -f $(LIB)
	ar rcs $(LIB) $(LIB_OBJ)
$(LIB_OBJ): | $(DIRS)

# The trick here is to force the test programs to run using a dummy
# target. Is there a better way?
.PHONY: test test_progs
TESTS := $(TEST_PROGS:$(O)/test/%=test/%)
# Dummy target
test/%: $(O)/test/%
	$<
$(O)/test/% : %.c
	$(CC) $(CFLAGS) -Wall -Ilib $< -o $@ -L$(O)/lib -l$(PROG) 
$(TEST_PROGS): $(LIB)
test_progs: $(TEST_PROGS)
test: $(TEST_PROGS) $(TESTS)


$(DIRS):
	@mkdir -p $(DIRS)

.PHONY: clean
clean:
	rm -f $(X) $(LIB) $(OBJ) $(LIB_OBJ) $(TEST_OBJ) $(TEST_PROGS)

.PHONY: help
help:
	@grep '^##' $(lastword $(MAKEFILE_LIST)) | cut -c3-
