//
//  ContentView.swift
//  ChartResults
//
//  Created by Wade Tregaskis on 6/9/2024.
//

import Charts
import Darwin
import SwiftUI
import UniformTypeIdentifiers

struct Record: Identifiable {
    let id: Int

    let input: String
    let inputLengthInCharacters: Int
    let inputLengthInBytes: Int
    let replacementEffect: String
    let algorithm: String
    let duration: Int
}

struct FuckYouSwift: Hashable, Identifiable {
    let input: String
    let algorithm: String
    let averageDurationPerByte: Double

    init(input: String, algorithm: String, averageDurationPerByte: Double = .nan) {
        self.input = input
        self.algorithm = algorithm
        self.averageDurationPerByte = averageDurationPerByte
    }

    func hash(into hasher: inout Hasher) {
        input.hash(into: &hasher)
        algorithm.hash(into: &hasher)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.input == rhs.input && lhs.algorithm == rhs.algorithm
    }

    var id: String { input + "\0" + algorithm }
}

let emptyStringInput = "Empty string"
let lineWidth: CGFloat = 3
let comparisonAcrossInputsInput = "Comparison across inputs"

let inputOrder = [
    "Empty ",
    "No ",
    "Few ",
    "Many ",
    "Only "
]

struct ContentView: View {
    @State var data: [Record] = []
    @State var showFileImporter = true
    @State var algorithmEnabled: [String: Bool] = [:]
    @State var algorithmColour: [String: Color] = [:]
    @State var algorithmSymbol: [String: BasicChartSymbolShape] = [:]
    @State var algorithmStrokeStyle: [String: StrokeStyle] = [:]

    let algorithmKeyphraseToSymbol: [(Regex, BasicChartSymbolShape)] = [(/N-pass via replac(?:e|ing)$/, .square),
                                                                        (/replacingOccurrences/, .circle),
                                                                        (/character enumeration & concatenation/, .cross),
                                                                        (/firstIndex\(where:\)/, .triangle),
                                                                        (/map & join/, .asterisk)]

    let algorithmKeyphraseToStrokeStyle: [(Regex, StrokeStyle)] = [(/\ \(Dictionary of replacements instead of Array\)/, .init(lineWidth: lineWidth, dash: [3.2, 3.2]))]

    let colourPalette: [Color] = [(221, 221, 221),
                                  (46, 37, 133),
                                  (51, 117, 56),
                                  (93, 168, 153),
                                  (148, 203, 236),
                                  (220, 205, 125),
                                  (194, 106, 119),
                                  (159, 74, 150),
                                  (126, 41, 84)].map { Color(.displayP3, red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) }

    @State var selectedInput: String? = nil
    @State var selectedReplacementEffect: String? = nil

    @State var xDomainMin: Double = 0
    @State var xDomainMax: Double = .infinity

    @State var normaliseByInputByteLength = false
    @State var showASCIIInputsInComparisonChart = false

    static func inputOrderIndex(_ input: String) -> Int? {
        for (i, prefix) in inputOrder.enumerated() {
            if input.hasPrefix(prefix) {
                return i
            }
        }

        return nil
    }

    static func orderInputs(_ a: String, _ b: String) -> Bool {
        guard let aIndex = inputOrderIndex(a) else {
            return true
        }

        guard let bIndex = inputOrderIndex(b) else {
            return false
        }

        if aIndex < bIndex {
            return true
        } else if aIndex > bIndex {
            return false
        } else {
            return a < b
        }
    }

    func fuckYouSwift(_ selectedData: [Record]) -> [FuckYouSwift] {
        let fuckYouFuckingSwift: [FuckYouSwift: Double] = Dictionary(grouping: selectedData.lazy.filter {
            showASCIIInputsInComparisonChart == ($0.input.hasSuffix(" (ASCII)") as Bool)
        }) {
            FuckYouSwift(input: $0.input, algorithm: $0.algorithm)
        }.mapValues {
            Double($0.lazy
                .map { $0.duration / $0.inputLengthInBytes }
                .reduce(0, +))
            / Double($0.count)
        }

        return fuckYouFuckingSwift
            .map { FuckYouSwift(input: $0.input, algorithm: $0.algorithm, averageDurationPerByte: $1) }
            .sorted {
                $0.algorithm < $1.algorithm
                || ($0.algorithm == $1.algorithm
                    && Self.orderInputs($0.input, $1.input)) }
    }

