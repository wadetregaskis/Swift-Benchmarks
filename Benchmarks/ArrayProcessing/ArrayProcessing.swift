import Benchmark
import Gen

struct Datas {
    let size: Int

    private lazy var datas: [[Int]] = {
        return Array(unsafeUninitializedCapacity: 2) { buffer, initialisedCount in
            let count = size / MemoryLayout<Int>.size

            for i in 0..<2 {
                buffer[i] = Array(unsafeUninitializedCapacity: count) { buffer, initialisedCount in
                    var prng = Xoshiro(seed: UInt64(exactly: i)!)

                    for i in 0..<count {
                        buffer[i] = Gen.int(in: Int.min...Int.max).run(using: &prng)
                    }

                    initialisedCount = count
                }
            }

            initialisedCount = 2
        }
    }()

    private var currentDataIndex = -1

    init(size: Int) {
        precondition(0 < size, "'size' of the test Datas must be one or more.")
        self.size = size
    }

    var next: [Int] {
        mutating get {
            currentDataIndex = (currentDataIndex + 1) % datas.count
            return datas[currentDataIndex]
        }
    }
}

var testData = Datas(size: 1 << 12)

let benchmarks = {
    Benchmark.defaultConfiguration = .init(maxDuration: .seconds(60),
                                           maxIterations: 100)

    Benchmark("for-in loop") { benchmark in
        for _ in benchmark.scaledIterations {
            var matchCount = 0

            for value in testData.next {
                if 0 == value % 2 {
                    let value = value.byteSwapped

                    if (value & 0xff00) >> 8 < value & 0xff {
                        let value = value.description

                        if value.count > 3 {
                            matchCount &+= 1
                        }
                    }
                }
            }

            blackHole(matchCount)
        }
    }

    Benchmark("Filter, map, and count") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(testData.next
                .filter { 0 == $0 % 2 }
                .map { $0.byteSwapped }
                .filter { ($0 & 0xff00) >> 8 < $0 & 0xff }
                .map(\.description)
                .filter { $0.count > 3 }
                .count)
        }
    }
}
