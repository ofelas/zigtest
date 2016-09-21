ZIG ?= ~/projects/REPOS/zig/build/bin/zig

all: t3dbg t3rel t5dbg t5rel

DEPS = Makefile $(ZIG)

t3dbg: t3main.zig t3.zig $(DEPS)
	$(ZIG) build --verbose --static --export exe --name $(@) $(<) 2>$(@).txt

t3rel: t3main.zig t3.zig $(DEPS)
	$(ZIG) build --release --verbose --static --export exe --name $(@) $(<) 2>$(@).txt

t5dbg: t5.zig $(DEPS)
	$(ZIG) build --verbose --static --export exe --name $(@) $(<) 2>$(@).txt

t5rel: t5.zig $(DEPS)
	$(ZIG) build --release --verbose --static --export exe --name $(@) $(<) 2>$(@).txt

.PHONY:
t3test: t3dbg t3rel
	./t3dbg
	./t3rel

t5test: t5dbg t5rel
	./t5dbg
	./t5rel
