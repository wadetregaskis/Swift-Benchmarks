import Benchmark
import Foundation
import FoundationExtensions
import Gen

let testFileSize = 128 * 1024 * 1024 // 128 MiB

let benchmarks = {
    Benchmark.defaultConfiguration = .init(metrics: [.cpuTotal,
                                                     .wallClock,
                                                     .peakMemoryResident,
                                                     .readBytesLogical,
                                                     .syscalls,
                                                     .mallocCountTotal,
                                                     .retainCount,
                                                     .releaseCount],
                                           maxDuration: .seconds(30),
                                           maxIterations: 100)

    let testFile: URL = try! {
        let url = try FileManager.default.url(for: .itemReplacementDirectory,
                                              in: .userDomainMask,
                                              appropriateFor: URL.temporaryDirectory,
                                              create: false)
            .appending(component: "URLSession benchmark test data")

        //print("Test file: \(url.path(percentEncoded: false))")

        precondition(FileManager.default.createFile(atPath: url.path(percentEncoded: false),
                                                    contents: nil))

        atexit_b {
            try! FileManager.default.removeItem(at: url)
            //print("Deleted test file.")
        }

        let handle = try FileHandle(forWritingTo: url)

        var gen = Xoshiro()

        let chunkSize = max(testFileSize, 1024 * 1024)

        for _ in 0..<(testFileSize / chunkSize) {
            try withUnsafeTemporaryAllocation(of: UInt8.self,
                                              capacity: chunkSize) { byteBuffer in
                byteBuffer.withMemoryRebound(to: UInt64.self) { wordBuffer in
                    for i in sequence(first: wordBuffer.startIndex, next: {
                        let next = wordBuffer.index(after: $0)

                        guard next != wordBuffer.endIndex else {
                            return nil
                        }

                        return next
                    }) {
                        wordBuffer[i] = gen.next()
                    }
                }

                try handle.write(contentsOf: UnsafeBufferPointer(byteBuffer))
            }
        }

        return url
    }()

    let session = URLSession(configuration: .ephemeral)

    Benchmark("bytewise read using data(from:) and for loop") { benchmark in
        for _ in benchmark.scaledIterations {
            let (data, response) = try await session.data(from: testFile)

            precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response)")

            var hash: UInt8 = 0

            for byte in data {
                hash &+= byte
            }

            blackHole(hash)
        }
    }

    Benchmark("bytewise read using data(from:) and reduce") { benchmark in
        for _ in benchmark.scaledIterations {
            let (data, response) = try await session.data(from: testFile)

            precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response)")

            blackHole(data.reduce(into: UInt8(0)) { hash, byte in
                hash &+= byte
            })
        }
    }

    Benchmark("bytewise read using data(from:) and forEach") { benchmark in
        for _ in benchmark.scaledIterations {
            let (data, response) = try await session.data(from: testFile)

            precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response)")

            var hash: UInt8 = 0

            data.forEach { byte in
                hash &+= byte
            }

            blackHole(hash)
        }
    }

    Benchmark("bytewise read using data(from:) and for loop inside withUnsafeBytes") { benchmark in
        for _ in benchmark.scaledIterations {
            let (data, response) = try await session.data(from: testFile)

            precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response)")

            var hash: UInt8 = 0

            data.withUnsafeBytes { buffer in
                for byte in buffer {
                    hash &+= byte
                }
            }

            blackHole(hash)
        }
    }

    Benchmark("bytewise read using bytes(from:) and for loop") { benchmark in
        for _ in benchmark.scaledIterations {
            let (bytes, response) = try await session.bytes(from: testFile)

            var hash: UInt8 = 0
            var count = 0

            for try await byte in bytes {
                hash &+= byte
                count += 1
            }

            blackHole(hash)
            precondition(testFileSize == count, "Read only \(count) byte(s).  Response: \(response)")
        }
    }

    Benchmark("bytewise read using bytes(from:) and reduce") { benchmark in
        for _ in benchmark.scaledIterations {
            let (bytes, response) = try await session.bytes(from: testFile)

            var count = 0

            blackHole(try await bytes.reduce(into: UInt8(0)) { hash, byte in
                hash &+= byte
                count += 1
            })

            precondition(testFileSize == count, "Read only \(count) byte(s).  Response: \(response)")
        }
    }

    Benchmark("bytewise read using dataTask(with:completionHandler:) and for loop ") { benchmark in
        for _ in benchmark.scaledIterations {
            let done = NSCondition()

            session.dataTask(with: testFile) { data, response, error in
                if let error {
                    preconditionFailure("Error: \(error)")
                }

                guard let data else {
                    preconditionFailure("No data.  Response: \(response.orNilString)")
                }

                precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response.orNilString)")

                var hash: UInt8 = 0

                for byte in data {
                    hash &+= byte
                }

                blackHole(hash)

                done.broadcast()
            }.resume()

            done.wait()
        }
    }

    Benchmark("bytewise read using dataTask(with:completionHandler:) and for loop inside withUnsafeBytes") { benchmark in
        for _ in benchmark.scaledIterations {
            let done = NSCondition()

            session.dataTask(with: testFile) { data, response, error in
                if let error {
                    preconditionFailure("Error: \(error)")
                }

                guard let data else {
                    preconditionFailure("No data.  Response: \(response.orNilString)")
                }

                precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response.orNilString)")

                var hash: UInt8 = 0

                data.withUnsafeBytes { buffer in
                    for byte in buffer {
                        hash &+= byte
                    }
                }

                blackHole(hash)

                done.broadcast()
            }.resume()

            done.wait()
        }
    }

    Benchmark("bytewise read using dataTask(with:completionHandler:) and reduce") { benchmark in
        for _ in benchmark.scaledIterations {
            let done = NSCondition()

            session.dataTask(with: testFile) { data, response, error in
                if let error {
                    preconditionFailure("Error: \(error)")
                }

                guard let data else {
                    preconditionFailure("No data.  Response: \(response.orNilString)")
                }

                precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response.orNilString)")

                blackHole(data.reduce(into: UInt8(0)) { hash, byte in
                    hash &+= byte
                })

                done.broadcast()
            }.resume()

            done.wait()
        }
    }

    Benchmark("bytewise read using dataTask(with:completionHandler:) and forEach") { benchmark in
        for _ in benchmark.scaledIterations {
            let done = NSCondition()

            session.dataTask(with: testFile) { data, response, error in
                if let error {
                    preconditionFailure("Error: \(error)")
                }

                guard let data else {
                    preconditionFailure("No data.  Response: \(response.orNilString)")
                }

                precondition(testFileSize == data.count, "Read only \(data.count) byte(s).  Response: \(response.orNilString)")

                var hash: UInt8 = 0

                data.forEach { byte in
                    hash &+= byte
                }

                blackHole(hash)

                done.broadcast()
            }.resume()

            done.wait()
        }
    }

    Benchmark("bytewise read using dataTask(with:) and an incremental delegate with for loop") { benchmark in
        for _ in benchmark.scaledIterations {
            var hash: UInt8 = 0
            var count = 0

            let task = session.dataTask(with: testFile)

            let delegate = IncrementalDataDelegate(task) { data in
                count += data.count

                for byte in data {
                    hash &+= byte
                }
            }

            task.delegate = delegate
            task.resume()

            delegate.wait()

            blackHole(hash)

            precondition(testFileSize == count, "Read only \(count) byte(s).")
        }
    }

    Benchmark("bytewise read using dataTask(with:) and an incremental delegate with for loop inside withUnsafeBytes") { benchmark in
        for _ in benchmark.scaledIterations {
            var hash: UInt8 = 0
            var count = 0

            let task = session.dataTask(with: testFile)

            let delegate = IncrementalDataDelegate(task) { data in
                count += data.count

                data.withUnsafeBytes { buffer in
                    for byte in buffer {
                        hash &+= byte
                    }
                }
            }

            task.delegate = delegate
            task.resume()

            delegate.wait()

            blackHole(hash)

            precondition(testFileSize == count, "Read only \(count) byte(s).")
        }
    }

    Benchmark("bytewise read using dataTask(with:) and an incremental delegate with reduce") { benchmark in
        for _ in benchmark.scaledIterations {
            var hash: UInt8 = 0
            var count = 0

            let task = session.dataTask(with: testFile)

            let delegate = IncrementalDataDelegate(task) { data in
                count += data.count

                hash = data.reduce(into: hash) { hash, byte in
                    hash &+= byte
                }
            }

            task.delegate = delegate
            task.resume()

            delegate.wait()

            blackHole(hash)

            precondition(testFileSize == count, "Read only \(count) byte(s).")
        }
    }

    Benchmark("bytewise read using dataTask(with:) and an incremental delegate with forEach") { benchmark in
        for _ in benchmark.scaledIterations {
            var hash: UInt8 = 0
            var count = 0

            let task = session.dataTask(with: testFile)

            let delegate = IncrementalDataDelegate(task) { data in
                count += data.count

                data.forEach { byte in
                    hash &+= byte
                }
            }

            task.delegate = delegate
            task.resume()

            delegate.wait()

            blackHole(hash)

            precondition(testFileSize == count, "Read only \(count) byte(s).")
        }
    }
}

class IncrementalDataDelegate: NSObject, URLSessionDataDelegate {
    private let task: URLSessionTask
    private let handler: (Data) -> ()
    private let done = NSCondition()

    init(_ task: URLSessionTask,
         handler: @escaping (Data) -> ()) {
        self.task = task
        self.handler = handler
        super.init()
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        precondition(self.task == dataTask)
        self.handler(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        precondition(self.task == task)

        if let error {
            preconditionFailure("Error: \(error)")
        }

        self.done.broadcast()
    }

    func wait() {
        self.done.wait()
    }
}
