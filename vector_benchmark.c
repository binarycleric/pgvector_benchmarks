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
#define MAX_PERCENT_DIFF 0.00025f  // Maximum allowed percentage difference

/*
   High-performance NEON implementation with FMA and optimal unrolling.
   Fused Multiply-Add (FMA) is a way to perform two multiplications and
   an addition in a single instruction.
*/
static inline float
VectorL2SquaredDistanceNEON_FMA(int dim, float *ax, float *bx)
{
    float32x4_t sum1 = vdupq_n_f32(0.0f);
    float32x4_t sum2 = vdupq_n_f32(0.0f);
    float32x4_t sum3 = vdupq_n_f32(0.0f);
    float32x4_t sum4 = vdupq_n_f32(0.0f);
    float32x4_t a1, a2, a3, a4;
    float32x4_t b1, b2, b3, b4;
    float32x4_t diff1, diff2, diff3, diff4;
    int i = 0;

    /* Unroll by 16 with fused multiply-add for best performance and accuracy */
    for (; i < dim - 15; i += 16) {
        a1 = vld1q_f32(&ax[i]);
        b1 = vld1q_f32(&bx[i]);
        diff1 = vsubq_f32(a1, b1);
        sum1 = vfmaq_f32(sum1, diff1, diff1);

        a2 = vld1q_f32(&ax[i + 4]);
        b2 = vld1q_f32(&bx[i + 4]);
        diff2 = vsubq_f32(a2, b2);
        sum2 = vfmaq_f32(sum2, diff2, diff2);

        a3 = vld1q_f32(&ax[i + 8]);
        b3 = vld1q_f32(&bx[i + 8]);
        diff3 = vsubq_f32(a3, b3);
        sum3 = vfmaq_f32(sum3, diff3, diff3);

        a4 = vld1q_f32(&ax[i + 12]);
        b4 = vld1q_f32(&bx[i + 12]);
        diff4 = vsubq_f32(a4, b4);
        sum4 = vfmaq_f32(sum4, diff4, diff4);
    }

    /* Handle remaining elements in groups of 4 when possible */
    for (; i < dim - 3; i += 4) {
        float32x4_t a = vld1q_f32(&ax[i]);
        float32x4_t b = vld1q_f32(&bx[i]);
        float32x4_t diff = vsubq_f32(a, b);
        sum1 = vfmaq_f32(sum1, diff, diff);
    }

    /* Combine all sums using pairwise addition for better numerical stability */
    sum1 = vaddq_f32(sum1, sum2);
    sum3 = vaddq_f32(sum3, sum4);
    sum1 = vaddq_f32(sum1, sum3);

    /* Handle final remaining elements (0-3) */
    float remaining_sum = 0.0f;
    for (; i < dim; i++) {
        float diff = ax[i] - bx[i];
        remaining_sum += diff * diff;
    }

    /* Horizontal sum with optimal pairwise reduction */
    float32x2_t sum_lo = vget_low_f32(sum1);
    float32x2_t sum_hi = vget_high_f32(sum1);
    float32x2_t sum_pair = vpadd_f32(sum_lo, sum_hi);
    float neon_sum = vget_lane_f32(vpadd_f32(sum_pair, sum_pair), 0);

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
float_within_tolerance(float a, float b)
{
    float abs_diff = fabsf(a - b);
    float percent_diff = (abs_diff / b) * 100.0f;
    return percent_diff <= MAX_PERCENT_DIFF;
}

/* Comparison function for qsort - compares two floats */
static int
compare_floats(const void *a, const void *b)
{
    float fa = *(const float*)a;
    float fb = *(const float*)b;

    if (fa < fb) return -1;
    if (fa > fb) return 1;
    return 0;
}

/* Test L2 Distance implementations */
static void
test_l2_distance(float *vectors, float *query_vec)
{
    int64_t start_time, end_time;
    float total_neon_l2 = 0.0f, total_simple_l2 = 0.0f;
    int64_t neon_l2_time = 0, simple_l2_time = 0;

    /* Verify L2 distance implementations return the same results */
    printf("Verifying L2 distance implementations...\n");
    float total_diff = 0.0f;
    float total_percent_diff = 0.0f;
    float max_diff = 0.0f;
    float max_percent_diff = 0.0f;
    float min_diff = INFINITY;
    float min_percent_diff = INFINITY;
    int diff_count = 0;

    /* Arrays to store all differences for percentile calculation */
    float *abs_diffs = (float *)malloc(NUM_VECTORS * sizeof(float));
    float *percent_diffs = (float *)malloc(NUM_VECTORS * sizeof(float));
    if (!abs_diffs || !percent_diffs) {
        fprintf(stderr, "Memory allocation failed for difference arrays\n");
        return;
    }

    for (int i = 0; i < NUM_VECTORS; i++) {
        float neon_result = VectorL2SquaredDistanceNEON_FMA(DIM, &vectors[i * DIM], query_vec);
        float simple_result = VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);

        float abs_diff = fabsf(neon_result - simple_result);
        float percent_diff = (abs_diff / simple_result) * 100.0f;

        /* Store differences for percentile calculation */
        abs_diffs[i] = abs_diff;
        percent_diffs[i] = percent_diff;

        // Track all differences
        total_diff += abs_diff;
        total_percent_diff += percent_diff;
        diff_count++;

        if (abs_diff > max_diff) {
            max_diff = abs_diff;
        }
        if (percent_diff > max_percent_diff) {
            max_percent_diff = percent_diff;
        }
        if (abs_diff < min_diff) {
            min_diff = abs_diff;
        }
        if (percent_diff < min_percent_diff) {
            min_percent_diff = percent_diff;
        }

        if (!float_within_tolerance(neon_result, simple_result)) {
            printf("L2 distance mismatch at vector %d:\n", i);
            printf("  NEON:    %f\n", neon_result);
            printf("  Simple:  %f\n", simple_result);
            printf("  Diff:    %f (%.6f%%)\n", abs_diff, percent_diff);
            printf("  Max allowed diff: %.6f%%\n", MAX_PERCENT_DIFF);
        }
    }

    /* Sort arrays for percentile calculation using qsort for efficiency */
    qsort(abs_diffs, NUM_VECTORS, sizeof(float), compare_floats);
    qsort(percent_diffs, NUM_VECTORS, sizeof(float), compare_floats);

    /* Calculate percentiles */
    int p95_idx = (int)((NUM_VECTORS - 1) * 0.95);
    int p99_idx = (int)((NUM_VECTORS - 1) * 0.99);
    float p95_diff = abs_diffs[p95_idx];
    float p95_percent_diff = percent_diffs[p95_idx];
    float p99_diff = abs_diffs[p99_idx];
    float p99_percent_diff = percent_diffs[p99_idx];

    float avg_diff = total_diff / diff_count;
    float avg_percent_diff = total_percent_diff / diff_count;
    printf("Minimum difference: %.9f (%.6f%%)\n", min_diff, min_percent_diff);
    printf("Average difference: %.9f (%.6f%%)\n", avg_diff, avg_percent_diff);
    printf("P95 difference:     %.9f (%.6f%%)\n", p95_diff, p95_percent_diff);
    printf("P99 difference:     %.9f (%.6f%%)\n", p99_diff, p99_percent_diff);
    printf("Maximum difference: %.9f (%.6f%%)\n", max_diff, max_percent_diff);
    printf("Tolerance: %.6f%%\n\n", MAX_PERCENT_DIFF);

    /* Clean up */
    free(abs_diffs);
    free(percent_diffs);

    /* Warm up */
    for (int i = 0; i < 10; i++) {
        VectorL2SquaredDistanceNEON_FMA(DIM, &vectors[i * DIM], query_vec);
        VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);
    }

    /* Benchmark L2 distance implementations */
    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_neon_l2 += VectorL2SquaredDistanceNEON_FMA(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    neon_l2_time = end_time - start_time;

    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_simple_l2 += VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    simple_l2_time = end_time - start_time;

    /* Calculate difference between total distance sums */
    float total_sum_diff = fabsf(total_neon_l2 - total_simple_l2);
    float total_sum_percent_diff = (total_sum_diff / total_simple_l2) * 100.0f;

    printf("L2 Distance Benchmark Results:\n");
    printf("NEON Implementation:\n");
    printf("  Total time: %.2f ms\n", neon_l2_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)neon_l2_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total distance sum: %f\n", total_neon_l2);
    printf("\nSimple Implementation:\n");
    printf("  Total time: %.2f ms\n", simple_l2_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)simple_l2_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total distance sum: %f\n", total_simple_l2);
    printf("\nTotal Distance Sum Comparison:\n");
    printf("  Absolute difference: %.9f\n", total_sum_diff);
    printf("  Percentage difference: %.6f%%\n", total_sum_percent_diff);
    printf("\nL2 Distance Speedup: %.2fx\n\n", (float)simple_l2_time / neon_l2_time);
}

