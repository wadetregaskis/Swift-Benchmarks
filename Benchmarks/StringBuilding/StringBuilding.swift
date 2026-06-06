import Benchmark
import Foundation
import Gen

// Benchmarks of the many ways to assemble a UTF-8 `String` from a sequence of chunks.
//
// Two questions are parameterised:
//   • The append *pattern* — chunks have a mean byte length (1…1,000) and a variance (0…±100% of the mean).  Smaller chunks mean more append operations for the same output, isolating per-append overhead; larger chunks shift the cost towards bulk copying.  Chunks are always cut on character (grapheme) boundaries, so every chunk is independently-valid UTF-8.
//   • The *character set* — ASCII (1 byte/char), CJK (3 bytes/char), a realistic mixed-prose blend, and an emoji/complex-grapheme set (4+ bytes, multiple scalars per grapheme) that exercises grapheme-breaking in the String-appending paths.
//
// Each configuration is built from two source representations, benchmarked separately, because in the real world your data already exists in one form or the other and the conversion cost is part of the answer:
//   • `[String]`  — concatenating text fragments.
//   • `[[UInt8]]` — assembling a String from decoded UTF-8 byte chunks (e.g. from I/O).
//
// Benchmark names encode their parameters as `[src=… | set=… | mean=… | var=… | out=…] Algorithm name`, where mean/var/out are raw byte counts, so the output is easy to split into columns for charting.  See "Output data munging commands.md".

// MARK: - Flags

/// When enabled, every algorithm's output is checked against a reference (and the timings become meaningless — ignore them).
let validate = false

/// Trims the matrix down to a handful of cases for fast iteration on the benchmark itself.
let quick = false

/// The pathological O(n²) approaches (non-in-place `reduce(_:_:)`, string interpolation) are only run when the chunk count is small enough to finish in reasonable time; above this they're skipped so they don't dominate the total runtime.
let quadraticChunkLimit = 2_048

// MARK: - Deterministic PRNG seeding

/// FNV-1a over the inputs, giving a seed that's stable across runs (unlike Swift's randomly-seeded `Hasher`).
private func seed(_ values: UInt64...) -> UInt64 {
    var hash: UInt64 = 14695981039346656037
    for value in values {
        hash = (hash ^ value) &* 1099511628211
    }
    return hash
}

// MARK: - Character sets

enum Charset: String, CaseIterable {
    case ascii = "ASCII"
    case cjk = "CJK"
    case mixed = "Mixed"
    case emoji = "Emoji"
}

/// Printable ASCII (one byte per character).
private let asciiCharacters: [Character] = (0x20...0x7E).map { Character(Unicode.Scalar($0)!) }

/// CJK Unified Ideographs (three bytes per character in UTF-8).
private let cjkCharacters: [Character] = (0x4E00...0x9FFF).map { Character(Unicode.Scalar($0)!) }

/// Latin-1 supplement letters & symbols (two bytes per character in UTF-8).
private let latin1Characters: [Character] = (0xA1...0xFF).compactMap { Unicode.Scalar($0).map(Character.init) }

/// A spread of emoji that are deliberately gnarly: simple 4-byte emoji, skin-tone-modified, ZWJ sequences, regional-indicator flags, and keycaps.  Most are multiple scalars per grapheme, which is what makes `Character`-level appends expensive.
private let emojiCharacters: [Character] = [
    "😀", "🎉", "🚀", "🔥", "✨", "🌍", "🍎", "🐢", // Simple 4-byte emoji.
    "👍🏽", "👋🏿", "✊🏻",                                // Skin-tone modified (multi-scalar).
    "👨‍👩‍👧‍👦", "🧑‍🚀", "👩‍💻", "🏳️‍🌈",                          // ZWJ sequences.
    "🇯🇵", "🇺🇸", "🇫🇷",                                // Regional-indicator flags.
    "1️⃣", "#️⃣", "🏴‍☠️",                                // Keycaps & tag sequences.
]

