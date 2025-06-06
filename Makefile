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

# Generate assembly with function names and comments
asm-annotated: vector_benchmark_annotated.s

vector_benchmark_annotated.s: vector_benchmark.c
	$(CC) $(CFLAGS) -S -fverbose-asm -o $@ $<
	@echo "Annotated assembly generated in vector_benchmark_annotated.s"

# Generate assembly with debug info and function labels
asm-debug: vector_benchmark_debug.s

vector_benchmark_debug.s: vector_benchmark.c
	$(CC) $(CFLAGS) -g -S -fverbose-asm -fno-omit-frame-pointer -o $@ $<
	@echo "Debug assembly with function labels generated in vector_benchmark_debug.s"

# Show NEON instructions in the assembly
neon-check: vector_benchmark.s
	@echo "=== NEON Intrinsic Mnemonics (older syntax) ==="
	@grep -E "(vld1|vst1|vmul|vadd|vsub|vfma|vdup|vget|vpadd|vset)" vector_benchmark.s || echo "No classic NEON mnemonics found"
	@echo ""
	@echo "=== ARM64 SIMD Instructions (modern syntax) ==="
	@grep -E "(ld1|st1|fmul|fadd|fsub|fmla|dup|mov|uzp|zip)" vector_benchmark.s | grep -E "\\.4s|\\.2s|\\.2d|v[0-9]+" || echo "No ARM64 SIMD instructions found"
	@echo ""
	@echo "=== Vector Register Usage ==="
	@grep -E "v[0-9]+\\." vector_benchmark.s | head -10 || echo "No vector registers found"
	@echo ""
	@echo "=== Instruction Counts ==="
	@echo "Classic NEON instructions: $$(grep -c -E "(vld1|vst1|vmul|vadd|vsub|vfma|vdup|vget|vpadd)" vector_benchmark.s 2>/dev/null || echo 0)"
	@echo "ARM64 SIMD instructions: $$(grep -c -E "(ld1|st1|fmul|fadd|fsub|fmla).*\\.(4s|2s|2d)" vector_benchmark.s 2>/dev/null || echo 0)"
	@echo "Vector registers used: $$(grep -c "v[0-9]\\+\\." vector_benchmark.s 2>/dev/null || echo 0)"

# Check NEON in annotated assembly (with function names)
neon-check-annotated: vector_benchmark_annotated.s
	@echo "=== Checking Annotated Assembly for NEON ==="
	@echo "Function labels found:"
	@grep -E "^[a-zA-Z_][a-zA-Z0-9_]*:" vector_benchmark_annotated.s | head -5
	@echo ""
	@echo "=== ARM64 SIMD Instructions with Context ==="
	@grep -B2 -A2 -E "(ld1|st1|fmul|fadd|fsub|fmla).*\\.(4s|2s|2d)" vector_benchmark_annotated.s || echo "No ARM64 SIMD instructions found"

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

# Debug assembly output (show sample)
debug-asm: vector_benchmark.s
	@echo "=== First 50 lines of assembly ==="
	@head -50 vector_benchmark.s
	@echo ""
	@echo "=== Looking for VectorL2SquaredDistanceNEON function ==="
	@grep -n "VectorL2SquaredDistanceNEON" vector_benchmark.s || echo "Function not found"
	@echo ""
	@echo "=== Sample lines with potential SIMD ==="
	@grep -E "(fmul|fadd|fsub|ld1|st1|v[0-9])" vector_benchmark.s | head -10 || echo "No obvious SIMD instructions"

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
	rm -f vector_benchmark vector_benchmark.s vector_benchmark_opt.s vector_benchmark_unopt.s vector_benchmark_annotated.s vector_benchmark_debug.s

.PHONY: all run clean asm asm-annotated asm-debug neon-check neon-check-annotated neon-functions compare-asm objdump-neon cpu-info debug-asm
