CC = gcc
CFLAGS = -O3 -Wall -Wextra -march=native -mtune=native -I/usr/include -I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include
LDFLAGS = -lm

ifeq ($(shell uname), Darwin)
    # Apple Silicon specific flags
    CFLAGS += -march=armv8.5-a
else ifeq ($(shell uname), Linux)
    # Linux ARM specific flags
    CFLAGS += -mfpu=neon-fp-armv8 -mfma
endif

# Add NEON support
CFLAGS += -D__ARM_NEON

all: vector_benchmark

vector_benchmark: vector_benchmark.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

# Generate assembly output
asm: vector_benchmark.s

vector_benchmark.s: vector_benchmark.c
	$(CC) $(CFLAGS) -S -o $@ $<
	@echo "Assembly generated in vector_benchmark.s"

# Show NEON instructions in the assembly
neon-check: vector_benchmark.s
	@echo "=== NEON Instructions Found ==="
	@grep -E "(vld1|vst1|vmul|vadd|vsub|vfma|vdup|vget|vpadd|vset)" vector_benchmark.s || echo "No NEON instructions found"
	@echo ""
	@echo "=== ARM64 SIMD Instructions Found ==="
	@grep -E "(fmul|fadd|fsub|fmla|dup|mov|uzp|zip)" vector_benchmark.s | grep -E "\.4s|\.2s|\.2d|v[0-9]+" || echo "No ARM64 SIMD instructions found"

# Show assembly for specific functions
neon-functions: vector_benchmark.s
	@echo "=== VectorL2SquaredDistanceNEON Assembly ==="
	@sed -n '/VectorL2SquaredDistanceNEON:/,/^[[:space:]]*\.cfi_endproc/p' vector_benchmark.s
	@echo ""
	@echo "=== VectorInnerProductNEON Assembly ==="
	@sed -n '/VectorInnerProductNEON:/,/^[[:space:]]*\.cfi_endproc/p' vector_benchmark.s
	@echo ""
	@echo "=== VectorCosineSimilarityNEON Assembly ==="
	@sed -n '/VectorCosineSimilarityNEON:/,/^[[:space:]]*\.cfi_endproc/p' vector_benchmark.s

# Compare optimized vs unoptimized assembly
compare-asm: vector_benchmark.c
	@echo "=== Generating optimized assembly ==="
	$(CC) $(CFLAGS) -S -o vector_benchmark_opt.s $<
	@echo "=== Generating unoptimized assembly ==="
	$(CC) -O0 -march=native -D__ARM_NEON -S -o vector_benchmark_unopt.s $<
	@echo ""
	@echo "=== NEON instructions in optimized version ==="
	@grep -c -E "(vld1|vst1|vmul|vadd|vsub|vfma|vdup|vget|vpadd)" vector_benchmark_opt.s || echo "0"
	@echo "=== NEON instructions in unoptimized version ==="
	@grep -c -E "(vld1|vst1|vmul|vadd|vsub|vfma|vdup|vget|vpadd)" vector_benchmark_unopt.s || echo "0"

# Inspect specific function assembly with objdump
objdump-neon: vector_benchmark
	@echo "=== Disassembly of NEON functions ==="
	objdump -d vector_benchmark | grep -A 50 "VectorL2SquaredDistanceNEON>" || echo "Function not found in objdump"

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
	./vector_benchmark && $(MAKE) clean

clean:
	rm -f vector_benchmark vector_benchmark.s vector_benchmark_opt.s vector_benchmark_unopt.s

.PHONY: all run clean asm neon-check neon-functions compare-asm objdump-neon cpu-info
