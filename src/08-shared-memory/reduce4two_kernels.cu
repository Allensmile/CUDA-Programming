#include "error.cuh"
#include <stdio.h>
#ifdef USE_DP
    typedef double real;
#else
    typedef float real;
#endif
#define NUM_ROUNDS 10

real reduce(real *x, int N);

int main(int argc, char **argv)
{
    int N = 100000000;
    int M = sizeof(real) * N;
    real *h_x = (real *)malloc(M);
    for (int n = 0; n < N; ++n) { h_x[n] = 1.0; }
    real *x;
    CHECK(cudaMalloc(&x, M))
    CHECK(cudaMemcpy(x, h_x, M, cudaMemcpyHostToDevice))

    real sum = reduce(x, N);
    printf("sum = %f.\n", sum);

    free(h_x);
    CHECK(cudaFree(x))
    return 0;
}

void __global__ reduce_1(real *g_x, real *g_y, int N)
{
    int tid = threadIdx.x;
    int bid = blockIdx.x;
    __shared__ real s_y[128];

    real y = 0.0;
    int offset = tid + bid * blockDim.x * NUM_ROUNDS;
    for (int round = 0; round < NUM_ROUNDS; ++round)
    {
        int n = round * blockDim.x + offset;
        if (n < N) { y += g_x[n]; }
    }
    s_y[tid] = y;

    for (int offset = blockDim.x >> 1; offset > 0; offset >>= 1)
    {
        __syncthreads();
        if (tid < offset) { s_y[tid] += s_y[tid + offset]; }
    }

    if (tid == 0) { g_y[bid] = s_y[0]; }
}

void __global__ reduce_2 
(real *g_x, real *g_sum, int N, int number_of_rounds)
{
    int tid = threadIdx.x;
    __shared__ real s_sum[1024];
    real tmp_sum = 0.0;
    for (int round = 0; round < number_of_rounds; ++round)
    {
        int n = tid + round * 1024;
        if (n < N) { tmp_sum += g_x[n]; }
    }
    s_sum[tid] = tmp_sum;

    for (int offset = blockDim.x >> 1; offset > 0; offset >>= 1)
    {
        __syncthreads();
        if (tid < offset) { s_sum[tid] += s_sum[tid + offset]; }
    }
    
    if (tid == 0) { g_sum[0] = s_sum[0]; }
}

real reduce(real *x, int N)
{
    const int block_size = 128;
    int grid_size = (N - 1) / (block_size * NUM_ROUNDS) + 1;
    int number_of_rounds = (grid_size - 1) / 1024 + 1;

    real *y, *sum;
    CHECK(cudaMalloc(&y, sizeof(real) * grid_size))
    CHECK(cudaMalloc(&sum, sizeof(real)))

    reduce_1<<<grid_size, block_size>>>(x, y, N);
    reduce_2<<<1, 1024>>>(y, sum, grid_size, number_of_rounds);

    real *h_sum = (real *)malloc(sizeof(real));
    CHECK(cudaMemcpy(h_sum, sum, sizeof(real), 
        cudaMemcpyDeviceToHost))
    real result = h_sum[0];

    free(h_sum);
    CHECK(cudaFree(y))
    CHECK(cudaFree(sum))
    return result;
}