/// Returns a closure that yields a random `Character` for the given set.  "Mixed" is a realistic-ish prose blend that's mostly ASCII with a sprinkling of wider scalars.
private func characterGenerator(for charset: Charset) -> (inout Xoshiro) -> Character {
    switch charset {
    case .ascii:
        { asciiCharacters[Int.random(in: asciiCharacters.indices, using: &$0)] }
    case .cjk:
        { cjkCharacters[Int.random(in: cjkCharacters.indices, using: &$0)] }
    case .emoji:
        { emojiCharacters[Int.random(in: emojiCharacters.indices, using: &$0)] }
    case .mixed:
        { rng in
            switch Int.random(in: 0..<100, using: &rng) {
                case 0..<80:  asciiCharacters[Int.random(in: asciiCharacters.indices, using: &rng)]
                case 80..<92: latin1Characters[Int.random(in: latin1Characters.indices, using: &rng)]
                case 92..<99: cjkCharacters[Int.random(in: cjkCharacters.indices, using: &rng)]
                default:      emojiCharacters[Int.random(in: emojiCharacters.indices, using: &rng)]
            }
        }
    }
}

// MARK: - Input generation

struct Configuration: Hashable {
    let charset: Charset
    let meanBytes: Int
    let varianceBytes: Int
    let outputBytes: Int
}

struct GeneratedInput {
    let strings: [String]
    let bytes: [[UInt8]]
    let totalBytes: Int
    let totalCharacters: Int

    var chunkCount: Int { strings.count }
}

/// Generated inputs are memoised so that the (potentially large) chunk arrays are produced once per configuration and shared by every algorithm that uses them.  Benchmarks run sequentially in a single process, so the unsynchronised access is safe.
nonisolated(unsafe) private var inputCache: [Configuration: GeneratedInput] = [:]

private func input(for configuration: Configuration) -> GeneratedInput {
    if let cached = inputCache[configuration] {
        return cached
    }

    var rng = Xoshiro(seed: seed(1, 3, 3, 7))
    let nextCharacter = characterGenerator(for: configuration.charset)

    var strings: [String] = []
    var bytes: [[UInt8]] = []
    var totalBytes = 0
    var totalCharacters = 0

    let low = max(1, configuration.meanBytes - configuration.varianceBytes)
    let high = configuration.meanBytes + configuration.varianceBytes

    while totalBytes < configuration.outputBytes {
        let target = (low >= high) ? low : Int.random(in: low...high, using: &rng)

        var characters: [Character] = []
        var chunkBytes = 0

        // Always emit at least one character; otherwise fill with whole characters until we reach (or just pass) the target.
        repeat {
            let character = nextCharacter(&rng)
            characters.append(character)
            chunkBytes += character.utf8.count
        } while chunkBytes < target

        let string = String(characters)

        strings.append(string)
        bytes.append(Array(string.utf8))

        totalBytes += chunkBytes
        totalCharacters += characters.count
    }

    let result = GeneratedInput(strings: strings,
                                bytes: bytes,
                                totalBytes: totalBytes,
                                totalCharacters: totalCharacters)

    inputCache[configuration] = result

    return result
}

// MARK: - Algorithms

struct Algorithm {
    let name: String

    /// Part of the curated "core" set used for the (lighter) output-size scaling sweep and `quick` mode.
    var core = false

    enum Reservation {
        case notSupported
        case supported
        case required
    }

    /// `true` if the algorithm can reserve the required space in advance.
    var reservation = Reservation.notSupported

    /// `true` for O(n²) approaches that must be skipped when there are too many chunks.
    var quadratic = false

    let fromStrings: (@Sendable (_ chunks: [String],
                                 _ totalBytes: Int?,
                                 _ charset: Charset) -> String)?
    let fromBytes: (@Sendable (_ chunks: [[UInt8]],
                               _ totalBytes: Int?,
                               _ charset: Charset) -> String)?
}

