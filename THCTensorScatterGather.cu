#include "THCTensorMath.h"
#include "THCGeneral.h"
#include "THCApply.cuh"

// Compute the offsets into the given tensors for a linear index. For the 't2'
// tensor, dimension 'dim' is skipped. The tensors are assumed to have the same
// size (with the exception of 't2' in dimension 'dim').
// This version uses a static number of dimensions.
template <typename IndexType, typename real, int Dims>
struct IndexToScatterGatherOffsets {
  static __device__ void compute(
      IndexType linearId, const int dim,
      const TensorInfo<long, IndexType>& index, IndexType* indexOffset,
      const TensorInfo<real, IndexType>& t1, IndexType* t1Offset,
      const TensorInfo<real, IndexType>& t2, IndexType* t2Offset) {
    for (int d = Dims - 1; d >= 0; d--) {
      IndexType curDimIndex = linearId % index.sizes[d];
      *indexOffset += curDimIndex * index.strides[d];
      *t1Offset += curDimIndex * t1.strides[d];
      if (d != dim) {
        *t2Offset += curDimIndex * t2.strides[d];
      }
      linearId /= index.sizes[d];
    }
  }

  static __device__ void compute(
      IndexType linearId, const int dim,
      const TensorInfo<long, IndexType>& index, IndexType* indexOffset,
      const TensorInfo<real, IndexType>& t2, IndexType* t2Offset) {
    for (int d = Dims - 1; d >= 0; d--) {
      IndexType curDimIndex = linearId % index.sizes[d];
      *indexOffset += curDimIndex * index.strides[d];
      if (d != dim) {
        *t2Offset += curDimIndex * t2.strides[d];
      }
      linearId /= index.sizes[d];
    }
  }
};

// Same as above but using a dynamic number of dimensions.
template <typename IndexType, typename real>
struct IndexToScatterGatherOffsets<IndexType, real, -1> {
  static __device__ void compute(
      IndexType linearId, const int dim,
      const TensorInfo<long, IndexType>& index, IndexType* indexOffset,
      const TensorInfo<real, IndexType>& t1, IndexType* t1Offset,
      const TensorInfo<real, IndexType>& t2, IndexType* t2Offset) {
    for (int d = index.dims - 1; d >= 0; d--) {
      IndexType curDimIndex = linearId % index.sizes[d];
      *indexOffset += curDimIndex * index.strides[d];
      *t1Offset += curDimIndex * t1.strides[d];
      if (d != dim) {
        *t2Offset += curDimIndex * t2.strides[d];
      }
      linearId /= index.sizes[d];
    }
  }

  static __device__ void compute(
      IndexType linearId, const int dim,
      const TensorInfo<long, IndexType>& index, IndexType* indexOffset,
      const TensorInfo<real, IndexType>& t2, IndexType* t2Offset) {
    for (int d = index.dims - 1; d >= 0; d--) {
      IndexType curDimIndex = linearId % index.sizes[d];
      *indexOffset += curDimIndex * index.strides[d];
      if (d != dim) {
        *t2Offset += curDimIndex * t2.strides[d];
      }
      linearId /= index.sizes[d];
    }
  }
};

template <typename IndexType, typename real, int Dims>
__global__ void THCudaTensor_gatherKernel(
    TensorInfo<real, IndexType> tensor,
    TensorInfo<real, IndexType> src,
    TensorInfo<long, IndexType> index,
    const int dim,
    const IndexType totalElements) {
  for (IndexType linearId = blockIdx.x * blockDim.x + threadIdx.x;
       linearId < totalElements;
       linearId += gridDim.x * blockDim.x) {
    IndexType tensorOffset = 0;
    IndexType srcOffset = 0;
    IndexType indexOffset = 0;

    IndexToScatterGatherOffsets<IndexType, real, Dims>::compute(linearId, dim,
                                                          index, &indexOffset,
                                                          tensor, &tensorOffset,
                                                          src, &srcOffset);

    IndexType indexValue = (IndexType)index.data[indexOffset] - 1;
    srcOffset += indexValue * src.strides[dim];

    tensor.data[tensorOffset] = src.data[srcOffset];
  }
}

template <typename IndexType, typename real, int Dims>
__global__ void THCudaTensor_scatterKernel(
    TensorInfo<real, IndexType> tensor,
    TensorInfo<real, IndexType> src,
    TensorInfo<long, IndexType> index,
    const int dim,
    const IndexType totalElements) {
  for (IndexType linearId = blockIdx.x * blockDim.x + threadIdx.x;
       linearId < totalElements;
       linearId += gridDim.x * blockDim.x) {
    IndexType tensorOffset = 0;
    IndexType srcOffset = 0;
    IndexType indexOffset = 0;

    IndexToScatterGatherOffsets<IndexType, real, Dims>::compute(linearId, dim,
                                                          index, &indexOffset,
                                                          src, &srcOffset,
                                                          tensor, &tensorOffset);

    IndexType indexValue = (IndexType)index.data[indexOffset] - 1;
    tensorOffset += indexValue * tensor.strides[dim];

    tensor.data[tensorOffset] = src.data[srcOffset];
  }
}

template <typename IndexType, typename real, int Dims>
__global__ void THCudaTensor_scatterFillKernel(
    TensorInfo<real, IndexType> tensor,
    TensorInfo<long, IndexType> index,
    real value,
    const int dim,
    const IndexType totalElements) {
  for (IndexType linearId = blockIdx.x * blockDim.x + threadIdx.x;
       linearId < totalElements;
       linearId += gridDim.x * blockDim.x) {
    IndexType tensorOffset = 0;
    IndexType indexOffset = 0;

    IndexToScatterGatherOffsets<IndexType, real, Dims>::compute(linearId, dim,
                                                          index, &indexOffset,
                                                          tensor, &tensorOffset);

    IndexType indexValue = (IndexType)index.data[indexOffset] - 1;
    tensorOffset += indexValue * tensor.strides[dim];

    tensor.data[tensorOffset] = value;
  }
}

#include "generic/THCTensorScatterGather.cu"
#include "THCGenerateAllTypes.h"
