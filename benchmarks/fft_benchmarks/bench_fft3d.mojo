import endia as nd


def fft3d_benchmark():
    var torch = Python.import_module("torch")

    for n in range(4, 12):
        var width = 2 ** (n - 3)
        var height = 2**n
        var size = width * height
        print("Width: 2**", end="")
        print(n - 3, "=", width)
        print("Height: 2**", end="")
        print(n, "=", height)

        var x = nd.complex(
            nd.arange(0, size).reshape(List(width, height)),
            nd.arange(0, size).reshape(List(width, height)),
        )
        x_torch = torch.complex(
            torch.arange(0, size).float().reshape(width, height),
            torch.arange(0, size).float().reshape(width, height),
        )

        num_iterations = 20
        warmup = 5
        total = Float32(0)
        total_torch = Float32(0)

        for iteration in range(num_iterations + warmup):
            if iteration < warmup:
                total = 0
                total_torch = 0

            start = now()
            _ = nd.fft.fft2d(x)
            total += now() - start

            start = now()
            _ = torch.fft.fft2(x_torch)
            total_torch += now() - start

        my_time = total / (1000000000 * num_iterations)
        torch_time = total_torch / (1000000000 * num_iterations)
        print("Time taken:", my_time)
        print("Time taken Torch:", torch_time)
        print("Difference:", (torch_time - my_time) / torch_time * 100, "%")
        print()