int
main(void)
{
    float *vectors;
    float *query_vec;

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

    printf("Benchmark Configuration:\n");
    printf("-----------------------\n");
    printf("Vector dimension: %d\n", DIM);
    printf("Number of vectors: %d\n", NUM_VECTORS);
    printf("Number of iterations: %d\n\n", NUM_ITERATIONS);

    /* Print query vector */
    printf("Query Vector (first 10 dimensions):\n");
    for (int i = 0; i < 10 && i < DIM; i++) {
        printf("  [%d]: %.6f\n", i, query_vec[i]);
    }
    if (DIM > 10) {
        printf("  ... (%d more dimensions)\n", DIM - 10);
    }
    printf("\n");

    /* Print first few vectors from the dataset */
    printf("Sample Dataset Vectors (first 3 vectors, first 10 dimensions each):\n");
    for (int v = 0; v < 3 && v < NUM_VECTORS; v++) {
        printf("Vector %d:\n", v);
        for (int i = 0; i < 10 && i < DIM; i++) {
            printf("  [%d]: %.6f\n", i, vectors[v * DIM + i]);
        }
        if (DIM > 10) {
            printf("  ... (%d more dimensions)\n", DIM - 10);
        }
        printf("\n");
    }

    test_l2_distance(vectors, query_vec);

    free(vectors);
    free(query_vec);

    return 0;
}