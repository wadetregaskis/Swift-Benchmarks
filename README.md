## Swift-Benchmarks

Varied benchmarks of Swift code.

This is essentially just a place to publish benchmark code.  The benchmarks are not necessarily self-explanatory; many were created & published here for the purposes of documentation or illustration of a blog post.

### Executing the benchmarks

`swift package benchmark`

See [the documentation](https://swiftpackageindex.com/ordo-one/benchmark/main/documentation/benchmark) for the [Benchmark](https://github.com/ordo-one/benchmark) package for details.

### Dependency updates

Note that, unlike most Swift packages, this one does _not_ commit `Package.resolved` to the repo.  So you'll automatically use the latest versions of all the dependencies when you first clone and build.  _But_, you'll never get automatically updated to new versions by e.g. `git pull --rebase`.  Instead, you'll have to manually `swift package update`.
