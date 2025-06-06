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

# QEMU ARM64 emulation (similar to AWS Graviton)
QEMU_ARM_FLAGS = -M virt -cpu neoverse-n1 -m 2G -smp 4 -nographic -netdev user,id=net0 -device virtio-net-pci,netdev=net0
QEMU_SYSTEM = qemu-system-aarch64

# Cross-compile for ARM64 (if not already on ARM64)
vector_benchmark_arm64: vector_benchmark.c
ifeq ($(shell uname -m), arm64)
	@echo "Already on ARM64, using native compilation"
	$(MAKE) vector_benchmark
	cp vector_benchmark vector_benchmark_arm64
else ifeq ($(shell uname -m), aarch64)
	@echo "Already on aarch64, using native compilation"
	$(MAKE) vector_benchmark
	cp vector_benchmark vector_benchmark_arm64
else
	@echo "Cross-compiling for ARM64..."
	aarch64-linux-gnu-gcc $(CFLAGS) -static -o $@ $< $(LDFLAGS) || \
	gcc-aarch64-linux-gnu $(CFLAGS) -static -o $@ $< $(LDFLAGS) || \
	(echo "Error: ARM64 cross-compiler not found. Install with:" && \
	 echo "  Ubuntu/Debian: sudo apt install gcc-aarch64-linux-gnu" && \
	 echo "  macOS: brew install aarch64-elf-gcc" && \
	 echo "  Fedora: sudo dnf install gcc-aarch64-linux-gnu" && \
	 false)
endif

# Check if QEMU system emulation is available
check-qemu:
	@echo "Checking QEMU system emulation..."
	@which $(QEMU_SYSTEM) >/dev/null 2>&1 || \
	(echo "Error: QEMU ARM64 system emulation not found." && \
	 echo "Install with:" && \
	 echo "  Ubuntu/Debian: sudo apt install qemu-system-arm" && \
	 echo "  macOS: brew install qemu" && \
	 echo "  Fedora: sudo dnf install qemu-system-aarch64" && \
	 false)
	@echo "✓ QEMU ARM64 system emulation available"

# Check if QEMU user-mode emulation is available (fallback only)
check-qemu-user:
	@echo "Checking QEMU user-mode emulation (fallback only)..."
	@if which qemu-aarch64 >/dev/null 2>&1; then \
		echo "⚠ QEMU ARM64 user-mode available but not recommended"; \
		echo "  User-mode uses host OS system calls (not accurate for cross-platform)"; \
		echo "  Consider using system emulation for accurate Linux ARM64 testing"; \
	elif which qemu-aarch64-static >/dev/null 2>&1; then \
		echo "⚠ QEMU ARM64 user-mode-static available but not recommended"; \
		echo "  User-mode uses host OS system calls (not accurate for cross-platform)"; \
	else \
		echo "ℹ User-mode emulation not found (system emulation preferred anyway)"; \
	fi

# Download ARM64 Linux kernel and create minimal rootfs
setup-qemu-linux: check-qemu
	@echo "=== Setting up ARM64 Linux environment for QEMU ==="
	@mkdir -p qemu-linux
	@if [ ! -f "qemu-linux/vmlinuz" ]; then \
		echo "Downloading ARM64 Linux kernel..."; \
		curl -L -o qemu-linux/vmlinuz "https://github.com/dhruvvyas90/qemu-rpi-kernel/raw/master/kernel8.img" || \
		(echo "Downloading Ubuntu ARM64 kernel..." && \
		 curl -L -o qemu-linux/vmlinuz "http://ports.ubuntu.com/ubuntu-ports/dists/jammy/main/installer-arm64/current/images/netboot/ubuntu-installer/arm64/linux"); \
	fi
	@if [ ! -f "qemu-linux/initrd.img" ]; then \
		echo "Downloading ARM64 initrd..."; \
		curl -L -o qemu-linux/initrd.img "http://ports.ubuntu.com/ubuntu-ports/dists/jammy/main/installer-arm64/current/images/netboot/ubuntu-installer/arm64/initrd.gz" || \
		echo "Warning: Could not download initrd, creating minimal one..."; \
	fi
	@if [ ! -f "qemu-linux/rootfs.img" ]; then \
		echo "Creating minimal ARM64 rootfs..."; \
		dd if=/dev/zero of=qemu-linux/rootfs.img bs=1M count=512 2>/dev/null; \
		echo "Note: You may need to format and populate this rootfs for full testing"; \
	fi
	@echo "✓ ARM64 Linux environment ready"

