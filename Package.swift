// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Swift Benchmarks",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(url: "https://github.com/ordo-one/package-benchmark", .upToNextMajor(from: "1.11.2")),
        .package(url: "https://github.com/pointfreeco/swift-gen.git",  .upToNextMajor(from: "0.4.0")),
    ],
    targets: [
        .executableTarget(
            name: "ArrayProcessing",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "Gen", package: "swift-gen"),
            ],
            path: "Benchmarks/ArrayProcessing",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        ),
        .executableTarget(
            name: "Clocks",
            dependencies: [
                .product(name: "Benchmark", package: "package-benchmark"),
                .product(name: "Gen", package: "swift-gen"),
            ],
            path: "Benchmarks/Clocks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark")
            ]
        )
    ]
)
