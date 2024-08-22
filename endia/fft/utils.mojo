# ===----------------------------------------------------------------------=== #
# Endia 2024
#
# Licensed under the Apache License v2.0 with LLVM Exceptions:
# https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #


import math
from algorithm import parallelize
from memory import memcpy
from sys import num_physical_cores

import endia as nd

alias pi = Float64(3.141592653589793)  # Maximum useful precision for Float64


fn reverse_bits_simd(
    x: SIMD[DType.uint32, nd.nelts[DType.uint32]()]
) -> SIMD[DType.uint32, nd.nelts[DType.uint32]()]:
    """
    Reverse the bits of a 32-bit integer.
    """
    var y = x
    y = ((y >> 1) & 0x55555555) | ((y & 0x55555555) << 1)
    y = ((y >> 2) & 0x33333333) | ((y & 0x33333333) << 2)
    y = ((y >> 4) & 0x0F0F0F0F) | ((y & 0x0F0F0F0F) << 4)
    y = ((y >> 8) & 0x00FF00FF) | ((y & 0x00FF00FF) << 8)
    return (y >> 16) | (y << 16)


@always_inline
fn bit_reversal(
    n: Int, reordered_arr_data: UnsafePointer[Scalar[DType.uint32]]
):
    """
    Generate a bit reversal permutation for integers from 0 to n-1.
    Works for any positive integer n.
    """
    var log2_n = int(math.ceil(math.log2(Float32(n))))
    var n_pow2 = 1 << log2_n

    var u = SIMD[DType.uint32, nd.nelts[DType.uint32]()]()
    for i in range(nd.nelts[DType.uint32]()):
        u[i] = SIMD[DType.uint32, 1](i)

    for i in range(0, n_pow2, nd.nelts[DType.uint32]()):
        var x = u + i
        var reversed = reverse_bits_simd(x) >> (32 - log2_n)

        # Only store if within original n
        if i < n:
            var to_store = reversed.cast[DType.uint32]()
            if i + 15 < n:
                reordered_arr_data.store[width = nd.nelts[DType.uint32]()](
                    i, to_store
                )
            else:
                for j in range(nd.nelts[DType.uint32]()):
                    if i + j < n:
                        reordered_arr_data.store(i + j, to_store[j])


@always_inline
fn cooley_tukey_split(
    n: Int, max_depth: Int, res_data: UnsafePointer[Scalar[DType.float64]]
):
    """
    Non-recursive Cooley-Tukey FFT splitting of the input data with a limited depth.
    """

    # Non-recursive Cooley-Tukey FFT splitting of the input data
    for iteration in range(max_depth):
        var subarray_size = n // (2**iteration)
        var num_subarrays = 2**iteration
        var temp = UnsafePointer[Scalar[DType.float64]].alloc(subarray_size * 2)

        # Split each subarray into even and odd indices
        for subarray in range(num_subarrays):
            var start = subarray * subarray_size
            var end = start + subarray_size
            var even_index = 0
            var odd_index = subarray_size // 2

            for i in range(start, end):
                if (i - start) % 2 == 0:
                    temp.store[width=2](
                        2 * even_index, res_data.load[width=2](2 * i)
                    )
                    even_index += 1
                else:
                    temp.store[width=2](
                        2 * odd_index, res_data.load[width=2](2 * i)
                    )
                    odd_index += 1

            for i in range(subarray_size):
                res_data.store(2 * (start + i), temp[2 * i])
                res_data.store(2 * (start + i) + 1, temp[2 * i + 1])

        # Free the temporary buffer
        temp.free()