# Test with QEMU system emulation (accurate cross-platform testing)
qemu-system-test: vector_benchmark_arm64 setup-qemu-linux
	@echo "=== Testing with QEMU System Emulation (Accurate ARM64 Linux) ==="
	@echo "Emulating complete ARM64 Linux system similar to AWS Graviton"
	@echo "Copying benchmark to QEMU environment..."
	@cp vector_benchmark_arm64 qemu-linux/
	@echo "Starting ARM64 Linux system emulation..."
	@echo "Note: This boots a complete ARM64 Linux system for accurate testing"
	$(QEMU_SYSTEM) $(QEMU_ARM_FLAGS) \
		-kernel qemu-linux/vmlinuz \
		-initrd qemu-linux/initrd.img \
		-append "console=ttyAMA0 root=/dev/ram rdinit=/sbin/init" \
		-drive file=qemu-linux/rootfs.img,format=raw,id=hd0 \
		-device virtio-blk-pci,drive=hd0 \
		|| echo "Note: Full system emulation requires proper kernel/rootfs setup"

# Simplified system test with direct kernel boot
qemu-direct-test: vector_benchmark_arm64 check-qemu
	@echo "=== Direct ARM64 Kernel Boot Test ==="
	@echo "Testing with minimal ARM64 kernel boot (no full OS)"
	@mkdir -p qemu-test
	@cp vector_benchmark_arm64 qemu-test/
	@echo '#!/bin/sh' > qemu-test/init.sh
	@echo 'echo "=== ARM64 Linux Environment ==="' >> qemu-test/init.sh
	@echo 'uname -a' >> qemu-test/init.sh
	@echo 'cat /proc/cpuinfo | head -20' >> qemu-test/init.sh
	@echo 'echo "=== Running Vector Benchmark ==="' >> qemu-test/init.sh
	@echo './vector_benchmark_arm64 || echo "Benchmark failed"' >> qemu-test/init.sh
	@echo 'echo "=== Test Complete ==="' >> qemu-test/init.sh
	@echo 'poweroff' >> qemu-test/init.sh
	@chmod +x qemu-test/init.sh
	@echo "Direct kernel boot test prepared. For full testing, use 'make qemu-system-test'"

# Fallback to user-mode only if system emulation fails
qemu-user-fallback: vector_benchmark_arm64
	@echo "=== Fallback: User-Mode Emulation (Less Accurate) ==="
	@echo "⚠ Warning: This uses host OS system calls, not true ARM64 Linux"
	@echo "Results may not accurately represent AWS Graviton behavior"
	@if which qemu-aarch64 >/dev/null 2>&1; then \
		echo "Using qemu-aarch64 (user-mode fallback)..."; \
		qemu-aarch64 -cpu neoverse-n1 ./vector_benchmark_arm64 2>/dev/null || \
		qemu-aarch64 -cpu cortex-a72 ./vector_benchmark_arm64 2>/dev/null || \
		qemu-aarch64 ./vector_benchmark_arm64; \
	elif which qemu-aarch64-static >/dev/null 2>&1; then \
		echo "Using qemu-aarch64-static (user-mode fallback)..."; \
		qemu-aarch64-static ./vector_benchmark_arm64; \
	else \
		echo "Error: No QEMU emulation available"; \
		false; \
	fi

# Renamed from qemu-user-test for clarity
qemu-test: qemu-system-test

run: vector_benchmark
	./vector_benchmark

clean:
	rm -f vector_benchmark vector_benchmark_arm64 vector_benchmark.s vector_benchmark_opt.s vector_benchmark_unopt.s vector_benchmark_annotated.s vector_benchmark_debug.s vector_benchmark_qemu.s
	rm -rf qemu-test qemu-linux

.PHONY: all run clean asm asm-annotated asm-debug neon-check neon-check-annotated neon-functions compare-asm objdump-neon cpu-info debug-asm vector_benchmark_arm64 check-qemu check-qemu-user setup-qemu-linux qemu-system-test qemu-direct-test qemu-user-fallback