/// Copies a contiguous block into `destination`, returning the number of bytes written.
@inline(__always)
private func copy(_ source: UnsafeBufferPointer<UInt8>, to destination: UnsafeMutablePointer<UInt8>) -> Int {
    if let base = source.baseAddress { // If the source is an empty string, it has no base address.  This never actually happens in the benchmark, but general-purpose real-world code would have to handle this gracefully, so we do it here.  It's conceivable the optimiser will remove this check though, if it is smart enough.  But that's unlikely.
        destination.update(from: base, count: source.count)
    }

    return source.count
}

/// The algorithms that don't need any OS newer than the package's deployment target.
private let baseAlgorithms: [Algorithm] = [

    // MARK: String accumulation

    Algorithm(name: "String +=", core: true, reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var result = ""

                  if let totalBytes {
                      result.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      result += chunk
                  }

                  return result
              },
              fromBytes: { chunks, totalBytes, _ in
                  var result = ""

                  if let totalBytes {
                      result.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      result += String(decoding: chunk, as: UTF8.self)
                  }

                  return result
              }),

    Algorithm(name: "String.append", reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var result = ""

                  if let totalBytes {
                      result.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      result.append(chunk)
                  }

                  return result
              },
              fromBytes: { chunks, totalBytes, _ in
                  var result = ""

                  if let totalBytes {
                      result.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      result.append(String(decoding: chunk, as: UTF8.self))
                  }

                  return result
              }),

    Algorithm(name: "joined()", core: true,
              fromStrings: { chunks, _, _ in chunks.joined() },
              fromBytes: nil),

    Algorithm(name: "String(decoding:as) → joined()", core: true,
              fromStrings: nil,
              fromBytes: { chunks, _, _ in chunks.lazy.map { String(decoding: $0, as: UTF8.self) }.joined() }),

    Algorithm(name: "joined() → String(decoding:as:)", core: true,
              fromStrings: nil,
              fromBytes: { chunks, _, _ in String(decoding: chunks.lazy.joined(), as: UTF8.self) }),

    Algorithm(name: "unicodeScalars.append(contentsOf:)", reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var result = ""

                  if let totalBytes {
                      result.reserveCapacity(totalBytes)
                  }

                  var scalars = result.unicodeScalars

                  for chunk in chunks {
                      scalars.append(contentsOf: chunk.unicodeScalars)
                  }

                  return result
              },
              fromBytes: { chunks, totalBytes, _ in
                  var result = ""

                  if let totalBytes {
                      result.reserveCapacity(totalBytes)
                  }

                  var scalars = result.unicodeScalars

                  for chunk in chunks {
                      scalars.append(contentsOf: String(decoding: chunk, as: UTF8.self).unicodeScalars)
                  }

                  return result
              }),

    Algorithm(name: "String interpolation accumulation", reservation: .supported, quadratic: true,
              fromStrings: { chunks, _, _ in
                  var result = ""

                  for chunk in chunks {
                      result = "\(result)\(chunk)"
                  }

                  return result
              },
              fromBytes: { chunks, _, _ in
                  var result = ""

                  for chunk in chunks {
                      result = "\(result)\(String(decoding: chunk, as: UTF8.self))"
                  }

                  return result
              }),

    Algorithm(name: "[UInt8].append(contentsOf:) → String(decoding:)", core: true, reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var bytes = [UInt8]()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk.utf8)
                  }

                  return String(decoding: bytes, as: UTF8.self)
              },
              fromBytes: { chunks, totalBytes, _ in
                  var bytes = [UInt8]()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk)
                  }

                  return String(decoding: bytes, as: UTF8.self)
              }),

    Algorithm(name: "ContiguousArray<UInt8>.append(contentsOf:) → String(decoding:as:)", reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var bytes = ContiguousArray<UInt8>()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk.utf8)
                  }

                  return String(decoding: bytes, as: UTF8.self)
              },
              fromBytes: { chunks, totalBytes, _ in
                  var bytes = ContiguousArray<UInt8>()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk)
                  }

                  return String(decoding: bytes, as: UTF8.self)
              }),

    Algorithm(name: "[UInt8].append(contentsOf:) → String(bytes:encoding:)", reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var bytes = [UInt8]()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk.utf8)
                  }

                  return String(bytes: bytes, encoding: .utf8)!
              },
              fromBytes: { chunks, totalBytes, _ in
                  var bytes = [UInt8]()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk)
                  }

                  return String(bytes: bytes, encoding: .utf8)!
              }),

    Algorithm(name: "Data.append(contentsOf:) → String(decoding:)", core: true, reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var data: Data

                  if let totalBytes {
                      data = Data(capacity: totalBytes)
                  } else {
                      data = Data()
                  }

                  for chunk in chunks {
                      data.append(contentsOf: chunk.utf8)
                  }

                  return String(decoding: data, as: UTF8.self)
              },
              fromBytes: { chunks, totalBytes, _ in
                  var data: Data

                  if let totalBytes {
                      data = Data(capacity: totalBytes)
                  } else {
                      data = Data()
                  }

                  for chunk in chunks {
                      data.append(contentsOf: chunk)
                  }

                  return String(decoding: data, as: UTF8.self)
              }),

    Algorithm(name: "NSMutableString.append", reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  let result: NSMutableString

                  if let totalBytes {
                      result = NSMutableString(capacity: totalBytes) // Note: it's unclear how NSMutableString interprets the capacity, i.e. whether it's bytes (as with Swift Strings) or something else (e.g. UTF-16 code units).  So this might be over-allocating.  But hopefully for the purposes of benchmarking it's acceptable (just don't necessarily do this in real code - you might end up wasting a lot of memory!).
                  } else {
                      result = NSMutableString()
                  }

                  for chunk in chunks {
                      result.append(chunk)
                  }

                  return result as String
              },
              fromBytes: { chunks, totalBytes, _ in
                  let result: NSMutableString

                  if let totalBytes {
                      result = NSMutableString(capacity: totalBytes) // Note: it's unclear how NSMutableString interprets the capacity, i.e. whether it's bytes (as with Swift Strings) or something else (e.g. UTF-16 code units).  So this might be over-allocating.  But hopefully for the purposes of benchmarking it's acceptable (just don't necessarily do this in real code - you might end up wasting a lot of memory!).
                  } else {
                      result = NSMutableString()
                  }

                  for chunk in chunks {
                      result.append(String(decoding: chunk, as: UTF8.self))
                  }

                  return result as String
              }),

    Algorithm(name: "String(unsafeUninitializedCapacity:)", core: true, reservation: .required,
              fromStrings: { chunks, totalBytes, _ in
                  String(unsafeUninitializedCapacity: totalBytes!) { buffer in
                      let base = buffer.baseAddress!
                      var offset = 0

                      for chunk in chunks {
                          var chunk = chunk
                          offset += chunk.withUTF8 {
                              copy($0, to: base + offset)
                          }
                      }

                      return offset
                  }
              },
              fromBytes: { chunks, totalBytes, _ in
                  String(unsafeUninitializedCapacity: totalBytes!) { buffer in
                      let base = buffer.baseAddress!
                      var offset = 0

                      for chunk in chunks {
                          offset += chunk.withUnsafeBufferPointer {
                              copy($0, to: base + offset)
                          }
                      }

                      return offset
                  }
              }),

    Algorithm(name: "[UInt8](unsafeUninitializedCapacity:) → String(decoding:)", core: true, reservation: .required,
              fromStrings: { chunks, totalBytes, _ in
                  let bytes = [UInt8](unsafeUninitializedCapacity: totalBytes!) { buffer, initializedCount in
                      let base = buffer.baseAddress!
                      var offset = 0

                      for chunk in chunks {
                          var chunk = chunk
                          offset += chunk.withUTF8 {
                              copy($0, to: base + offset)
                          }
                      }

                      initializedCount = offset
                  }

                  return String(decoding: bytes, as: UTF8.self)
              },
              fromBytes: { chunks, totalBytes, _ in
                  let bytes = [UInt8](unsafeUninitializedCapacity: totalBytes!) { buffer, initializedCount in
                      let base = buffer.baseAddress!
                      var offset = 0

                      for chunk in chunks {
                          offset += chunk.withUnsafeBufferPointer {
                              copy($0, to: base + offset)
                          }
                      }

                      initializedCount = offset
                  }

                  return String(decoding: bytes, as: UTF8.self)
              }),

    Algorithm(name: "withUnsafeTemporaryAllocation → String(decoding:)", reservation: .required,
              fromStrings: { chunks, totalBytes, _ in
                  withUnsafeTemporaryAllocation(of: UInt8.self, capacity: totalBytes!) { buffer in
                      let base = buffer.baseAddress!

                      var offset = 0

                      for chunk in chunks {
                          var chunk = chunk
                          offset += chunk.withUTF8 {
                              copy($0, to: base + offset)
                          }
                      }

                      return String(decoding: UnsafeBufferPointer(start: base, count: offset), as: UTF8.self)
                  }
              },
              fromBytes: { chunks, totalBytes, _ in
                  withUnsafeTemporaryAllocation(of: UInt8.self, capacity: totalBytes!) { buffer in
                      let base = buffer.baseAddress!

                      var offset = 0

                      for chunk in chunks {
                          offset += chunk.withUnsafeBufferPointer {
                              copy($0, to: base + offset)
                          }
                      }

                      return String(decoding: UnsafeBufferPointer(start: base, count: offset), as: UTF8.self)
                  }
              }),

    Algorithm(name: "UnsafeMutablePointer → String(decoding:)", core: true, reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var capacity = totalBytes ?? 16

                  var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                  defer { buffer.deallocate() }

                  var count = 0

                  for chunk in chunks {
                      var chunk = chunk

                      chunk.withUTF8 { source in
                          let width = source.count

                          if count + width > capacity {
                              var newCapacity = capacity

                              repeat {
                                  newCapacity *= 2
                              } while count + width > newCapacity

                              let grown = UnsafeMutablePointer<UInt8>.allocate(capacity: newCapacity)

                              grown.update(from: buffer, count: count)

                              buffer.deallocate()
                              buffer = grown

                              capacity = newCapacity
                          }

                          count += copy(source, to: buffer + count)
                      }
                  }

                  return String(decoding: UnsafeBufferPointer(start: buffer, count: count), as: UTF8.self)
              },
              fromBytes: { chunks, totalBytes, _ in
                  var capacity = totalBytes ?? 16

                  var buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
                  defer { buffer.deallocate() }

                  var count = 0

                  for chunk in chunks {
                      chunk.withUnsafeBufferPointer { source in
                          let width = source.count

                          if count + width > capacity {
                              var newCapacity = capacity

                              repeat {
                                  newCapacity *= 2
                              } while count + width > newCapacity

                              let grown = UnsafeMutablePointer<UInt8>.allocate(capacity: newCapacity)

                              grown.update(from: buffer, count: count)

                              buffer.deallocate()
                              buffer = grown

                              capacity = newCapacity
                          }

                          count += copy(source, to: buffer + count)
                      }
                  }

                  return String(decoding: UnsafeBufferPointer(start: buffer, count: count), as: UTF8.self)
              }),

    Algorithm(name: "OutputSpan into String(unsafeUninitializedCapacity:), per-byte append", core: true, reservation: .required,
              fromStrings: { chunks, totalBytes, _ in
                  String(unsafeUninitializedCapacity: totalBytes!) { buffer in
                      var output = OutputSpan(buffer: buffer, initializedCount: 0)

                      for chunk in chunks {
                          for byte in chunk.utf8 {
                              output.append(byte)
                          }
                      }

                      return output.finalize(for: buffer)
                  }
              },
              fromBytes: { chunks, totalBytes, _ in
                  String(unsafeUninitializedCapacity: totalBytes!) { buffer in
                      var output = OutputSpan(buffer: buffer, initializedCount: 0)

                      for chunk in chunks {
                          for byte in chunk {
                              output.append(byte)
                          }
                      }

                      return output.finalize(for: buffer)
                  }
              }),

    Algorithm(name: "OutputRawSpan into String(unsafeUninitializedCapacity:), per-byte append", reservation: .required,
              fromStrings: { chunks, totalBytes, _ in
                  String(unsafeUninitializedCapacity: totalBytes!) { buffer in
                      let raw = UnsafeMutableRawBufferPointer(buffer)
                      var output = OutputRawSpan(buffer: raw, initializedCount: 0)

                      for chunk in chunks {
                          for byte in chunk.utf8 {
                              output.append(byte)
                          }
                      }

                      return output.finalize(for: raw)
                  }
              },
              fromBytes: { chunks, totalBytes, _ in
                  String(unsafeUninitializedCapacity: totalBytes!) { buffer in
                      let raw = UnsafeMutableRawBufferPointer(buffer)
                      var output = OutputRawSpan(buffer: raw, initializedCount: 0)

                      for chunk in chunks {
                          for byte in chunk {
                              output.append(byte)
                          }
                      }

                      return output.finalize(for: raw)
                  }
              }),

    Algorithm(name: "[UInt8].append(contentsOf:) → String(validating:as:)", reservation: .supported,
              fromStrings: { chunks, totalBytes, _ in
                  var bytes = [UInt8]()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk.utf8)
                  }

                  return String(validating: bytes, as: UTF8.self)!
              },
              fromBytes: { chunks, totalBytes, _ in
                  var bytes = [UInt8]()

                  if let totalBytes {
                      bytes.reserveCapacity(totalBytes)
                  }

                  for chunk in chunks {
                      bytes.append(contentsOf: chunk)
                  }

                  return String(validating: bytes, as: UTF8.self)!
              }),
]

