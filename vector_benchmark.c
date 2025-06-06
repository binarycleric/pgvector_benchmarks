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
VectorCosineSimilarityNEON(int dim, float *ax, float *bx)
{
    float32x4_t dot_sum = vdupq_n_f32(0.0f);
    float32x4_t norm_a_sum = vdupq_n_f32(0.0f);
    float32x4_t norm_b_sum = vdupq_n_f32(0.0f);
    float32x4_t a, b;
    float32x2_t sum2;
    float remaining_dot = 0.0f;
    float remaining_norm_a = 0.0f;
    float remaining_norm_b = 0.0f;
    int i = 0;

    for (; i < dim - 3; i += 4) {
        a = vld1q_f32(&ax[i]);
        b = vld1q_f32(&bx[i]);

        dot_sum = vaddq_f32(dot_sum, vmulq_f32(a, b));
        norm_a_sum = vaddq_f32(norm_a_sum, vmulq_f32(a, a));
        norm_b_sum = vaddq_f32(norm_b_sum, vmulq_f32(b, b));
    }

    for (; i < dim; i++) {
        remaining_dot += ax[i] * bx[i];
        remaining_norm_a += ax[i] * ax[i];
        remaining_norm_b += bx[i] * bx[i];
    }

    sum2 = vadd_f32(vget_low_f32(dot_sum), vget_high_f32(dot_sum));
    float dot_product = vget_lane_f32(vpadd_f32(sum2, sum2), 0) + remaining_dot;

    sum2 = vadd_f32(vget_low_f32(norm_a_sum), vget_high_f32(norm_a_sum));
    float norm_a = vget_lane_f32(vpadd_f32(sum2, sum2), 0) + remaining_norm_a;

    sum2 = vadd_f32(vget_low_f32(norm_b_sum), vget_high_f32(norm_b_sum));
    float norm_b = vget_lane_f32(vpadd_f32(sum2, sum2), 0) + remaining_norm_b;

    return dot_product / sqrtf(norm_a * norm_b);
}

static inline double
VectorCosineSimilarity(int dim, float *ax, float *bx)
{
	float		similarity = 0.0;
	float		norma = 0.0;
	float		normb = 0.0;

	/* Auto-vectorized */
	for (int i = 0; i < dim; i++)
	{
		similarity += ax[i] * bx[i];
		norma += ax[i] * ax[i];
		normb += bx[i] * bx[i];
	}

	/* Use sqrt(a * b) over sqrt(a) * sqrt(b) */
	return (double) similarity / sqrt((double) norma * (double) normb);
}

