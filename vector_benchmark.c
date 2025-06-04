#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>
#include <math.h>
#include <stdbool.h>
#include <arm_neon.h>

#define DIM 1536  // OpenAI embedding dimension
#define NUM_VECTORS 10000
#define NUM_ITERATIONS 1000
#define EPSILON 0.000001f  // Small value for float comparison
#define MAX_PERCENT_DIFF 0.0005f  // Maximum allowed percentage difference

/* NEON implementation */
static inline float
VectorL2SquaredDistanceNEON(int dim, float *ax, float *bx)
{
    float32x4_t sum1 = vdupq_n_f32(0.0f);
    float32x4_t sum2 = vdupq_n_f32(0.0f);
    float32x4_t sum3 = vdupq_n_f32(0.0f);
    float32x4_t sum4 = vdupq_n_f32(0.0f);
    int i = 0;

    /* Process 16 elements at a time using 4 NEON registers */
    for (; i < dim - 15; i += 16) {
        /* First 4 elements */
        float32x4_t a1 = vld1q_f32(&ax[i]);
        float32x4_t b1 = vld1q_f32(&bx[i]);
        float32x4_t diff1 = vsubq_f32(a1, b1);
        sum1 = vaddq_f32(sum1, vmulq_f32(diff1, diff1));

        /* Next 4 elements */
        float32x4_t a2 = vld1q_f32(&ax[i + 4]);
        float32x4_t b2 = vld1q_f32(&bx[i + 4]);
        float32x4_t diff2 = vsubq_f32(a2, b2);
        sum2 = vaddq_f32(sum2, vmulq_f32(diff2, diff2));

        /* Next 4 elements */
        float32x4_t a3 = vld1q_f32(&ax[i + 8]);
        float32x4_t b3 = vld1q_f32(&bx[i + 8]);
        float32x4_t diff3 = vsubq_f32(a3, b3);
        sum3 = vaddq_f32(sum3, vmulq_f32(diff3, diff3));

        /* Last 4 elements */
        float32x4_t a4 = vld1q_f32(&ax[i + 12]);
        float32x4_t b4 = vld1q_f32(&bx[i + 12]);
        float32x4_t diff4 = vsubq_f32(a4, b4);
        sum4 = vaddq_f32(sum4, vmulq_f32(diff4, diff4));
    }

    /* Combine the 4 NEON registers */
    sum1 = vaddq_f32(sum1, sum2);
    sum1 = vaddq_f32(sum1, sum3);
    sum1 = vaddq_f32(sum1, sum4);

    /* Handle remaining elements */
    float remaining_sum = 0.0f;
    for (; i < dim; i++) {
        float diff = ax[i] - bx[i];
        remaining_sum += diff * diff;
    }

    /* Horizontal sum of NEON result */
    float32x2_t sum_lo = vget_low_f32(sum1);
    float32x2_t sum_hi = vget_high_f32(sum1);
    float32x2_t sum_half = vadd_f32(sum_lo, sum_hi);
    float neon_sum = vget_lane_f32(vpadd_f32(sum_half, sum_half), 0);

    return neon_sum + remaining_sum;
}

/* Simple implementation */
static inline float
VectorL2SquaredDistanceSimple(int dim, float *ax, float *bx)
{
	float		distance = 0.0;

	/* Auto-vectorized */
	for (int i = 0; i < dim; i++)
	{
		float		diff = ax[i] - bx[i];

		distance += diff * diff;
	}

	return distance;
}

/* Generate random float between -1 and 1 */
static float
random_float(void)
{
    return (float)rand() / RAND_MAX * 2.0f - 1.0f;
}

/* Initialize vector with random values */
static void
init_vector(float *vec, int dim)
{
    for (int i = 0; i < dim; i++)
        vec[i] = random_float();
}

/* Get current time in microseconds */
static int64_t
get_time_us(void)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return tv.tv_sec * 1000000LL + tv.tv_usec;
}

/* Compare two floats with epsilon and percentage difference */
static bool
float_equal(float a, float b)
{
    float abs_diff = fabsf(a - b);
    float percent_diff = (abs_diff / b) * 100.0f;
    return percent_diff <= MAX_PERCENT_DIFF;
}

int
main(void)
{
    float *vectors;
    float *query_vec;
    int64_t start_time, end_time;
    float total_neon = 0.0f, total_simple = 0.0f;
    int64_t neon_time = 0, simple_time = 0;
    bool results_match = true;

    /* Allocate memory */
    vectors = (float *)malloc(NUM_VECTORS * DIM * sizeof(float));
    query_vec = (float *)malloc(DIM * sizeof(float));
    if (!vectors || !query_vec) {
        fprintf(stderr, "Memory allocation failed\n");
        return 1;
    }

    /* Initialize vectors with random values */
    srand(time(NULL));
    for (int i = 0; i < NUM_VECTORS; i++)
        init_vector(&vectors[i * DIM], DIM);
    init_vector(query_vec, DIM);

    /* Verify implementations return the same results */
    printf("Verifying implementations...\n");
    for (int i = 0; i < NUM_VECTORS; i++) {
        float neon_result = VectorL2SquaredDistanceNEON(DIM, &vectors[i * DIM], query_vec);
        float simple_result = VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);

        if (!float_equal(neon_result, simple_result)) {
            float abs_diff = fabsf(neon_result - simple_result);
            float percent_diff = (abs_diff / simple_result) * 100.0f;
            printf("Mismatch at vector %d:\n", i);
            printf("  NEON:    %f\n", neon_result);
            printf("  Simple:  %f\n", simple_result);
            printf("  Diff:    %f (%.6f%%)\n", abs_diff, percent_diff);
            printf("  Max allowed diff: %.6f%%\n", MAX_PERCENT_DIFF);
            results_match = false;
            break;
        }
    }

    if (!results_match) {
        printf("\nERROR: Implementations produce different results!\n");
        free(vectors);
        free(query_vec);
        return 1;
    }
    printf("Verification passed!\n\n");

    /* Warm up */
    for (int i = 0; i < 10; i++) {
        VectorL2SquaredDistanceNEON(DIM, &vectors[i * DIM], query_vec);
        VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);
    }

    /* Benchmark NEON implementation */
    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_neon += VectorL2SquaredDistanceNEON(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    neon_time = end_time - start_time;

    /* Benchmark Simple implementation */
    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_simple += VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    simple_time = end_time - start_time;

    /* Print results */
    printf("Benchmark Results:\n");
    printf("-----------------\n");
    printf("Vector dimension: %d\n", DIM);
    printf("Number of vectors: %d\n", NUM_VECTORS);
    printf("Number of iterations: %d\n", NUM_ITERATIONS);
    printf("\nNEON Implementation:\n");
    printf("  Total time: %.2f ms\n", neon_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)neon_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total distance sum: %f\n", total_neon);
    printf("\nSimple Implementation:\n");
    printf("  Total time: %.2f ms\n", simple_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)simple_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total distance sum: %f\n", total_simple);
    printf("\nSpeedup: %.2fx\n", (float)simple_time / neon_time);

    /* Clean up */
    free(vectors);
    free(query_vec);

    return 0;
}