/// Approaches that require macOS 26 (`UTF8Span` and `Array.span` are gated to it, so these won't run on an older OS).
@available(macOS 26, *)
private func macOS26Algorithms() -> [Algorithm] {
    [
        Algorithm(name: "[UInt8].append(contentsOf:) → UTF8Span(validating:) → String(copying:)", reservation: .supported,
                  fromStrings: { chunks, totalBytes, _ in
                      var bytes = [UInt8]()

                      if let totalBytes {
                          bytes.reserveCapacity(totalBytes)
                      }

                      for chunk in chunks {
                          bytes.append(contentsOf: chunk.utf8)
                      }

                      return String(copying: try! UTF8Span(validating: bytes.span))
                  },
                  fromBytes: { chunks, totalBytes, _ in
                      var bytes = [UInt8]()

                      if let totalBytes {
                          bytes.reserveCapacity(totalBytes)
                      }

                      for chunk in chunks {
                          bytes.append(contentsOf: chunk)
                      }

                      return String(copying: try! UTF8Span(validating: bytes.span))
                  }),

        Algorithm(name: "[UInt8].append(contentsOf:) → UTF8Span(unchecked:isKnownASCII:) → String(copying:)", reservation: .supported,
                  fromStrings: { chunks, totalBytes, charset in
                      var bytes = [UInt8]()

                      if let totalBytes {
                          bytes.reserveCapacity(totalBytes)
                      }

                      for chunk in chunks {
                          bytes.append(contentsOf: chunk.utf8)
                      }

                      return String(copying: UTF8Span(unchecked: bytes.span, isKnownASCII: charset == .ascii))
                  },
                  fromBytes: { chunks, totalBytes, charset in
                      var bytes = [UInt8]()

                      if let totalBytes {
                          bytes.reserveCapacity(totalBytes)
                      }

                      for chunk in chunks {
                          bytes.append(contentsOf: chunk)
                      }

                      return String(copying: UTF8Span(unchecked: bytes.span, isKnownASCII: charset == .ascii))
                  }),
    ]
}

