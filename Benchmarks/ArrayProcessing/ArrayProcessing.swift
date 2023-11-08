import Benchmark
import Gen

struct Datas {
    private let datas: [[Int]]
    private var currentDataIndex = -1

    init(size: Int) {
        precondition(0 < size, "'size' of the test Datas must be one or more.")

        var datas = [[Int]]()

        let count = size / MemoryLayout<Int>.size

        for i in 0..<2 {
            datas.append(Array(unsafeUninitializedCapacity: count) { buffer, initialisedCount in
                var prng = Xoshiro(seed: UInt64(exactly: i)!)

                for i in 0..<count {
                    buffer[i] = Int.random(in: Int.min...Int.max, using: &prng)
                }

                initialisedCount = count
            })
        }

        self.datas = datas
    }

    var next: [Int] {
        mutating get {
            currentDataIndex = (currentDataIndex + 1) % datas.count
            return datas[currentDataIndex]
        }
    }
}

let benchmarks = {
    Benchmark.defaultConfiguration = .init(metrics: [.cpuTotal,
                                                     .wallClock,
                                                     .peakMemoryResident,
                                                     .mallocCountTotal,
                                                     .allocatedResidentMemory,
                                                     .retainCount,
                                                     .releaseCount],
                                           maxDuration: .seconds(30),
                                           maxIterations: 100)

    for (dataSize, dataSizeLabel) in [
        // Have to provide bespoke labels, rather than using e.g. (1 << dataSize).formatted(.byteCount(style: .binary)), because said formatter is broken (it uses decimal labels, e.g. "kB", rather than binary ones).
        (0, "Empty collection"),  // Empty array.  Looks at the baseline overhead.
        (15, "32 KiB"),           // Fits into L1 cache.
        (19, "512 KiB"),          // Probably doesn't fit into L1, but should fit into L2.
        (23, "8 MiB"),            // Probably doesn't fit into L2, but should fit into L3 (if present).
        (28, "256 MiB")           // Probably doesn't fit into any CPU caches.
    ] {
        var testData = Datas(size: 1 << dataSize)

        Benchmark("[\(dataSizeLabel)] for-in loop") { benchmark in
            for _ in benchmark.scaledIterations {
                var result = 0

                for value in testData.next {
                    if 0 != value {
                        let value = value.byteSwapped

                        if (value & 0xff00) >> 8 < value & 0xff {
                            let value = value.leadingZeroBitCount

                            if Int.bitWidth - 8 >= value {
                                result &+= value
                            }
                        }
                    }
                }

                blackHole(result)
            }
        }

        Benchmark("[\(dataSizeLabel)] Filter, map, and reduce") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(testData.next
                    .filter { 0 != $0 }
                    .map { $0.byteSwapped }
                    .filter { ($0 & 0xff00) >> 8 < $0 & 0xff }
                    .map { $0.leadingZeroBitCount }
                    .filter { Int.bitWidth - 8 >= $0 }
                    .reduce(into: 0, &+=))
            }
        }

        Benchmark("[\(dataSizeLabel)] Filter, map, and reduce (lazily)") { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(testData.next
                    .lazy
                    .filter { 0 != $0 }
                    .map { $0.byteSwapped }
                    .filter { ($0 & 0xff00) >> 8 < $0 & 0xff }
                    .map { $0.leadingZeroBitCount }
                    .filter { Int.bitWidth - 8 >= $0 }
                    .reduce(into: 0) { (result, value) in
                        result &+= value
                    })
            }
        }
    }
}
