// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "Swift Benchmarks",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/attaswift/BigInt.git", .upToNextMajor(from: "5.3.0")),
        .package(url: "https://github.com/ordo-one/benchmark", .upToNextMajor(from: "1.11.2"), traits: []),
        .package(url: "https://github.com/oscbyspro/Numberick.git", branch: "main"),
        .package(url: "https://github.com/pointfreeco/swift-gen.git",  .upToNextMajor(from: "0.4.0")),
        .package(url: "https://github.com/wadetregaskis/FoundationExtensions.git", .upToNextMajor(from: "3.4.0")),
    ],
    targets: [
        .executableTarget(
            name: "ArrayProcessing",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                .product(name: "Gen", package: "swift-gen"),
            ],
            path: "Benchmarks/ArrayProcessing",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        ),
        .executableTarget(
            name: "Clocks",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
            ],
            path: "Benchmarks/Clocks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        ),
        .executableTarget(
            name: "StringReplacement",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                .product(name: "Gen", package: "swift-gen"),
            ],
            path: "Benchmarks/StringReplacement",
            exclude: [
                "ChartResults",
                "Output data munging commands.md",
            ],
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        ),
        .executableTarget(
            name: "Swap",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                .product(name: "BigInt", package: "BigInt"),
                .product(name: "NBKFlexibleWidthKit", package: "Numberick"),
            ],
            path: "Benchmarks/Swap",
//            swiftSettings: [.unsafeFlags(["-Xfrontend", "-internalize-at-link", "-Xlinker", "-x", "-Xlinker", "-dead_strip", "-lto=llvm-full", "-experimental-hermetic-seal-at-link"])],
//            linkerSettings: [.unsafeFlags(["-Xfrontend", "-internalize-at-link", "-Xlinker", "-x", "-Xlinker", "-dead_strip", "-lto=llvm-full", "-experimental-hermetic-seal-at-link"])],
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        ),
        .executableTarget(
            name: "URLSession",
            dependencies: [
                .product(name: "Benchmark", package: "benchmark"),
                .product(name: "Gen", package: "swift-gen"),
                .product(name: "FoundationExtensions", package: "FoundationExtensions"),
            ],
            path: "Benchmarks/URLSession",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "benchmark")
            ]
        )
    ]
)