    @Environment(\.displayScale) var displayScale

    @State var chartSize = CGSize(width: 0, height: 0)

    var body: some View {
        VStack {
            let preSelectedData = data.lazy
                .filter {
                    ($0.input == selectedInput
                     || (comparisonAcrossInputsInput == selectedInput
                         && emptyStringInput != $0.input))
                    && $0.replacementEffect == selectedReplacementEffect
                    && algorithmEnabled[$0.algorithm] ?? true }
                .sorted {
                    $0.algorithm < $1.algorithm
                    || ($0.algorithm == $1.algorithm
                        && $0.inputLengthInBytes < $1.inputLengthInBytes) }
            let xDomain = Set(preSelectedData.lazy.map(\.inputLengthInBytes)).sorted()

            HStack {
                Button("Import data…") {
                    showFileImporter = true
                }.fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.tabSeparatedText]) { result in
                    if let url = try? result.get() {
                        var newData = Array<Record>()
                        let parseStrategy = IntegerParseStrategy(format: IntegerFormatStyle<Int>.number, lenient: true)

                        for (i, line) in try! String(contentsOf: url, encoding: .utf8).lazy.split(whereSeparator: \.isNewline).enumerated() {
                            let cells = line.split(separator: "\t").map(String.init)

                            guard 7 == cells.count else {
                                fatalError("Encountered a line in the input that does not have the expected number of cells - should be seven, but it has \(cells.count): \(line)")
                            }

                            newData.append(Record(id: i,
                                                  input: cells[0],
                                                  inputLengthInCharacters: (try? Int(cells[1], strategy: parseStrategy)) ?? 0,
                                                  inputLengthInBytes: (try? Int(cells[2], strategy: parseStrategy)) ?? 0,
                                                  replacementEffect: cells[3],
                                                  algorithm: cells[4],
                                                  duration: try! Int(cells[6], strategy: parseStrategy)))
                        }

                        data = newData

                        var colourIndex = 0

                        for algorithm in Set(data.lazy.map(\.algorithm)).sorted() {
                            algorithmSymbol[algorithm] = algorithmKeyphraseToSymbol.first { algorithm.contains($0.0) }?.1

                            let strokeStyleMatch = algorithmKeyphraseToStrokeStyle.first { algorithm.contains($0.0) }
                            algorithmStrokeStyle[algorithm] = strokeStyleMatch?.1

                            if let strokeStyleMatch, let baseColour = algorithmColour[algorithm.replacing(strokeStyleMatch.0, with: "")] {
                                algorithmColour[algorithm] = baseColour
                            } else {
                                algorithmColour[algorithm] = colourPalette[colourIndex % colourPalette.count]
                                colourIndex += 1
                            }
                        }

                        selectedInput = data.first?.input
                        selectedReplacementEffect = data.first?.replacementEffect
                    }
                }

                let applicableReplacementEffects = Set(data.lazy
                    .filter {
                        $0.input == selectedInput
                        || (comparisonAcrossInputsInput == selectedInput
                            && emptyStringInput != $0.input) }
                    .map(\.replacementEffect))
                    .sorted()

                Picker("Input", selection: $selectedInput) {
                    ForEach(Set(data.lazy.map(\.input)).sorted(by: Self.orderInputs) + [comparisonAcrossInputsInput], id: \.self) {
                        Text($0).tag($0)
                    }
                }.onChange(of: selectedInput) { oldValue, newValue in
                    if newValue != oldValue {
                        guard let effect = selectedReplacementEffect, applicableReplacementEffects.contains(effect) else {
                            let newReplacementEffect = applicableReplacementEffects.sorted().first
                            print("Selected replacement effect (\(selectedReplacementEffect.orNilString)) is no longer valid (input changed from \(oldValue.orNilString) to \(newValue.orNilString)), so setting it to \(newReplacementEffect.orNilString).")
                            selectedReplacementEffect = newReplacementEffect
                            return
                        }
                    }
                }

                Picker("Replacement effect", selection: $selectedReplacementEffect) {
                    ForEach(applicableReplacementEffects, id: \.self) {
                        Text($0).tag($0)
                    }
                }.disabled(1 >= applicableReplacementEffects.count)

                Slider(value: $xDomainMin, in: 0...Double(max(1, xDomain.count - 1)), step: 1, label: { Text("X min") })
                    .disabled(xDomain.isEmpty)
                    .opacity(emptyStringInput == selectedInput ? 0.0 : 1.0)
                    .onChange(of: xDomainMax) { _, newValue in
                        if xDomainMin > newValue {
                            xDomainMin = newValue
                        }
                    }

                Slider(value: $xDomainMax, in: 0...Double(max(1, xDomain.count - 1)), step: 1, label: { Text("X max") })
                    .disabled(xDomain.isEmpty)
                    .opacity(emptyStringInput == selectedInput ? 0.0 : 1.0)
                    .onChange(of: xDomainMin) { _, newValue in
                        if newValue > xDomainMax {
                            xDomainMax = newValue
                        }
                    }
            }.padding()

