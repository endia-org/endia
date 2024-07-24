from endia import Array
from endia.utils import array_shape_to_list, list_to_array_shape, concat_lists
from endia.utils.aliases import dtype, nelts, NA
from algorithm import vectorize, parallelize
import math
from endia.functional._utils import (
    setup_shape_and_data,
)
from endia.functional._utils import setup_array_shape, contiguous, op_array


struct AvgPool2d:
    """
    Namespace for 2D average pooling operations.
    """

    @staticmethod
    fn compute_shape(inout curr: ArrayShape, args: List[ArrayShape]) raises:
        """
        Computes the shape of an array after a 2-dimensional average pooling operation with dilation.
        """
        var arg = args[0]  # Input tensor
        var params = array_shape_to_list(args[1])  # Pooling parameters

        var input_shape = arg.shape_node[].shape
        var ndim = len(input_shape)
        if ndim != 4:
            raise "Input must be 4-dimensional (batch_size, channels, height, width) for 2D pooling!"

        var batch_size = input_shape[0]
        var channels = input_shape[1]
        var kernel_height = params[0]
        var kernel_width = params[1]
        var stride_height = params[2]
        var stride_width = params[3]
        var padding_height = params[4]
        var padding_width = params[5]
        var dilation_height = params[6]
        var dilation_width = params[7]

        var new_shape = List[Int]()
        new_shape.append(batch_size)
        new_shape.append(channels)
        new_shape.append(
            (input_shape[2] + 2 * padding_height - dilation_height * (kernel_height - 1) - 1) // stride_height + 1
        )
        new_shape.append(
            (input_shape[3] + 2 * padding_width - dilation_width * (kernel_width - 1) - 1) // stride_width + 1
        )
        curr.setup(new_shape)

    @staticmethod
    fn __call__(inout curr: Array, args: List[Array]) raises:
        var params = array_shape_to_list(curr.array_shape().args()[1])

        setup_shape_and_data(curr)

        var kernel_height = params[0]
        var kernel_width = params[1]
        var stride_height = params[2]
        var stride_width = params[3]
        var padding_height = params[4]
        var padding_width = params[5]
        var dilation_height = params[6]
        var dilation_width = params[7]

        var input = contiguous(args[0])

        var out = curr
        var out_shape = out.shape()
        var out_data = out.data()
        var input_data = input.data()

        var out_stride = out.stride()
        var input_stride = input.stride()
        var input_shape = input.shape()

        for batch in range(out_shape[0]):
            for channel in range(out_shape[1]):
                for out_y in range(out_shape[2]):
                    for out_x in range(out_shape[3]):
                        var start_y = out_y * stride_height - padding_height
                        var start_x = out_x * stride_width - padding_width
                        var sum_val = SIMD[dtype, 1](0)
                        var count = 0
                        
                        for ky in range(kernel_height):
                            var y = start_y + ky * dilation_height
                            if y >= 0 and y < input_shape[2]:
                                for kx in range(kernel_width):
                                    var x = start_x + kx * dilation_width
                                    if x >= 0 and x < input_shape[3]:
                                        var idx = batch * input_stride[0] + channel * input_stride[1] + y * input_stride[2] + x * input_stride[3]
                                        sum_val += input_data.load(idx)
                                        count += 1

                        var out_idx = batch * out_stride[0] + channel * out_stride[1] + out_y * out_stride[2] + out_x * out_stride[3]
                        out_data.store(out_idx, sum_val / count if count > 0 else SIMD[dtype, 1](0))

    @staticmethod
    fn vjp(primals: List[Array], grad: Array, out: Array) raises -> List[Array]:
        return default_vjp(primals, grad, out)

    @staticmethod
    fn jvp(primals: List[Array], tangents: List[Array]) raises -> Array:
        return default_jvp(primals, tangents)

    @staticmethod
    fn fwd(
        arg0: Array,
        kernel_size: Tuple[Int, Int],
        stride: Tuple[Int, Int] = (1, 1),
        padding: Tuple[Int, Int] = (0, 0),
        dilation: Tuple[Int, Int] = (1, 1),
    ) raises -> Array:
        var arr_shape = setup_array_shape(
            List(
                arg0.array_shape(),
                list_to_array_shape(
                    concat_lists(
                        kernel_size[0],
                        kernel_size[1],
                        stride[0],
                        stride[1],
                        padding[0],
                        padding[1],
                        dilation[0],
                        dilation[1],
                    )
                ),
            ),
            "avg_pool2d_shape",
            AvgPool2d.compute_shape,
        )

        var args = List(arg0)

        return op_array(arr_shape, args, NA, "avg_pool2d", AvgPool2d.__call__, AvgPool2d.jvp, AvgPool2d.vjp, False)

fn avg_pool2d(
    arg0: Array,
    kernel_size: Tuple[Int, Int],
    stride: Tuple[Int, Int] = (1, 1),
    padding: Tuple[Int, Int] = (0, 0),
    dilation: Tuple[Int, Int] = (1, 1),
) raises -> Array:
    """
    Applies a 2D average pooling operation over an input array.

    Args:
        arg0: The input array.
        kernel_size: The size of the kernel (height, width).
        stride: The stride of the pooling operation. Defaults to (1, 1).
        padding: The padding to apply to the input. Defaults to (0, 0).
        dilation: The dilation to apply to the input. Defaults to (1, 1).

    Returns:
        Array: The output array.
    """
    return AvgPool2d.fwd(arg0, kernel_size, stride, padding, dilation)