import Benchmark
import Darwin
import Foundation

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

    Benchmark("ContinuousClock") { benchmark in
        let clock = ContinuousClock()
        var lastUpdate = clock.now

        for _ in benchmark.scaledIterations {
            let now = clock.now
            let delta = now - lastUpdate

            if delta > .milliseconds(updateRateInMilliseconds) {
                lastUpdate = now
            }
        }

        blackHole(lastUpdate)
    }

    Benchmark("SuspendingClock") { benchmark in
        let clock = SuspendingClock()
        var lastUpdate = clock.now

        for _ in benchmark.scaledIterations {
            let now = clock.now
            let delta = now - lastUpdate

            if delta > .milliseconds(updateRateInMilliseconds) {
                lastUpdate = now
            }
        }

        blackHole(lastUpdate)
    }

    Benchmark("Date") { benchmark in
        var lastUpdate = Date.now

        for _ in benchmark.scaledIterations {
            let delta = -lastUpdate.timeIntervalSinceNow

            if delta > Double(updateRateInMilliseconds) / 1000 {
                lastUpdate = Date.now
            }
        }

        blackHole(lastUpdate)
    }

    Benchmark("gettimeofday") { benchmark in
        var lastUpdate = timeval()
        precondition(0 == gettimeofday(&lastUpdate, nil))

        for _ in benchmark.scaledIterations {
            var now = timeval()
            precondition(0 == gettimeofday(&now, nil))

            let delta = (   ((UInt64(now.tv_sec) * 1_000_000_000) + UInt64(now.tv_usec))
                          - ((UInt64(lastUpdate.tv_sec) * 1_000_000_000) + UInt64(lastUpdate.tv_usec)))

            if delta > updateRateInMilliseconds * 1_000_000 {
                lastUpdate = now
            }
        }

        blackHole(lastUpdate)
    }

    Benchmark("clock_gettime_nsec_np(CLOCK_UPTIME_RAW)") { benchmark in
        var lastUpdate = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)

        for _ in benchmark.scaledIterations {
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let delta = now - lastUpdate

            if delta > updateRateInMilliseconds * 1_000_000 {
                lastUpdate = now
            }
        }

        blackHole(lastUpdate)
    }

    Benchmark("clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)") { benchmark in
        var lastUpdate = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)

        for _ in benchmark.scaledIterations {
            let now = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)
            let delta = now - lastUpdate

            if delta > updateRateInMilliseconds * 1_000_000 {
                lastUpdate = now
            }
        }

        blackHole(lastUpdate)
    }

    Benchmark("mach_absolute_time") { benchmark in
        var timebaseInfo = mach_timebase_info()
        precondition(0 == mach_timebase_info(&timebaseInfo))

        let updateRate = UInt64(Double(updateRateInMilliseconds)
                                * 1_000_000
                                * Double(timebaseInfo.denom)
                                / Double(timebaseInfo.numer))

        //print("timebaseInfo = \(timebaseInfo.numer) / \(timebaseInfo.denom)\nupdateRate = \(updateRate)")

        var lastUpdate = mach_absolute_time()

        for _ in benchmark.scaledIterations {
            let now = mach_absolute_time()
            let delta = now - lastUpdate

            if delta > updateRate {
                lastUpdate = now
            }
        }

        blackHole(lastUpdate)
    }
}
