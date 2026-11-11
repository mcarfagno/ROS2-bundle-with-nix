#include <cuda_runtime.h>

#include "my_awesome_cuda/vector_add.hpp"

__global__ void add(const int *a, const int *b, int *c, int n) {
  int i = blockIdx.x * blockDim.x + threadIdx.x;
  if (i < n) {
    c[i] = a[i] + b[i];
  }
}

long vector_add(int n) {
  int *a, *b, *c;
  // Jetson CPU and GPU share memory, so managed memory keeps this short
  if (cudaMallocManaged(&a, n * sizeof(int)) != cudaSuccess) {
    return -1;
  }
  cudaMallocManaged(&b, n * sizeof(int));
  cudaMallocManaged(&c, n * sizeof(int));

  for (int i = 0; i < n; i++) {
    a[i] = i;
    b[i] = i;
  }

  add<<<(n + 255) / 256, 256>>>(a, b, c, n);
  long sum = -1;
  if (cudaDeviceSynchronize() == cudaSuccess) {
    sum = 0;
    for (int i = 0; i < n; i++) {
      sum += c[i];
    }
  }

  cudaFree(a);
  cudaFree(b);
  cudaFree(c);
  return sum;
}

std::string device_name() {
  cudaDeviceProp prop;
  if (cudaGetDeviceProperties(&prop, 0) != cudaSuccess) {
    return "no CUDA device";
  }
  return prop.name;
}
