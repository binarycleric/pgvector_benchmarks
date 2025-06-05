CC = gcc
CFLAGS = -O3 -Wall -Wextra -march=native -mtune=native
LDFLAGS = -lm

ifeq ($(shell uname), Darwin)
    # Apple Silicon specific flags
    CFLAGS += -march=armv8.5-a -mfma
else ifeq ($(shell uname), Linux)
    # Linux ARM specific flags
    CFLAGS += -mfpu=neon-fp-armv8 -mfma
endif

# Add NEON support
CFLAGS += -D__ARM_NEON

all: vector_benchmark

vector_benchmark: vector_benchmark.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

run: vector_benchmark
	./vector_benchmark && $(MAKE) clean

clean:
	rm -f vector_benchmark
