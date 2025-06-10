CC = clang
CFLAGS = -O2 -Wall -Wextra -march=native -mtune=native -I/usr/include -ftree-vectorize -fassociative-math -fno-signed-zeros -fno-trapping-math
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

# Generate assembly without inlining to preserve function boundaries
asm-no-inline: vector_benchmark_no_inline.s

vector_benchmark_no_inline.s: vector_benchmark.c
	$(CC) -O1 -fno-inline -Wall -Wextra -march=native -mtune=native -S -ftree-vectorize -fverbose-asm -fassociative-math -fno-signed-zeros -fno-trapping-math -o $@ $<
	@echo "Assembly with preserved functions generated in vector_benchmark_no_inline.s"
	@echo "Function symbols available:"
	@grep -E "^[_A-Za-z][A-Za-z0-9_]*:" $@ | head -10

# Compare assembly of NEON vs Simple implementations (using no-inline version)
compare-functions: vector_benchmark_neon_asm.txt vector_benchmark_simple_asm.txt
	@echo "=== Assembly Comparison: NEON_FMA vs Simple ==="
	@echo ""
	@echo "NEON_FMA Function Assembly:"
	@echo "=========================="
	@cat vector_benchmark_neon_asm.txt
	@echo ""
	@echo "Simple Function Assembly:"
	@echo "========================"
	@cat vector_benchmark_simple_asm.txt
	@echo ""
	@echo "=== Files saved for detailed analysis ==="
	@echo "NEON_FMA: vector_benchmark_neon_asm.txt"
	@echo "Simple:   vector_benchmark_simple_asm.txt"

# Extract NEON_FMA function assembly from no-inline version
vector_benchmark_neon_asm.txt: vector_benchmark_no_inline.s
	@echo "Extracting VectorL2SquaredDistanceNEON_FMA assembly..."
	@awk '/VectorL2SquaredDistanceNEON_FMA:/{flag=1; print} flag && /^[_A-Za-z][A-Za-z0-9_]*:/ && !/VectorL2SquaredDistanceNEON_FMA:/{flag=0} flag && !/^[_A-Za-z][A-Za-z0-9_]*:/' $< > $@
	@if [ ! -s $@ ]; then \
		echo "Warning: Could not extract NEON_FMA function. Trying alternative method..."; \
		grep -A 100 "VectorL2SquaredDistanceNEON_FMA:" $< | grep -B 100 -E "^[_A-Za-z][A-Za-z0-9_]*:" | head --lines=-1 > $@; \
	fi
	@echo "Extracted $$(wc -l < $@) lines of NEON_FMA assembly"

# Extract Simple function assembly from no-inline version
vector_benchmark_simple_asm.txt: vector_benchmark_no_inline.s
	@echo "Extracting VectorL2SquaredDistanceSimple assembly..."
	@awk '/VectorL2SquaredDistanceSimple:/{flag=1; print} flag && /^[_A-Za-z][A-Za-z0-9_]*:/ && !/VectorL2SquaredDistanceSimple:/{flag=0} flag && !/^[_A-Za-z][A-Za-z0-9_]*:/' $< > $@
	@if [ ! -s $@ ]; then \
		echo "Warning: Could not extract Simple function. Trying alternative method..."; \
		grep -A 50 "VectorL2SquaredDistanceSimple:" $< | grep -B 50 -E "^[_A-Za-z][A-Za-z0-9_]*:" | head --lines=-1 > $@; \
	fi
	@echo "Extracted $$(wc -l < $@) lines of Simple assembly"

# Side-by-side comparison (requires column/pr command)
compare-side-by-side: vector_benchmark_neon_asm.txt vector_benchmark_simple_asm.txt
	@echo "=== Side-by-Side Assembly Comparison ==="
	@echo ""
	@if command -v pr >/dev/null 2>&1; then \
		pr -m -t -w 120 vector_benchmark_neon_asm.txt vector_benchmark_simple_asm.txt | \
		sed '1i NEON_FMA                                    |  Simple'; \
	else \
		echo "NEON_FMA Assembly:"; \
		cat vector_benchmark_neon_asm.txt; \
		echo ""; \
		echo "Simple Assembly:"; \
		cat vector_benchmark_simple_asm.txt; \
	fi

# Count instructions in each function
compare-instruction-count: vector_benchmark_neon_asm.txt vector_benchmark_simple_asm.txt
	@echo "=== Instruction Count Comparison ==="
	@echo -n "NEON_FMA instructions: "
	@grep -E '^\s+[a-z]' vector_benchmark_neon_asm.txt | wc -l || echo "0"
	@echo -n "Simple instructions:   "
	@grep -E '^\s+[a-z]' vector_benchmark_simple_asm.txt | wc -l || echo "0"
	@echo ""
	@echo "NEON instructions in NEON_FMA:"
	@grep -E '^\s+(ld1|st1|fadd|fsub|fmul|fmla|movi|v[a-z]|faddp)' vector_benchmark_neon_asm.txt | wc -l || echo "0"

# All assembly analysis
analyze-functions: compare-functions compare-instruction-count
	@echo ""
	@echo "=== Analysis Complete ==="
	@echo "Use 'make compare-side-by-side' for side-by-side view"

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

run-arm64:
	podman build --arch=arm64 -t pgvector-benchmarks -f Dockerfile.arm64 .
	podman run --rm --arch=arm64 pgvector-benchmarks

clean:
	rm -f vector_benchmark vector_benchmark.s vector_benchmark_opt.s vector_benchmark_unopt.s vector_benchmark_annotated.s vector_benchmark_debug.s vector_benchmark_no_inline.s vector_benchmark_neon_asm.txt vector_benchmark_simple_asm.txt

.PHONY: all run clean asm asm-annotated asm-no-inline compare-functions compare-instruction-count analyze-functions cpu-info debug-asm
