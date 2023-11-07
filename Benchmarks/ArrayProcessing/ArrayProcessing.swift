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

@inlinable
@inline(__always)
func filter1(_ value: Int) -> Bool {
    0 == value % 2
}

@inlinable
@inline(__always)
func map1(_ value: Int) -> Int {
    value.byteSwapped
}

@inlinable
@inline(__always)
func filter2(_ value: Int) -> Bool {
    (value & 0xff00) >> 8 < value & 0xff
}

@inlinable
@inline(__always)
func map2(_ value: Int) -> String {
    value.description
}

@inlinable
@inline(__always)
func filter3(_ value: String) -> Bool {
    3 < value.count
}

let benchmarks = {
    Benchmark.defaultConfiguration = .init(maxDuration: .seconds(60),
                                           maxIterations: 100)

    Benchmark("for-in loop") { benchmark in
        for _ in benchmark.scaledIterations {
            var matchCount = 0

            for value in testData.next {
                if filter1(value) {
                    let value = map1(value)

                    if filter2(value) {
                        let value = map2(value)

                        if filter3(value) {
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
                .filter { filter1($0) }
                .map { map1($0) }
                .filter { filter2($0) }
                .map { map2($0) }
                .filter { filter3($0) }
                .count)
        }
    }
}