@always_inline
fn cooley_tukey_recombine(
    n: Int, start_depth: Int, res_data: UnsafePointer[Scalar[DType.float64]]
):
    """
    Non-recursive Cooley-Tukey FFT recombination of the subsolutions. The recombination starts at a given depth.
    """
    # Allocate temporary buffers
    var temp = UnsafePointer[Scalar[DType.float64]].alloc(n * 2)
    var even = UnsafePointer[Scalar[DType.float64]].alloc(n)
    var odd = UnsafePointer[Scalar[DType.float64]].alloc(n)
    var T = UnsafePointer[Scalar[DType.float64]].alloc(n)
    var twiddle_factors = UnsafePointer[Scalar[DType.float64]].alloc(n)

    # Non-recursive Cooley-Tukey FFT recombination of the subsolutions
    for iteration in range(start_depth - 1, -1, -1):
        var subarray_size = n // (2**iteration)
        var num_subarrays = 2**iteration

        for k in range(subarray_size // 2):
            var p = (-2 * pi / subarray_size) * k
            twiddle_factors.store[width=2](
                2 * k, SIMD[DType.float64, 2](math.cos(p), math.sin(p))
            )

        for subarray in range(num_subarrays):
            var start = subarray * subarray_size
            var mid = start + subarray_size // 2

            for k in range(subarray_size // 2):
                var k_times_2 = 2 * k
                var k_times_2_plus_1 = k_times_2 + 1
                even.store[width=2](
                    k_times_2, res_data.load[width=2](2 * (start + k))
                )
                odd.store[width=2](
                    k_times_2, res_data.load[width=2](2 * (mid + k))
                )
                var twiddle_factor = twiddle_factors.load[width=2](k_times_2)
                T.store(
                    k_times_2,
                    twiddle_factor[0] * odd[k_times_2]
                    - twiddle_factor[1] * odd[k_times_2_plus_1],
                )
                T.store(
                    k_times_2_plus_1,
                    twiddle_factor[0] * odd[k_times_2_plus_1]
                    + twiddle_factor[1] * odd[k_times_2],
                )
                temp.store[width=2](
                    2 * (start + k),
                    even.load[width=2](k_times_2) + T.load[width=2](k_times_2),
                )
                temp.store[width=2](
                    2 * (mid + k),
                    even.load[width=2](k_times_2) - T.load[width=2](k_times_2),
                )

        memcpy(res_data, temp, n * 2)

    # Free the temporary buffers
    even.free()
    odd.free()
    T.free()
    twiddle_factors.free()
    temp.free()


@always_inline
fn cooley_tukey_with_bit_reversal(
    workload: Int,
    data: UnsafePointer[Scalar[DType.float64]],
    reordered_arr_data: UnsafePointer[Scalar[DType.uint32]],
):
    """
    Iterative fast Fourier transform using the Cooley-Tukey algorithm with bit-reversal permutation.
    """
    # permute x according to the bit-reversal permutation
    for i in range(workload):
        var j = int(reordered_arr_data.load(i))
        if i < j:
            var tmp = data.load[width=2](2 * i)
            data.store[width=2](2 * i, data.load[width=2](2 * j))
            data.store[width=2](2 * j, tmp)

    # Cooley-Tukey FFT
    var m = 2
    while m <= workload:
        var u = SIMD[DType.float64, 2](1.0, 0.0)
        var angle = -2 * pi / m
        var w_real = math.cos(angle)
        var w_imag = math.sin(angle)

        for k in range(0, m // 2):
            for j in range(k, workload, m):
                var j_2 = 2 * j
                var j_2_plus_m = j_2 + m

                var z = data.load[width=2](j_2)
                var d = data.load[width=2](j_2_plus_m)
                var t = SIMD[DType.float64, 2](
                    u[0] * d[0] - u[1] * d[1], u[0] * d[1] + u[1] * d[0]
                )
                data.store[width=2](j_2_plus_m, z - t)
                data.store[width=2](j_2, z + t)

            # Update u for the next iteration
            u = SIMD[DType.float64, 2](
                u[0] * w_real - u[1] * w_imag, u[0] * w_imag + u[1] * w_real
            )

        m *= 2


fn copy_complex_and_cast[
    dst_type: DType, src_type: DType
](
    dst: UnsafePointer[Scalar[dst_type]],
    src: UnsafePointer[Scalar[src_type]],
    size: Int,
    conjugate_and_divide: Bool = False,
    divisor: SIMD[dst_type, 1] = 1,
):
    """
    Copy complex data from one buffer to another and cast the data to a different type. Optionally conjugate and divide by a scalar (usefule for inverse FFT).
    """
    if conjugate_and_divide:
        for i in range(size):
            dst.store(2 * i, src.load(2 * i).cast[dst_type]() / divisor)
            dst.store(
                2 * i + 1, -src.load(2 * i + 1).cast[dst_type]() / divisor
            )
    else:
        for i in range(size):
            dst.store[width=2](2 * i, src.load[width=2](2 * i).cast[dst_type]())


fn setup_input(input: nd.Array) raises -> nd.Array:
    """
    Checks the input and prepares it for the FFT, i.e. makes it complex if it is not and reshapes it to a one-dimensional contiguous array.
    """

    # only power of two inputs are supported
    if (input.shape()[-1] & (input.shape()[-1] - 1)) != 0:
        raise "Input size must be a power of two"

    # Setup parameters and data buffers
    var x = input
    var copied = False

    # make x complex if it is not
    if not input.is_complex():
        x = nd.complex(input, nd.zeros_like(input))
        copied = True

    # make x one dimensional adn contiguous
    x = input.reshape(x.size())
    if not copied:
        x = nd.copy(x)

    return x


fn fft_c(
    input: nd.Array, divisions: Int = 1, perform_inverse: Bool = False
) raises -> nd.Array:
    """
    Perform a one-dimensional FFT/IFFT on the input data and returns a new array with the result.
    """
    # setup input array and parameters
    var x = setup_input(input)
    var n = x.size()
    if n == 1:
        return x
    var parallelize_threshold = 2**14
    var num_workers = num_physical_cores() if n >= parallelize_threshold else 1
    var workload = (n // num_workers) if (divisions == 1) else (n // divisions)
    var h = (int(math.log2(Float32(n // workload)))) if divisions == 1 else 0
    var number_subtasks = num_workers if divisions == 1 else divisions
    var data = x.data()
    var res_data = UnsafePointer[Scalar[DType.float64]].alloc(n * 2)
    copy_complex_and_cast(res_data, data, n, perform_inverse)

    # Split the data into individual subarrays to perform #workload indipendent FFTs
    if h > 0:
        cooley_tukey_split(n, h, res_data)

    # Prepare the bit-reversal permutation
    var reordered_arr_data = UnsafePointer[Scalar[DType.uint32]].alloc(workload)
    bit_reversal(workload, reordered_arr_data)

    # define
    @parameter
    fn perform_cooley_tukey_sequencial(i: Int) capturing:
        var data = UnsafePointer[Scalar[DType.float64]].alloc(2 * workload)
        for j in range(2 * workload):
            data.store(j, res_data.load(2 * i * workload + j))

        cooley_tukey_with_bit_reversal(workload, data, reordered_arr_data)
        memcpy(res_data.offset(2 * i * workload), data, 2 * workload)
        data.free()

    parallelize[perform_cooley_tukey_sequencial](number_subtasks, num_workers)
    _ = workload, divisions
    reordered_arr_data.free()

    # Recombine the data of the subarrays if necessary
    if h > 0:
        cooley_tukey_recombine(n, h, res_data)

    # Cast the data back to the original type and return the result
    var result = nd.Array(List(n), is_complex=True)
    var data_orig = result.data()
    copy_complex_and_cast(data_orig, res_data, n, perform_inverse, workload)
    res_data.free()
    return result.reshape(input.shape())
