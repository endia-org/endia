import endia as nd
from python import Python


def run_test_reduce_argmin(msg: String = "reduce_argmin"):
    torch = Python.import_module("torch")
    arr = nd.randu(List(2, 30, 40))
    arr_torch = nd.utils.to_torch(arr)

    axis = 1  # Note: In PyTorch we can only call min and argmin along a single dimension at a time!

    res = nd.reduce_argmin(arr, axis)
    res_torch = torch.argmin(arr_torch, dim=axis)

    if not nd.utils.is_close(res, res_torch):
        print("\033[31mTest failed\033[0m", msg)
    else:
        print("\033[32mTest passed\033[0m", msg)