// MARK: - Validation

private func validateAlgorithms(_ algorithms: [Algorithm]) {
    let configuration = Configuration(charset: .mixed,
                                      meanBytes: 7,
                                      varianceBytes: 5,
                                      outputBytes: 4_096)

    let generated = input(for: configuration)
    let reference = generated.strings.joined()

    precondition(reference == String(decoding: Array(generated.bytes.joined()), as: UTF8.self),
                 "The two source representations disagree — input generation is broken.")

    for algorithm in algorithms {
        let fromStrings = algorithm.fromStrings?(generated.strings, generated.totalBytes, .mixed)
        let fromBytes = algorithm.fromBytes?(generated.bytes, generated.totalBytes, .mixed)

        if ((nil != algorithm.fromStrings) && (fromStrings != reference)) || ((nil != algorithm.fromBytes) && (fromBytes != reference)) {
            print("""
                  Validation FAILED for "\(algorithm.name)":
                     fromStrings correct: \(fromStrings == reference)
                       fromBytes correct: \(fromBytes == reference)
                  """)
            preconditionFailure()
        }
    }

    print("All \(algorithms.count) algorithms validated against \(generated.chunkCount) chunks / \(generated.totalBytes) bytes.")
}

// MARK: - Registration

nonisolated(unsafe) let benchmarks = {
    Benchmark.defaultConfiguration = .init(metrics: validate ? [] : [.wallClock,
                                                                     .mallocCountTotal,
                                                                     .peakMemoryResident,
                                                                     .retainCount,
                                                                     .releaseCount],
                                           scalingFactor: .one,
                                           maxDuration: .seconds(5),
                                           maxIterations: 100_000)

    var algorithms = baseAlgorithms

    if #available(macOS 26, *) {
        algorithms += macOS26Algorithms()
    }

    if validate {
        validateAlgorithms(algorithms)
    }

    func register(_ configuration: Configuration, algorithms: [Algorithm]) {
        let estimatedChunks = configuration.outputBytes / max(1, configuration.meanBytes)

        for algorithm in algorithms {
            if algorithm.quadratic && estimatedChunks > quadraticChunkLimit {
                continue
            }

            for useBytes in [false, true] {
                let lengthCases = switch algorithm.reservation {
                    case .notSupported: [false]
                    case .supported: [false, true]
                    case .required: [true]
                }

                for provideLength in lengthCases {
                    let name = "[src=\(useBytes ? "Bytes" : "String") | set=\(configuration.charset.rawValue) | mean=\(configuration.meanBytes) | var=\(configuration.varianceBytes) | out=\(configuration.outputBytes) | reserve=\(provideLength)] \(algorithm.name)"

                    if useBytes, let algo = algorithm.fromBytes {
                        Benchmark(name) { benchmark, generated in
                            let chunks = generated.bytes

                            for _ in benchmark.scaledIterations {
                                blackHole(algo(chunks, provideLength ? generated.totalBytes : nil, configuration.charset))
                            }
                        } setup: {
                            input(for: configuration)
                        }
                    } else if !useBytes, let algo = algorithm.fromStrings {
                        Benchmark(name) { benchmark, generated in
                            let chunks = generated.strings

                            for _ in benchmark.scaledIterations {
                                blackHole(algo(chunks, provideLength ? generated.totalBytes : nil, configuration.charset))
                            }
                        } setup: {
                            input(for: configuration)
                        }
                    }
                }
            }
        }
    }

    for charset in quick ? [Charset.ascii, .cjk] : Charset.allCases {
        for mean in quick ? [1, 100] : [1, 2, 4, 8, 16, 32, 64, 128, 256, 512, 1_024] {
            for variancePercent in [0] { // quick ? [0, 100] : [0, 50, 100] { // I'm not sure how valuable this is.
                // At a one-byte mean the variance can't do anything (a chunk is always at least one character), so skip the dupes.
                if mean == 1 && variancePercent != 0 {
                    continue
                }

                for outputBytes in [64, 256, 1024, 4_096, 16_384, 65_536, 262_144, 1_048_576] {
                    if mean <= outputBytes {
                        register(Configuration(charset: charset,
                                               meanBytes: mean,
                                               varianceBytes: mean * variancePercent / 100,
                                               outputBytes: outputBytes),
                                 algorithms: algorithms)
                    }
                }
            }
        }
    }
}