/* NEON implementation */
static inline float
VectorL2SquaredDistanceNEON(int dim, float *ax, float *bx)
{
    float32x4_t sum1 = vdupq_n_f32(0.0f);
    float32x4_t sum2 = vdupq_n_f32(0.0f);
    float32x4_t sum3 = vdupq_n_f32(0.0f);
    float32x4_t sum4 = vdupq_n_f32(0.0f);
    float32x4_t a1, a2, a3, a4;
    float32x4_t b1, b2, b3, b4;
    float32x4_t diff1, diff2, diff3, diff4;
    float32x2_t sum_lo, sum_hi, sum_half;
    float neon_sum, remaining_sum;
    int i = 0;

    for (; i < dim - 15; i += 16) {
        a1 = vld1q_f32(&ax[i]);
        b1 = vld1q_f32(&bx[i]);
        diff1 = vsubq_f32(a1, b1);
        sum1 = vaddq_f32(sum1, vmulq_f32(diff1, diff1));

        a2 = vld1q_f32(&ax[i + 4]);
        b2 = vld1q_f32(&bx[i + 4]);
        diff2 = vsubq_f32(a2, b2);
        sum2 = vaddq_f32(sum2, vmulq_f32(diff2, diff2));

        a3 = vld1q_f32(&ax[i + 8]);
        b3 = vld1q_f32(&bx[i + 8]);
        diff3 = vsubq_f32(a3, b3);
        sum3 = vaddq_f32(sum3, vmulq_f32(diff3, diff3));

        a4 = vld1q_f32(&ax[i + 12]);
        b4 = vld1q_f32(&bx[i + 12]);
        diff4 = vsubq_f32(a4, b4);
        sum4 = vaddq_f32(sum4, vmulq_f32(diff4, diff4));
    }

    sum1 = vaddq_f32(sum1, sum2);
    sum1 = vaddq_f32(sum1, sum3);
    sum1 = vaddq_f32(sum1, sum4);

    remaining_sum = 0.0f;
    for (; i < dim; i++) {
        float diff = ax[i] - bx[i];
        remaining_sum += diff * diff;
    }

    sum_lo = vget_low_f32(sum1);
    sum_hi = vget_high_f32(sum1);
    sum_half = vadd_f32(sum_lo, sum_hi);
    neon_sum = vget_lane_f32(vpadd_f32(sum_half, sum_half), 0);

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


static inline float
VectorInnerProductNEON(int dim, float *ax, float *bx)
{
#ifdef __ARM_FEATURE_FMA
    // Use FMA instructions when available
    float32x4_t sum = vdupq_n_f32(0.0f);
    float32x4_t a, b;
    float32x2_t sum2;
    float remaining_sum = 0.0f;
    int i = 0;

    // Process 4 elements at a time using FMA
    for (; i < dim - 3; i += 4) {
        a = vld1q_f32(&ax[i]);
        b = vld1q_f32(&bx[i]);
        sum = vfmaq_f32(sum, a, b);  // Fused multiply-add
    }

    // Handle remaining elements
    for (; i < dim; i++) {
        remaining_sum += ax[i] * bx[i];
    }

    // Horizontal sum
    sum2 = vadd_f32(vget_low_f32(sum), vget_high_f32(sum));
    return vget_lane_f32(vpadd_f32(sum2, sum2), 0) + remaining_sum;
#else
    // Fallback to a more precise accumulation pattern
    float sum = 0.0f;
    float32x4_t a, b;
    float32x4_t prod;
    float32x2_t sum2;
    int i = 0;

    // Process 4 elements at a time
    for (; i < dim - 3; i += 4) {
        a = vld1q_f32(&ax[i]);
        b = vld1q_f32(&bx[i]);
        prod = vmulq_f32(a, b);

        // Accumulate in a way that minimizes floating-point error
        float32x2_t lo = vget_low_f32(prod);
        float32x2_t hi = vget_high_f32(prod);
        float32x2_t sum_pair = vadd_f32(lo, hi);
        float pair_sum = vget_lane_f32(vpadd_f32(sum_pair, sum_pair), 0);
        sum += pair_sum;
    }

    // Handle remaining elements
    for (; i < dim; i++) {
        sum += ax[i] * bx[i];
    }

    return sum;
#endif
}

static inline float
VectorInnerProductSimple(int dim, float *ax, float *bx)
{
	float		distance = 0.0;

	/* Auto-vectorized */
	for (int i = 0; i < dim; i++)
		distance += ax[i] * bx[i];

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

int
main(void)
{
    float *vectors;
    float *query_vec;
    int64_t start_time, end_time;
    float total_neon_l2 = 0.0f, total_simple_l2 = 0.0f;
    float total_neon_ip = 0.0f, total_simple_ip = 0.0f;
    double total_neon_cosine = 0.0, total_simple_cosine = 0.0;
    int64_t neon_l2_time = 0, simple_l2_time = 0;
    int64_t neon_ip_time = 0, simple_ip_time = 0;
    int64_t neon_cosine_time = 0, simple_cosine_time = 0;
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

    /* Verify L2 distance implementations return the same results */
    printf("Verifying L2 distance implementations...\n");
    float total_diff = 0.0f;
    float max_diff = 0.0f;
    float max_percent_diff = 0.0f;
    int diff_count = 0;

    for (int i = 0; i < NUM_VECTORS; i++) {
        float neon_result = VectorL2SquaredDistanceNEON(DIM, &vectors[i * DIM], query_vec);
        float simple_result = VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);

        float abs_diff = fabsf(neon_result - simple_result);
        float percent_diff = (abs_diff / simple_result) * 100.0f;

        // Track all differences
        total_diff += abs_diff;
        diff_count++;

        if (abs_diff > max_diff) {
            max_diff = abs_diff;
        }
        if (percent_diff > max_percent_diff) {
            max_percent_diff = percent_diff;
        }

        if (!float_within_tolerance(neon_result, simple_result)) {
            printf("L2 distance mismatch at vector %d:\n", i);
            printf("  NEON:    %f\n", neon_result);
            printf("  Simple:  %f\n", simple_result);
            printf("  Diff:    %f (%.6f%%)\n", abs_diff, percent_diff);
            printf("  Max allowed diff: %.6f%%\n", MAX_PERCENT_DIFF);
            results_match = false;
            break;
        }
    }

    if (!results_match) {
        printf("\nERROR: L2 distance implementations produce different results!\n");
        free(vectors);
        free(query_vec);
        return 1;
    }

    float avg_diff = total_diff / diff_count;
    printf("L2 distance verification passed!\n");
    printf("Average difference: %.9f\n", avg_diff);
    printf("Maximum difference: %.9f (%.6f%%)\n", max_diff, max_percent_diff);
    printf("Tolerance: %.6f%%\n\n", MAX_PERCENT_DIFF);

/*
    printf("Verifying cosine similarity implementations...\n");
    float total_cosine_diff = 0.0f;
    float max_cosine_diff = 0.0f;
    float max_cosine_percent_diff = 0.0f;
    int cosine_diff_count = 0;

    for (int i = 0; i < NUM_VECTORS; i++) {
        float neon_result = VectorCosineSimilarityNEON(DIM, &vectors[i * DIM], query_vec);
        double simple_result = VectorCosineSimilarity(DIM, &vectors[i * DIM], query_vec);

        float abs_diff = fabsf(neon_result - (float)simple_result);
        float percent_diff = (abs_diff / fabsf((float)simple_result)) * 100.0f;

        // Track all differences
        total_cosine_diff += abs_diff;
        cosine_diff_count++;

        if (abs_diff > max_cosine_diff) {
            max_cosine_diff = abs_diff;
        }
        if (percent_diff > max_cosine_percent_diff) {
            max_cosine_percent_diff = percent_diff;
        }

        if (!float_within_tolerance(neon_result, (float)simple_result)) {
            printf("Cosine similarity mismatch at vector %d:\n", i);
            printf("  NEON:    %f\n", neon_result);
            printf("  Simple:  %f\n", (float)simple_result);
            printf("  Diff:    %f (%.6f%%)\n", abs_diff, percent_diff);
            printf("  Max allowed diff: %.6f%%\n", MAX_PERCENT_DIFF);
            results_match = false;
            break;
        }
    }

    if (!results_match) {
        printf("\nERROR: Cosine similarity implementations produce different results!\n");
        free(vectors);
        free(query_vec);
        return 1;
    }

    float avg_cosine_diff = total_cosine_diff / cosine_diff_count;
    printf("Cosine similarity verification passed!\n");
    printf("Average difference: %.9f\n", avg_cosine_diff);
    printf("Maximum difference: %.9f (%.6f%%)\n", max_cosine_diff, max_cosine_percent_diff);
    printf("Tolerance: %.6f%%\n\n", MAX_PERCENT_DIFF);
*/
/*
    printf("Verifying inner product implementations...\n");
    for (int i = 0; i < NUM_VECTORS; i++) {
        float neon_result = VectorInnerProductNEON(DIM, &vectors[i * DIM], query_vec);
        float simple_result = VectorInnerProductSimple(DIM, &vectors[i * DIM], query_vec);

        if (!float_within_tolerance(neon_result, simple_result)) {
            float abs_diff = fabsf(neon_result - simple_result);
            float percent_diff = (abs_diff / fabsf(simple_result)) * 100.0f;
            printf("Inner product mismatch at vector %d:\n", i);
            printf("  NEON:    %f\n", neon_result);
            printf("  Simple:  %f\n", simple_result);
            printf("  Diff:    %f (%.6f%%)\n", abs_diff, percent_diff);
            printf("  Max allowed diff: %.6f%%\n", MAX_PERCENT_DIFF);
            results_match = false;
            break;
        }
    }

    if (!results_match) {
        printf("\nERROR: Inner product implementations produce different results!\n");
        free(vectors);
        free(query_vec);
        return 1;
    }
    printf("Inner product verification passed!\n\n");
*/

    /* Warm up */
    for (int i = 0; i < 10; i++) {
        VectorL2SquaredDistanceNEON(DIM, &vectors[i * DIM], query_vec);
        VectorL2SquaredDistanceSimple(DIM, &vectors[i * DIM], query_vec);
        VectorInnerProductNEON(DIM, &vectors[i * DIM], query_vec);
        VectorInnerProductSimple(DIM, &vectors[i * DIM], query_vec);
        VectorCosineSimilarityNEON(DIM, &vectors[i * DIM], query_vec);
        VectorCosineSimilarity(DIM, &vectors[i * DIM], query_vec);
    }

    /* Benchmark L2 distance implementations */
    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_neon_l2 += VectorL2SquaredDistanceNEON(DIM, &vectors[i * DIM], query_vec);
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

    /* Benchmark inner product implementations */
    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_neon_ip += VectorInnerProductNEON(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    neon_ip_time = end_time - start_time;

    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_simple_ip += VectorInnerProductSimple(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    simple_ip_time = end_time - start_time;

    /* Benchmark cosine similarity implementations */
    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_neon_cosine += VectorCosineSimilarityNEON(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    neon_cosine_time = end_time - start_time;

    start_time = get_time_us();
    for (int iter = 0; iter < NUM_ITERATIONS; iter++) {
        for (int i = 0; i < NUM_VECTORS; i++) {
            total_simple_cosine += VectorCosineSimilarity(DIM, &vectors[i * DIM], query_vec);
        }
    }
    end_time = get_time_us();
    simple_cosine_time = end_time - start_time;

    printf("Benchmark Results:\n");
    printf("-----------------\n");
    printf("Vector dimension: %d\n", DIM);
    printf("Number of vectors: %d\n", NUM_VECTORS);
    printf("Number of iterations: %d\n", NUM_ITERATIONS);

    printf("\nL2 Distance:\n");
    printf("NEON Implementation:\n");
    printf("  Total time: %.2f ms\n", neon_l2_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)neon_l2_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total distance sum: %f\n", total_neon_l2);
    printf("\nSimple Implementation:\n");
    printf("  Total time: %.2f ms\n", simple_l2_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)simple_l2_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total distance sum: %f\n", total_simple_l2);
    printf("\nL2 Distance Speedup: %.2fx\n", (float)simple_l2_time / neon_l2_time);

    printf("\nInner Product:\n");
    printf("NEON Implementation:\n");
    printf("  Total time: %.2f ms\n", neon_ip_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)neon_ip_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total product sum: %f\n", total_neon_ip);
    printf("\nSimple Implementation:\n");
    printf("  Total time: %.2f ms\n", simple_ip_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)simple_ip_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total product sum: %f\n", total_simple_ip);
    printf("\nInner Product Speedup: %.2fx\n", (float)simple_ip_time / neon_ip_time);

    printf("\nCosine Similarity:\n");
    printf("NEON Implementation:\n");
    printf("  Total time: %.2f ms\n", neon_cosine_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)neon_cosine_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total similarity sum: %f\n", total_neon_cosine);
    printf("\nSimple Implementation:\n");
    printf("  Total time: %.2f ms\n", simple_cosine_time / 1000.0);
    printf("  Average time per vector: %.3f us\n", (float)simple_cosine_time / (NUM_VECTORS * NUM_ITERATIONS));
    printf("  Total similarity sum: %f\n", total_simple_cosine);
    printf("\nCosine Similarity Speedup: %.2fx\n", (float)simple_cosine_time / neon_cosine_time);

    free(vectors);
    free(query_vec);

    return 0;
}