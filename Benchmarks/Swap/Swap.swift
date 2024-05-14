import Benchmark
import BigInt
import NBKFlexibleWidthKit

let benchmarks = {
    Benchmark.defaultConfiguration = .init(metrics: [.cpuTotal,
                                                     .wallClock,
                                                     .mallocCountTotal,
                                                     .retainCount,
                                                     .releaseCount],
                                           scalingFactor: .mega,
                                           maxDuration: .seconds(30),
                                           maxIterations: 100)

    let cycles = 1_000_000
    let updateRateInMilliseconds = 100

    Benchmark("Fibonnaci Integer (using temporary)") { benchmark in
        var previous = 0
        var current = 1

        for _ in benchmark.scaledIterations {
            let next = previous &+ current
            previous = current
            current = next
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci Integer (using swap)") { benchmark in
        var previous = 0
        var current = 1

        for _ in benchmark.scaledIterations {
            previous &+= current
            swap(&previous, &current)
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci Integer (using reduce(_:_:))") { benchmark in
        blackHole(benchmark.scaledIterations.reduce((0, 1)) { pair, _ in
            (pair.1, pair.1 &+ pair.0)
        })
    }

    Benchmark("Fibonnaci Integer (using reduce(into:_:))") { benchmark in
        blackHole(benchmark.scaledIterations.reduce(into: (0, 1)) { pair, _ in
            pair.0 &+= pair.1
            swap(&pair.0, &pair.1)
        })
    }

    Benchmark("Fibonnaci Array (using temporary)") { benchmark in
        var previous = [0, 0, 0, 0]
        var current = [1, 1, 1, 1]

        for _ in benchmark.scaledIterations {
            let next = zip(previous, current).map { $0 &+ $1 }
            previous = current
            current = next
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci Array (using swap)") { benchmark in
        var previous = [0, 0, 0, 0]
        var current = [1, 1, 1, 1]

        for _ in benchmark.scaledIterations {
            for i in previous.indices {
                previous[i] &+= current[i]
            }

            swap(&previous, &current)
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci Array (using reduce(_:_:))") { benchmark in
        blackHole(benchmark.scaledIterations.reduce(([0, 0, 0, 0], [1, 1, 1, 1])) { pair, _ in
            (pair.1, zip(pair.0, pair.1).map { $0 &+ $1 })
        })
    }

    Benchmark("Fibonnaci Array (using reduce(into:_:))") { benchmark in
        blackHole(benchmark.scaledIterations.reduce(into: ([0, 0, 0, 0], [1, 1, 1, 1])) { pair, _ in
            for i in pair.0.indices {
                pair.0[i] &+= pair.1[i]
            }
            
            swap(&pair.0, &pair.1)
        })
    }

    Benchmark("Incrementing Array (using temporary)") { benchmark in
        blackHole(sequence(first: [0, 0, 0, 0]) {
            $0.map { $0 &+ 1 }
        })
    }

    Benchmark("Incrementing Array (in place)") { benchmark in
        blackHole(sequence(state: [0, 0, 0, 0]) {
            for i in $0.indices {
                $0[i] &+= 1
            }
        })
    }

    Benchmark("Fibonnaci UIntXL (using temporary)") { benchmark in
        var previous = UIntXL(0)
        var current = UIntXL(1)

        for _ in 0 ..< (benchmark.scaledIterations.upperBound / 10) {
            let next = previous + current
            previous = current
            current = next
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci UIntXL (using swap)") { benchmark in
        var previous = UIntXL(0)
        var current = UIntXL(1)

        for _ in 0 ..< (benchmark.scaledIterations.upperBound / 10) {
            previous += current
            swap(&previous, &current)
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci UIntXL (using reduce(_:_:))") { benchmark in
        blackHole((0 ..< (benchmark.scaledIterations.upperBound / 10)).reduce((UIntXL(0), UIntXL(1))) { pair, _ in
            (pair.1, pair.1 + pair.0)
        })
    }

    Benchmark("Fibonnaci UIntXL (using reduce(into:_:))") { benchmark in
        blackHole((0 ..< (benchmark.scaledIterations.upperBound / 10)).reduce(into: (UIntXL(0), UIntXL(1))) { pair, _ in
            pair.0 += pair.1
            swap(&pair.0, &pair.1)
        })
    }

    Benchmark("Fibonnaci BigUInt (using temporary)") { benchmark in
        var previous = BigUInt(0)
        var current = BigUInt(1)

        for _ in 0 ..< (benchmark.scaledIterations.upperBound / 10) {
            let next = previous + current
            previous = current
            current = next
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci BigUInt (using swap)") { benchmark in
        var previous = BigUInt(0)
        var current = BigUInt(1)

        for _ in 0 ..< (benchmark.scaledIterations.upperBound / 10) {
            previous += current
            swap(&previous, &current)
        }

        blackHole(current)
    }

    Benchmark("Fibonnaci BigUInt (using reduce(_:_:))") { benchmark in
        blackHole((0 ..< (benchmark.scaledIterations.upperBound / 10)).reduce((BigUInt(0), BigUInt(1))) { pair, _ in
            (pair.1, pair.1 + pair.0)
        })
    }

    Benchmark("Fibonnaci BigUInt (using reduce(into:_:))") { benchmark in
        blackHole((0 ..< (benchmark.scaledIterations.upperBound / 10)).reduce(into: (BigUInt(0), BigUInt(1))) { pair, _ in
            pair.0 += pair.1
            swap(&pair.0, &pair.1)
        })
    }
}