            HStack {
                Toggle("Normalise by input byte length",
                       isOn: Binding(get: { comparisonAcrossInputsInput == selectedInput || (emptyStringInput != selectedInput && normaliseByInputByteLength) },
                                     set: { normaliseByInputByteLength = $0 }))
                    .disabled(emptyStringInput == selectedInput || comparisonAcrossInputsInput == selectedInput)

                Toggle("ASCII inputs", isOn: $showASCIIInputsInComparisonChart)
                    .disabled(comparisonAcrossInputsInput != selectedInput)
                    .opacity(comparisonAcrossInputsInput == selectedInput ? 1 : 0)
                    .padding(.leading)
            }

            VStack(alignment: .leading) {
                ForEach(Set(data.lazy.map(\.algorithm)).sorted(), id: \.self) { algorithm in
                    Toggle(algorithm,
                           isOn: Binding(get: { algorithmEnabled[algorithm] ?? true },
                                         set: { algorithmEnabled[algorithm] = $0 }))
                }
            }.padding()

            let (chart, title) = chart(preSelectedData: preSelectedData, xDomain: xDomain)

            chart
                .onDrag {
                    let renderer = ImageRenderer(content: chart.frame(width: chartSize.width, height: chartSize.height))

                    renderer.isOpaque = false
                    renderer.scale = displayScale
                    renderer.colorMode = .extendedLinear

                    let result = NSItemProvider()

                    result.suggestedName = title

                    guard let image = renderer.nsImage else {
                        print("Unable to render chart as an NSImage.")
                        return result
                    }

                    print("Providing file for drag…")

                    let folder: URL

                    do {
                        folder = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: .temporaryDirectory, create: true)
                    } catch {
                        print("Unable to create temporary folder, error:", error)
                        result.registerObject(image, visibility: .all)
                        return result
                    }

                    let url = folder.appending(path: title + ".tiff", directoryHint: .notDirectory)

                    print("Writing temporary file for drag to:", url)

                    guard let tiffData = image.tiffRepresentation(using: .lzw, factor: 1) else {
                        print("Unable to save image as a TIFF.")
                        result.registerObject(image, visibility: .all)
                        return result
                    }

                    do {
                        try tiffData.write(to: url, options: .withoutOverwriting)
                    } catch {
                        print("Unable to write image, as a TIFF, to \(url), error:", error)
                        result.registerObject(image, visibility: .all)
                        return result
                    }

                    result.registerObject(url as NSURL, visibility: .all)
                    result.registerObject(image, visibility: .all)

