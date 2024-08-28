import Benchmark
import Foundation
import Gen

let stringWithNoMatches = "[Mal] - Remember, if anything happens to me, or you don't 👂 from me within the hour… you take this 🚀 and you come and you rescue me."
let stringWithNoMatchesASCII = "[Mal] - Remember, if anything happens to me, or you don't hear from me within the hour... you take this ship and you come and you rescue me."

let stringWithFewMatches = "[Mal] - Remember, if anything happens to me, or you don't 👂 from me within the hour…\0you take this 🚀 and you come and you rescue me."
let stringWithFewMatchesASCII = "[Mal] - Remember, if anything happens to me, or you don't hear from me within the hour...\0you take this ship and you come and you rescue me."

let stringWithManyMatches = "[Mal]\0-\0Remember:/if/anything:happens/to:me,\0or:you/don't:👂:from/me:within/the:hour…\0you:take/this:🚀:and/you:come/and:you/rescue:me."
let stringWithManyMatchesASCII = "[Mal]\0-\0Remember:/if/anything:happens/to:me,\0or:you/don't:hear:from/me:within/the:hour...\0you:take/this:ship:and/you:come/and:you/rescue:me."

let validateResults = false // Off by default because it impacts performance.  Ignore the output measurements when this is enabled.

let benchmarks = {
    Benchmark.defaultConfiguration = .init(metrics: validateResults ? [] : [.cpuTotal,
                                                                            .wallClock,
                                                                            .mallocCountTotal,
                                                                            .peakMemoryResident,
                                                                            .objectAllocCount,
                                                                            .retainCount,
                                                                            .releaseCount],
                                           scalingFactor: validateResults ? .one : Benchmark.defaultConfiguration.scalingFactor,
                                           maxDuration: .seconds(30),
                                           maxIterations: 100)

    let replacementClasses: [(String, [(Character, Character)])] = [("Length unchanged", [(":", "-"),
                                                                                          ("/", ":"),
                                                                                          ("\0", "_")]),
                                                                    ("Length increased", [(":", "꞉"),
                                                                                          ("/", ":"),
                                                                                          ("\0", "␀")])]

    for (replacementsLabel, replacementsAsCharacters) in replacementClasses {
        let replacements = replacementsAsCharacters.map { (String($0.0), String($0.1)) }
        let replacementsAsDictionary = Dictionary(uniqueKeysWithValues: replacementsAsCharacters)

        for (sampleCore, label) in [
            ("", "Empty string"),
            (replacements.map { $0.0 }.joined(), "Only matches"),
            (stringWithNoMatches, "No matches"),
            (stringWithNoMatchesASCII, "No matches (ASCII)"),
            (stringWithOneMatch, "Few matches"),
            (stringWithOneMatchASCII, "Few matches (ASCII)"),
            (stringWithManyMatches, "Many matches"),
            (stringWithManyMatchesASCII, "Many matches (ASCII)")
        ] {
            for lengthModifier in sampleCore.isEmpty ? [1] : [1, 10, 100, 1_000, 10_000, 100_000, 1_000_000] {
                let sample = String(String(repeating: sampleCore, count: lengthModifier))

                let expectedResult = validateResults
                ? { // Note that this expectation hard-codes the assumption that the replacements are commutative (they can be run in any order with identical results).
                    var result = sample.replacingOccurrences(of: replacements[0].0, with: replacements[0].1)

                    for replacement in replacements[1...] {
                        result = result.replacingOccurrences(of: replacement.0, with: replacement.1)
                    }

                    return result
                }()
                : ""

                if validateResults {
                    print("Expected transformation: \(sample) → \(expectedResult)")
                }

                @inline(__always)
                func checkResult(_ result: String) {
                    if validateResults {
                        if result != expectedResult {
                            // For some reason the precondition functions never actually print the message before crashing the program.  So it has to be manually printed first. 🤨
                            print("""
                              Validation failure:
                                 Expected: "\(expectedResult)"
                                   Actual: "\(result)"
                              """)
                            preconditionFailure()
                        }
                    } else {
                        blackHole(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] N-pass via replacingOccurrences") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = sample.replacingOccurrences(of: replacements[0].0, with: replacements[0].1)

                        for replacement in replacements[1...] {
                            result = result.replacingOccurrences(of: replacement.0, with: replacement.1)
                        }

                        checkResult(result)
                    }
                }

                // Doesn't make a meaningful difference in runtime.  In this non-unrolled version there is in principle additional overhead, in the form of additional ARC traffic for the String CoW (Copy-on-Write) mechanism as well as the actual copy on first write.  But it appears that overhead is insignificant in practice, here.  So no point enabling both forms (especially not for every benchmark case).  I'm choosing to favour the hypothetically more optimal form (above) in order to rule out the CoW variable (and because in at least some real-world cases the replacements will be hard-coded and so amenable to partial if not full manual unrolling, and even in dynamic cases if the author cares enough about performance to consult benchmarks like this, they're going to be amenable to partial unrolling).
                //            Benchmark("[\(label) ⨉\(lengthModifier.formatted())] replacingOccurences") { benchmark in
                //                for _ in benchmark.scaledIterations {
                //                    var result = sample
                //
                //                    for replacement in replacements {
                //                        result = result.replacingOccurrences(of: replacement.0, with: replacement.1)
                //                    }
                //
                //                    blackHole(result)
                //                }
                //            }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] N-pass via replacingOccurrences(.literal)") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = sample.replacingOccurrences(of: replacements[0].0, with: replacements[0].1, options: .literal)

                        for replacement in replacements[1...] {
                            result = result.replacingOccurrences(of: replacement.0, with: replacement.1, options: .literal)
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] N-pass via replace") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = sample

                        for replacement in replacements {
                            result.replace(replacement.0, with: replacement.1)
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] N-pass via replacing") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = sample.replacing(replacements[0].0, with: replacements[0].1)

                        for replacement in replacements[1...] {
                            result = result.replacing(replacement.0, with: replacement.1)
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via character enumeration & concatenation") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = ""

                        mainLoop: for character in sample {
                            for replacement in replacementsAsCharacters {
                                if character == replacement.0 {
                                    result.append(replacement.1)
                                    continue mainLoop
                                }
                            }

                            result.append(character)
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via character enumeration & concatenation, with naive space reservation") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = ""

                        result.reserveCapacity(sample.utf8.count)

                        mainLoop: for character in sample {
                            for replacement in replacementsAsCharacters {
                                if character == replacement.0 {
                                    result.append(replacement.1)
                                    continue mainLoop
                                }
                            }

                            result.append(character)
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Two pass via character enumeration & concatenation, with accurate space reservation") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var outputByteCount = 0
                        var willReplace = false

                        mainLoop: for character in sample {
                            for replacement in replacementsAsCharacters {
                                if character == replacement.0 {
                                    outputByteCount += replacement.1.utf8.count
                                    willReplace = true
                                    continue mainLoop
                                }
                            }

                            outputByteCount += character.utf8.count
                        }

                        //print("\"\(sample)\" is \(sample.utf8.count) and will need \(outputByteCount).") // e.g.: ":/." is 3 and will need 5.

                        guard willReplace else {
                            blackHole(sample)
                            continue
                        }

                        var result = ""

                        result.reserveCapacity(outputByteCount)

                        mainLoop: for character in sample {
                            for replacement in replacementsAsCharacters {
                                if character == replacement.0 {
                                    result.append(replacement.1)
                                    continue mainLoop
                                }
                            }

                            result.append(character)
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Two pass via character enumeration & concatenation, with accurate space reservation & String(unsafeUninitializedCapacity:initializingUTF8With:)") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var outputByteCount = 0
                        var willReplace = false

                        mainLoop: for character in sample {
                            for replacement in replacementsAsCharacters {
                                if character == replacement.0 {
                                    outputByteCount += replacement.1.utf8.count
                                    willReplace = true
                                    continue mainLoop
                                }
                            }

                            outputByteCount += character.utf8.count
                        }

                        //print("\"\(sample)\" is \(sample.utf8.count) and will need \(outputByteCount).") // e.g.: ":/." is 3 and will need 5.

                        guard willReplace else {
                            blackHole(sample)
                            continue
                        }

                        let result = String(unsafeUninitializedCapacity: outputByteCount, initializingUTF8With: { buffer in
                            var index = buffer.startIndex

                            mainLoop: for character in sample {
                                for replacement in replacementsAsCharacters {
                                    if character == replacement.0 {
                                        index = buffer[index...].initialize(fromContentsOf: replacement.1.utf8)
                                        continue mainLoop
                                    }
                                }

                                index = buffer[index...].initialize(fromContentsOf: character.utf8)
                            }

                            return buffer.distance(from: buffer.startIndex, to: index)
                        })

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via firstIndex(where:) & concatenation") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = ""

                        var remainingString = sample[...]

                        while !remainingString.isEmpty {
                            var replacement: Character? = nil

                            if let indexOfNextReplacement = remainingString.firstIndex(where: {
                                if let rep = replacementsAsDictionary[$0] {
                                    replacement = rep
                                    return true
                                } else {
                                    return false
                                }
                            }) {
                                result += remainingString[..<indexOfNextReplacement]
                                result.append(replacement!)
                                remainingString = remainingString[remainingString.index(after: indexOfNextReplacement)...]
                            } else {
                                if result.isEmpty {
                                    result = sample
                                } else {
                                    result += remainingString
                                }

                                break
                            }
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via firstIndex(where:) & concatenation (array of replacements instead of dictionary)") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = ""

                        var remainingString = sample[...]

                        while !remainingString.isEmpty {
                            var replacement: Character? = nil

                            if let indexOfNextReplacement = remainingString.firstIndex(where: {
                                for pair in replacementsAsCharacters {
                                    if pair.0 == $0 {
                                        replacement = pair.1
                                        return true
                                    }
                                }

                                return false
                            }) {
                                result += remainingString[..<indexOfNextReplacement]
                                result.append(replacement!)
                                remainingString = remainingString[remainingString.index(after: indexOfNextReplacement)...]
                            } else {
                                if result.isEmpty {
                                    result = sample
                                } else {
                                    result += remainingString
                                }

                                break
                            }
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via firstIndex(where:) & concatenation, with naive space reservation") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = ""

                        result.reserveCapacity(sample.utf8.count)

                        var remainingString = sample[...]

                        while !remainingString.isEmpty {
                            var replacement: Character? = nil

                            if let indexOfNextReplacement = remainingString.firstIndex(where: {
                                if let rep = replacementsAsDictionary[$0] {
                                    replacement = rep
                                    return true
                                } else {
                                    return false
                                }
                            }) {
                                result += remainingString[..<indexOfNextReplacement]
                                result.append(replacement!)
                                remainingString = remainingString[remainingString.index(after: indexOfNextReplacement)...]
                            } else {
                                if result.isEmpty {
                                    result = sample
                                } else {
                                    result += remainingString
                                }

                                break
                            }
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via firstIndex(where:) & concatenation, with naive space reservation (array of replacements instead of dictionary)") { benchmark in
                    for _ in benchmark.scaledIterations {
                        var result = ""

                        result.reserveCapacity(sample.utf8.count)

                        var remainingString = sample[...]

                        while !remainingString.isEmpty {
                            var replacement: Character? = nil

                            if let indexOfNextReplacement = remainingString.firstIndex(where: {
                                for pair in replacementsAsCharacters {
                                    if pair.0 == $0 {
                                        replacement = pair.1
                                        return true
                                    }
                                }

                                return false
                            }) {
                                result += remainingString[..<indexOfNextReplacement]
                                result.append(replacement!)
                                remainingString = remainingString[remainingString.index(after: indexOfNextReplacement)...]
                            } else {
                                if result.isEmpty {
                                    result = sample
                                } else {
                                    result += remainingString
                                }

                                break
                            }
                        }

                        checkResult(result)
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via map & join") { benchmark in
                    for _ in benchmark.scaledIterations {
                        checkResult(String(sample.map {
                            replacementsAsDictionary[$0] ?? $0
                        }))
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via lazy map & join") { benchmark in
                    for _ in benchmark.scaledIterations {
                        checkResult(String(sample.lazy.map {
                            replacementsAsDictionary[$0] ?? $0
                        }))
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via map & join (array of replacements instead of dictionary)") { benchmark in
                    for _ in benchmark.scaledIterations {
                        checkResult(String(sample.map {
                            for replacement in replacementsAsCharacters {
                                if replacement.0 == $0 {
                                    return replacement.1
                                }
                            }

                            return $0
                        }))
                    }
                }

                Benchmark("[\(label) ⨉\(lengthModifier.formatted()), \(replacementsLabel)] Single pass via lazy map & join (array of replacements instead of dictionary)") { benchmark in
                    for _ in benchmark.scaledIterations {
                        checkResult(String(sample.lazy.map {
                            for replacement in replacementsAsCharacters {
                                if replacement.0 == $0 {
                                    return replacement.1
                                }
                            }

                            return $0
                        }))
                    }
                }
            }
        }
    }
}
