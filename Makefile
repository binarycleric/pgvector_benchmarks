CC = clang
CFLAGS = -O2 -Wall -Wextra -march=native -mtune=native -I/usr/include -I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include
LDFLAGS = -lm

all: vector_benchmark

vector_benchmark: vector_benchmark.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

vector_benchmark.s: vector_benchmark.c
	$(CC) $(CFLAGS) -S -o $@ $<
	@echo "Assembly generated in vector_benchmark.s"

# Generate assembly with function names and comments
asm-annotated: vector_benchmark_annotated.s

vector_benchmark_annotated.s: vector_benchmark.c
	$(CC) $(CFLAGS) -S -fverbose-asm -o $@ $<
	@echo "Annotated assembly generated in vector_benchmark_annotated.s"

# Check CPU features and capabilities
cpu-info:
ifeq ($(shell uname), Darwin)
	@echo "=== Apple Silicon CPU Information ==="
	@echo "CPU Brand: $$(sysctl -n machdep.cpu.brand_string)"
	@echo "Architecture: $$(uname -m)"
	@echo "Core Count: $$(sysctl -n machdep.cpu.core_count)"
	@echo "Thread Count: $$(sysctl -n machdep.cpu.thread_count)"
	@echo ""
	@echo "=== CPU Features ==="
	@sysctl machdep.cpu.features 2>/dev/null || echo "Features not available"
	@echo ""
	@echo "=== ARM64 Features ==="
	@sysctl hw.optional.arm64 2>/dev/null || echo "ARM64 features not available"
	@echo ""
	@echo "=== Advanced SIMD (NEON) Support ==="
	@if sysctl hw.optional.neon 2>/dev/null | grep -q ": 1"; then \
		echo "✓ NEON/Advanced SIMD supported"; \
	else \
		echo "✗ NEON/Advanced SIMD not found"; \
	fi
	@if sysctl hw.optional.arm64 2>/dev/null | grep -q ": 1"; then \
		echo "✓ ARM64 architecture confirmed"; \
	else \
		echo "✗ ARM64 architecture not confirmed"; \
	fi
else
	@echo "=== Linux CPU Information ==="
	@echo "CPU Info:"
	@cat /proc/cpuinfo | head -20
	@echo ""
	@echo "=== NEON Support Check ==="
	@if grep -q "neon" /proc/cpuinfo; then \
		echo "✓ NEON support found"; \
	else \
		echo "✗ NEON support not found"; \
	fi
endif

run: vector_benchmark
	./vector_benchmark
	$(MAKE) clean

clean:
	rm -f vector_benchmark vector_benchmark.s vector_benchmark_opt.s vector_benchmark_unopt.s vector_benchmark_annotated.s vector_benchmark_debug.s

.PHONY: all run clean asm asm-annotated asm-debug neon-check neon-check-annotated neon-functions compare-asm objdump-neon cpu-info debug-asm