                    return result
                }
                .overlay {
                    GeometryReader { geometryProxy in
                        let size = geometryProxy.size

                        print("Chart size will change:", size)

                        DispatchQueue.main.async {
                            chartSize = size
                            print("Chart size changed:", chartSize)
                        }

                        return Rectangle().opacity(0)
                    }
                }
        }

        Spacer(minLength: 0)
    }

    func chart(preSelectedData: [Record], xDomain: [Int]) -> (AnyView, String) {
        let restrictedXDomain = Array(xDomain.dropFirst(Int(xDomainMin)).dropLast(max(0, xDomain.count - Int(min(Double(xDomain.count), xDomainMax)) - 1)))
        let restrictedXDomainRange = (restrictedXDomain.first ?? 1)...(restrictedXDomain.last ?? 1)
        let selectedData = preSelectedData.filter { restrictedXDomainRange.contains($0.inputLengthInBytes) }

        if emptyStringInput == selectedInput {
            let emptyStringData = data.filter { emptyStringInput == $0.input }.map(\.duration)
            let xRange = __exp10(log10(Double(emptyStringData.min() ?? 1)).rounded(.down))...__exp10(log10(Double(emptyStringData.max() ?? 1)).rounded(.up))

            return (
                AnyView(
                    Chart {
                        ForEach(data.lazy.filter { emptyStringInput == $0.input && algorithmEnabled[$0.algorithm] ?? true }) { datum in
                            BarMark(x: .value("Runtime", datum.duration),
                                    y: .value("Algorithm", datum.algorithm))
                            .foregroundStyle(by: .value("Algorithm", datum.algorithm))
                            .annotation(position: .overlay, alignment: .trailing, spacing: nil) {
                                Text("\(Measurement(value: Double(datum.duration), unit: UnitDuration.nanoseconds).simplified.formatted(.measurement(width: .abbreviated)))").font(.caption)
                            }
                        }
                    }
                        .chartLegend(.hidden)
                        .chartForegroundStyleScale { // This is required for the legend to be drawn.
                            algorithmColour[$0] ?? .black
                        }
                        .chartXScale(domain: xRange, type: .linear) // Should be .log, but Swift Charts has a bug whereby using .log here results in no bars being rendered at all. 😤
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisValueLabel(centered: true, anchor: .trailing)
                            }
                        }
                        .chartXAxis {
                            AxisMarks {
                                if let value = $0.as(Double.self) {
                                    AxisValueLabel(Measurement(value: value, unit: UnitDuration.nanoseconds).simplified.formatted(.measurement(width: .abbreviated)))
                                } else {
                                    let _ = print("X axis (runtime) value is not an integer.")
                                }

                                AxisTick()
                                AxisGridLine()
                            }
                        }
                        .padding()
                        .padding(.leading, 1200)),
                "Empty string")
        } else if comparisonAcrossInputsInput == selectedInput {
            let aggregatedSelectedData = fuckYouSwift(selectedData)

            let title = "Comparison across \(showASCIIInputsInComparisonChart ? "ASCII " : "")inputs"

            let fuckYouSwift = restrictedXDomain.map(Int64.init).formatted(.list(memberStyle: ByteCountFormatStyle(style: .decimal),
                                                                                 type: .and,
                                                                                 width: .short))

            let subtitle: String? = if let restrictedXDomainMin = restrictedXDomain.first {
                if 1 < restrictedXDomain.count {
                    "Mean of input byte lengths \(fuckYouSwift)"
                } else {
                    "Input byte length \(restrictedXDomainMin.formatted())"
                }
            } else {
                nil
            }

            let fileTitle = if let subtitle {
                "\(title) (\(subtitle))"
            } else {
                title
            }

            return (
                AnyView(
                    Chart {
                        ForEach(aggregatedSelectedData) {
                            LineMark(x: .value("Input", $0.input),
                                     y: .value("Mean runtime per byte", $0.averageDurationPerByte),
                                     series: .value("Algorithm", $0.algorithm))
                            .foregroundStyle(by: .value("Algorithm", $0.algorithm)) // This is required in order for .chartForegroundStyleScale to work, and therefore for the legend to be drawn.
                            .lineStyle(by: .value("Algorithm", $0.algorithm)) // Similar to the above, for .chartLineStyleScale, and to have the line style reflected in the legend.
                            .symbol(by: .value("Algorithm", $0.algorithm)) // And likewise, this indirect method has to be used otherwise the legend doesn't reflect the symbols (even though the data series' do).
                                                                           //                            .foregroundStyle(algorithmStyles[$0.0.algorithm] ?? .black) // If you use this you cannot use chart legends (Swift Charts just silently refuses to render them), and that is not documented anywhere.  But plenty of Apple sample code & documentation recommends using this modifier anyway. 😤
                        }
                    }.chartPlotStyle {
                        $0.frame(maxWidth: 600, maxHeight: 500)
                    }
                        .chartLegend(position: .trailing, alignment: .leading, spacing: 30)
                        .chartForegroundStyleScale { // This is required for the legend to be drawn.
                            algorithmColour[$0] ?? .black
                        }
                        .chartSymbolScale {
                            (algorithmSymbol[$0] ?? .pentagon)
                        }
                        .chartLineStyleScale {
                            algorithmStrokeStyle[$0] ?? .init(lineWidth: lineWidth)
                        }
                        .chartYScale(type: .log)
                        .chartYAxis {
                            AxisMarks {
                                if let value = $0.as(Double.self) {
                                    AxisValueLabel(Measurement(value: value, unit: UnitDuration.nanoseconds).simplified.formatted(.measurement(width: .abbreviated)))
                                } else {
                                    let _ = print("Y axis (runtime) value is not an integer.")
                                }

                                AxisTick()
                                AxisGridLine()
                            }
                        }
                        .chartXAxisLabel("Input", alignment: .center)
                        .chartYAxisLabel("Runtime per input byte",
                                         position: .trailing,
                                         alignment: .center,
                                         spacing: normaliseByInputByteLength ? 0 : -10) // Spacing hack to make the non-normalised version look aesthetically correct, with the results on an M2 MacBook Air.  May be wrong for any other numbers (typically depends on the worst-case performance, as that determines the width of the Y axis labels bounding box).
                        .chartXAxisLabel(position: .top, alignment: .center, spacing: 10) {
                            let result = if let subtitle {
                                Text("""
                                     \(Text(title).font(.headline))
                                     \(Text(subtitle).font(.subheadline))
                                     """)
                            } else {
                                Text(title).font(.headline)
                            }

                            return result.multilineTextAlignment(.center)
                        }
                        .padding()
                        .padding(.leading, 20)),
                fileTitle)
        } else {
            let nonEmptyStringData = data.lazy.filter { emptyStringInput != $0.input && restrictedXDomainRange.contains($0.inputLengthInBytes) }.map { normaliseByInputByteLength ? $0.duration / $0.inputLengthInBytes : $0.duration }
            let yRange = (false // i.e. whether to use the Y range naively as-is, or expand it outwards to even multiples of 10 (which helps neaten up the display when using a log Y axis).
                          ? Double(nonEmptyStringData.min() ?? 1)...Double(nonEmptyStringData.max() ?? 1)
                          : __exp10(log10(Double(nonEmptyStringData.min() ?? 1)).rounded(.down))...__exp10(log10(Double(nonEmptyStringData.max() ?? 1)).rounded(.up)))

            let _ = print("X-axis domain: \(xDomain)\(xDomain != restrictedXDomain ? " (restricted to: \(restrictedXDomain))" : ""), Y-axis range: \(yRange)")

            let title = selectedInput
            let subtitle = selectedReplacementEffect

            let fileTitle = if let title {
                if let subtitle {
                    "\(title) (\(subtitle))"
                } else {
                    title
                }
            } else {
                "Unknown"
            }

            return (
                AnyView(
                    Chart {
                        ForEach(selectedData) {
                            LineMark(x: .value("Input length", $0.inputLengthInBytes),
                                     y: (normaliseByInputByteLength
                                         ? .value("Runtime per input byte", $0.duration / $0.inputLengthInBytes)
                                         : .value("Runtime", $0.duration)),
                                     series: .value("Algorithm", $0.algorithm))
                            .foregroundStyle(by: .value("Algorithm", $0.algorithm)) // This is required in order for .chartForegroundStyleScale to work, and therefore for the legend to be drawn.
                            .lineStyle(by: .value("Algorithm", $0.algorithm)) // Similar to the above, for .chartLineStyleScale, and to have the line style reflected in the legend.
                            .symbol(by: .value("Algorithm", $0.algorithm)) // And likewise, this indirect method has to be used otherwise the legend doesn't reflect the symbols (even though the data series' do).
                                                                           //                            .foregroundStyle(algorithmStyles[$0.algorithm] ?? .black) // If you use this you cannot use chart legends (Swift Charts just silently refuses to render them), and that is not documented anywhere.  But plenty of Apple sample code & documentation recommends using this modifier anyway. 😤
                        }
                    }.chartPlotStyle {
                        $0.frame(maxWidth: 600, maxHeight: 500)
                    }
                    .chartLegend(position: .trailing, alignment: .leading, spacing: 30) /*{
                        VStack() {
                            let algorithms = Set(selectedData.map(\.algorithm)).sorted()

//                            ForEach(algorithms, id: \String.self) { // The compiler just hangs if ForEach is used inside the chartLegend contents, irrespective of what collection or ID keypath is used. 😤
//                                HStack {
//                                    $0.symbol
//                                        .frame(width: 10, height: 10)
//                                        .foregroundColor(algorithmColour[$0] ?? .black)
//                                    Text($0).foregroundColor(.black)
//                                }
//                            }
                        }
                    }*/
                    .chartForegroundStyleScale { // This is required for the legend to be drawn.
                        algorithmColour[$0] ?? .black
                    }
                    .chartSymbolScale {
                        (algorithmSymbol[$0] ?? .pentagon)
                    }
//                    .chartSymbolSizeScale { // The compiler just hangs if this modifier is used, irrespective of what its contents are. 😤
//                        min(4, lineWidth)
//                    }
                    .chartLineStyleScale {
                        algorithmStrokeStyle[$0] ?? .init(lineWidth: lineWidth)
                    }
                    .chartYScale(domain: yRange, type: .log)
                    .chartYAxis {
                        AxisMarks {
                            if let value = $0.as(Double.self) {
                                AxisValueLabel(Measurement(value: value, unit: UnitDuration.nanoseconds).simplified.formatted(.measurement(width: .abbreviated)))
                            } else {
                                let _ = print("Y axis value is not an integer.")
                            }

                            AxisTick()
                            AxisGridLine()
                        }
                    }
                    .chartXScale(domain: restrictedXDomainRange, type: .log)
                    .chartXAxis {
                        AxisMarks(preset: .aligned, values: restrictedXDomain) {
                            if let value = $0.as(Int.self) {
                                AxisValueLabel(value.formatted(.byteCount(style: .decimal)))
                            } else {
                                let _ = print("X axis value is not an integer.")
                            }

                            AxisTick()
                            AxisGridLine()
                        }
                    }
                    .chartXAxisLabel("Input length", alignment: .center)
                    .chartYAxisLabel(normaliseByInputByteLength ? "Runtime per input byte" : "Runtime",
                                     position: .trailing,
                                     alignment: .center,
                                     spacing: 10) // -10) // -10 is a spacing hack to make the layout look decent for charts showing the full dataset, with the results on an M2 MacBook Air.  May be wrong for any other benchmark results (typically depends on the worst-case performance, as that determines the width of the Y axis labels bounding box).
                    .chartXAxisLabel(position: .top, alignment: .center, spacing: 10) {
                        if let title {
                            if let subtitle {
                                Text("""
                                     \(Text(title).font(.headline))
                                     \(Text(subtitle).font(.subheadline))
                                     """).multilineTextAlignment(.center)
                            } else {
                                Text(title).font(.headline)
                            }
                        }
                    }
                    .padding()
                    .padding(.leading, 20)),
                fileTitle)
        }
    }
}

extension Measurement where UnitType == UnitDuration {
    var simplified: Self {
        var measurement = self

        for unit in [UnitDuration.seconds, .milliseconds, .microseconds, .nanoseconds, .picoseconds] {
            measurement.convert(to: unit)

            if 1 <= measurement.value {
                break
            }
        }

        return measurement
    }
}

extension Optional where Wrapped == String {
    var orNilString: String {
        if let value = self {
            "\"\(value)\""
        } else {
            "nil"
        }
    }
}

#Preview {
    ContentView()
}
