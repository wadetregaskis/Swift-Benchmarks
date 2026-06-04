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

// MARK: - Shared styling

let colourPalette: [Color] = [(221, 221, 221),
                              (46, 37, 133),
                              (51, 117, 56),
                              (93, 168, 153),
                              (148, 203, 236),
                              (220, 205, 125),
                              (194, 106, 119),
                              (159, 74, 150),
                              (126, 41, 84)].map { Color(.displayP3, red: $0.0 / 255, green: $0.1 / 255, blue: $0.2 / 255) }

let symbolPalette: [BasicChartSymbolShape] = [.circle, .square, .triangle, .diamond, .cross, .pentagon, .plus, .asterisk]

/// Renders a chart image to a temporary file and bundles it (plus the raw image) into an `NSItemProvider`, so a chart can be
/// dragged out of the app as a file or pasted as an image.
func chartDragProvider(title: String, image: NSImage?) -> NSItemProvider {
    let provider = NSItemProvider()
    let name = title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    provider.suggestedName = name

    guard let image else {
        print("Unable to render chart as an NSImage.")
        return provider
    }

    if let folder = try? FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: .temporaryDirectory, create: true),
       let tiff = image.tiffRepresentation(using: .lzw, factor: 1) {
        let url = folder.appending(path: (name.isEmpty ? "Chart" : name) + ".tiff", directoryHint: .notDirectory)
        try? tiff.write(to: url, options: .withoutOverwriting)
        provider.registerObject(url as NSURL, visibility: .all)
    }

    provider.registerObject(image, visibility: .all)
    return provider
}

// MARK: - Router

/// Imports a TSV and routes to the right renderer.  A file with a header row (first line entirely non-numeric) is treated as a
/// general, self-describing dataset; a headerless file is the legacy StringReplacement seven-column format.
struct ContentView: View {
    @State private var showFileImporter = true
    @State private var legacyRecords: [Record]? = nil
    @State private var genericDataset: GenericDataset? = nil
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack {
            HStack {
                Button("Import data…") { showFileImporter = true }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .padding(.top)

            if let genericDataset {
                GenericChartView(dataset: genericDataset)
            } else if let legacyRecords {
                StringReplacementView(records: legacyRecords)
            } else {
                Spacer()
                Text("Import a benchmark results TSV to begin.").foregroundStyle(.secondary)
                Spacer()
            }
        }
        .fileImporter(isPresented: $showFileImporter, allowedContentTypes: [.tabSeparatedText, .plainText, .text]) { result in
            guard let url = try? result.get() else { return }
            load(url)
        }
    }

    private func load(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = "Couldn't read \(url.lastPathComponent)."
            return
        }

        let lines = content.split(whereSeparator: \.isNewline)
        guard let firstLine = lines.first else {
            errorMessage = "\(url.lastPathComponent) is empty."
            return
        }

        let firstCells = firstLine.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        let hasHeader = !firstCells.isEmpty && firstCells.allSatisfy { Double($0) == nil }

        errorMessage = nil

        if hasHeader, let dataset = GenericDataset(lines: Array(lines)) {
            genericDataset = dataset
            legacyRecords = nil
        } else {
            genericDataset = nil
            legacyRecords = Self.parseLegacy(Array(lines))
        }
    }

    static func parseLegacy(_ lines: [Substring]) -> [Record] {
        let parseStrategy = IntegerParseStrategy(format: IntegerFormatStyle<Int>.number, lenient: true)
        var records: [Record] = []

        for (i, line) in lines.enumerated() {
            let cells = line.split(separator: "\t").map(String.init)

            guard cells.count == 7 else {
                fatalError("Encountered a line in the input that does not have the expected number of cells - should be seven, but it has \(cells.count): \(line)")
            }

            records.append(Record(id: i,
                                  input: cells[0],
                                  inputLengthInCharacters: (try? Int(cells[1], strategy: parseStrategy)) ?? 0,
                                  inputLengthInBytes: (try? Int(cells[2], strategy: parseStrategy)) ?? 0,
                                  replacementEffect: cells[3],
                                  algorithm: cells[4],
                                  duration: (try? Int(cells[6], strategy: parseStrategy)) ?? 0))
        }

        return records
    }
}

// MARK: - Generic, schema-driven dataset

/// A self-describing tabular dataset parsed from a headed TSV.  Columns whose every value parses as a number are "numeric";
/// the rest are categorical.  One numeric column is singled out as the *measure* (what's plotted on the Y axis).
struct GenericDataset {
    let columns: [String]
    let rows: [[String: String]]
    let numericColumns: Set<String>
    let measureColumn: String

    init?(lines: [Substring]) {
        guard let header = lines.first else { return nil }

        let columns = header.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard columns.count >= 2 else { return nil }

        var rows: [[String: String]] = []

        for line in lines.dropFirst() {
            let cells = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cells.count == columns.count else { continue }
            rows.append(Dictionary(uniqueKeysWithValues: zip(columns, cells)))
        }

        guard !rows.isEmpty else { return nil }

        let numeric = Set(columns.filter { column in
            let values = rows.compactMap { $0[column] }.filter { !$0.isEmpty }
            return !values.isEmpty && values.allSatisfy { Double($0) != nil }
        })

        // Prefer a duration-ish numeric column as the measure; otherwise just the last numeric column.
        let measureKeywords = ["nanosecond", "microsecond", "millisecond", "second", "duration", "time", "wallclock", "latency"]
        self.measureColumn = columns.last { numeric.contains($0) && measureKeywords.contains(where: $0.lowercased().contains) }
            ?? columns.last { numeric.contains($0) }
            ?? columns.last!
        self.columns = columns
        self.rows = rows
        self.numericColumns = numeric
    }

    func distinctValues(_ column: String) -> [String] {
        let values = Set(rows.compactMap { $0[column] })

        if numericColumns.contains(column) {
            return values.sorted { (Double($0) ?? 0) < (Double($1) ?? 0) }
        }

        return values.sorted()
    }
}

// MARK: - Generic, schema-driven chart

/// One line chart of measure-vs-X, one line per series value, with a picker for the X axis (any numeric column), a picker for
/// the series (any categorical column), and a slicer picker for every other column.  This is what renders the StringBuilding
/// benchmark, and any future headed dataset.
struct GenericChartView: View {
    let dataset: GenericDataset

    @State private var xColumn = ""
    @State private var seriesColumn = ""
    @State private var normaliseColumn: String? = nil
    @State private var slicerSelections: [String: String] = [:]
    @State private var seriesEnabled: [String: Bool] = [:]
    @State private var seriesColour: [String: Color] = [:]
    @State private var seriesSymbol: [String: BasicChartSymbolShape] = [:]
    @State private var showLegend = true
    @State private var logX = true
    @State private var logY = true
    @State private var didSetup = false

    @Environment(\.displayScale) private var displayScale

    private var xCandidates: [String] { dataset.columns.filter { dataset.numericColumns.contains($0) && $0 != dataset.measureColumn } }
    private var categoricalColumns: [String] { dataset.columns.filter { !dataset.numericColumns.contains($0) } }
    private var slicerColumns: [String] { dataset.columns.filter { $0 != xColumn && $0 != seriesColumn && $0 != dataset.measureColumn } }

    private func numeric(_ row: [String: String], _ column: String) -> Double? {
        row[column].flatMap(Double.init)
    }

    var body: some View {
        VStack(spacing: 8) {
            controls

            ScrollView {
                VStack(alignment: .leading) {
                    ForEach(dataset.distinctValues(seriesColumn), id: \.self) { value in
                        Toggle(value, isOn: Binding(get: { seriesEnabled[value] ?? true },
                                                    set: { seriesEnabled[value] = $0 }))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
            .padding(.horizontal)

            chart
        }
        .onAppear(perform: setup)

        Spacer(minLength: 0)
    }

    private var controls: some View {
        VStack {
            HStack {
                Picker("X axis", selection: $xColumn) {
                    ForEach(xCandidates, id: \.self) { Text($0).tag($0) }
                }.fixedSize()

                Picker("Series", selection: $seriesColumn) {
                    ForEach(categoricalColumns, id: \.self) { Text($0).tag($0) }
                }.fixedSize()

                Picker("Normalise by", selection: $normaliseColumn) {
                    Text("None").tag(String?.none)
                    ForEach(xCandidates, id: \.self) { Text($0).tag(String?.some($0)) }
                }.fixedSize()

                Toggle("Legend", isOn: $showLegend)
                Toggle("log X", isOn: $logX)
                Toggle("log Y", isOn: $logY)
            }
            .onChange(of: seriesColumn) { _, _ in
                seriesEnabled.removeAll()
                assignSeriesStyles()
                refreshSlicers()
            }
            .onChange(of: xColumn) { _, _ in refreshSlicers() }

            ScrollView(.horizontal) {
                HStack {
                    ForEach(slicerColumns, id: \.self) { column in
                        Picker(column, selection: Binding(get: { slicerSelections[column] ?? dataset.distinctValues(column).first ?? "" },
                                                          set: { slicerSelections[column] = $0 })) {
                            ForEach(dataset.distinctValues(column), id: \.self) { value in
                                Text(displayValue(value, column)).tag(value)
                            }
                        }.fixedSize()
                    }
                }
            }
        }
        .padding(.horizontal)
    }

    private var chart: some View {
        let rows = filteredRows

        return chartCore(rows)
            .frame(width: 700, height: 500)
            .padding()
            .onDrag {
                let renderer = ImageRenderer(content: chartCore(rows).frame(width: 700, height: 500).padding())
                renderer.isOpaque = false
                renderer.scale = displayScale
                renderer.colorMode = .extendedLinear
                return chartDragProvider(title: chartTitle, image: renderer.nsImage)
            }
    }

    private func chartCore(_ rows: [[String: String]]) -> some View {
        let xs = rows.compactMap { numeric($0, xColumn) }
        let ys = rows.map(yValue)
        let useLogX = logX && (xs.min() ?? 0) > 0
        let useLogY = logY && (ys.min() ?? 0) > 0

        return Chart {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                let series = row[seriesColumn] ?? ""

                LineMark(x: .value(xColumn, numeric(row, xColumn) ?? 0),
                         y: .value(yAxisLabel, yValue(row)),
                         series: .value(seriesColumn, series))
                .foregroundStyle(by: .value(seriesColumn, series))
                .symbol(by: .value(seriesColumn, series))
            }
        }
        .chartForegroundStyleScale { seriesColour[$0] ?? .gray }
        .chartSymbolScale { seriesSymbol[$0] ?? BasicChartSymbolShape.circle }
        .chartXScale(domain: .automatic, type: useLogX ? .log : .linear)
        .chartYScale(domain: .automatic, type: useLogY ? .log : .linear)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 6)) { value in
                if let v = value.as(Double.self) { AxisValueLabel(formatX(v)) }
                AxisTick()
                AxisGridLine()
            }
        }
        .chartYAxis {
            AxisMarks { value in
                if let v = value.as(Double.self) { AxisValueLabel(formatMeasure(v)) }
                AxisTick()
                AxisGridLine()
            }
        }
        .chartXAxisLabel(xColumn, alignment: .center)
        .chartYAxisLabel(yAxisLabel, position: .trailing, alignment: .center)
        .chartLegend(showLegend ? .visible : .hidden)
        .chartLegend(position: .trailing, alignment: .top, spacing: 16)
    }

    private var filteredRows: [[String: String]] {
        dataset.rows
            .filter { row in
                (seriesEnabled[row[seriesColumn] ?? ""] ?? true)
                && slicerColumns.allSatisfy { row[$0] == (slicerSelections[$0] ?? dataset.distinctValues($0).first) }
            }
            .sorted { (numeric($0, xColumn) ?? 0) < (numeric($1, xColumn) ?? 0) }
    }

    private func yValue(_ row: [String: String]) -> Double {
        let measure = numeric(row, dataset.measureColumn) ?? 0

        if let normaliseColumn, let denominator = numeric(row, normaliseColumn), denominator != 0 {
            return measure / denominator
        }

        return measure
    }

    private var yAxisLabel: String {
        if let normaliseColumn { return "\(dataset.measureColumn) / \(normaliseColumn)" }
        return dataset.measureColumn
    }

    private var chartTitle: String {
        slicerColumns
            .map { "\($0)=\(slicerSelections[$0] ?? dataset.distinctValues($0).first ?? "")" }
            .joined(separator: ", ")
    }

    private var measureIsDuration: Bool { dataset.measureColumn.lowercased().contains("nanosecond") }

    private func formatMeasure(_ value: Double) -> String {
        if measureIsDuration && normaliseColumn == nil {
            return Measurement(value: value, unit: UnitDuration.nanoseconds).simplified.formatted(.measurement(width: .abbreviated))
        }

        return value.formatted(.number.precision(.significantDigits(1...3)))
    }

    private func formatX(_ value: Double) -> String {
        if xColumn.lowercased().contains("byte") { return Int(value).formatted(.byteCount(style: .binary)) }
        return value.formatted(.number)
    }

    private func displayValue(_ value: String, _ column: String) -> String {
        if dataset.numericColumns.contains(column), let number = Double(value), column.lowercased().contains("byte") {
            return Int(number).formatted(.byteCount(style: .binary))
        }

        return value
    }

    private func setup() {
        guard !didSetup else { return }
        didSetup = true

        xColumn = xCandidates.first ?? dataset.columns.first ?? ""
        seriesColumn = categoricalColumns.first { $0.lowercased() == "algorithm" } ?? categoricalColumns.last ?? dataset.columns.first ?? ""

        assignSeriesStyles()
        refreshSlicers()
    }

    private func assignSeriesStyles() {
        for (i, value) in dataset.distinctValues(seriesColumn).enumerated() {
            seriesColour[value] = colourPalette[(i + 1) % colourPalette.count] // +1 so the first series isn't the pale swatch.
            seriesSymbol[value] = symbolPalette[i % symbolPalette.count]
        }
    }

    private func refreshSlicers() {
        for column in slicerColumns where slicerSelections[column] == nil {
            slicerSelections[column] = defaultSlicerValue(column)
        }
    }

    /// The most common value in a column — a far better default slice than the minimum, since it lands on whichever value the
    /// bulk of the data shares (e.g. the main matrix's output size rather than a sparse scaling-sweep size).
    private func defaultSlicerValue(_ column: String) -> String {
        let counts = Dictionary(grouping: dataset.rows.compactMap { $0[column] }, by: { $0 }).mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key ?? dataset.distinctValues(column).first ?? ""
    }
}

struct StringReplacementView: View {
    let records: [Record]

    @State var data: [Record] = []
    @State var algorithmEnabled: [String: Bool] = [:]
    @State var algorithmColour: [String: Color] = [:]
    @State var algorithmSymbol: [String: BasicChartSymbolShape] = [:]
    @State var algorithmStrokeStyle: [String: StrokeStyle] = [:]

    let algorithmKeyphraseToSymbol: [(Regex, BasicChartSymbolShape)] = [(/N-pass via replac(?:e|ing)$/, .square),
                                                                        (/replacingOccurrences/, .circle),
                                                                        (/character enumeration & concatenation/, .cross),
                                                                        (/firstIndex\(where:\)/, .triangle),
                                                                        (/map & join/, .asterisk)]

    let algorithmKeyphraseToStrokeStyle: [(Regex, StrokeStyle)] = [(/\ \(Dictionary of replacements instead of Array\)/, .init(lineWidth: lineWidth, dash: [lineWidth, lineWidth]))]

    @State var selectedInput: String? = nil
    @State var selectedReplacementEffect: String? = nil

    @State var xDomainMin: Double = 0
    @State var xDomainMax: Double = .infinity

    @State var normaliseByInputByteLength = false
    @State var showASCIIInputsInComparisonChart = false

    @State var yAxisLabelPadding: CGFloat = 0
    @State var legendWidth: CGFloat = 400
    @State var swatchWidth: CGFloat = 0.5 + lineWidth + (2 * lineWidth * 4) // i.e. 27.5, for line width 3.  15.5 is another good option.

    @State var showLegend = true

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
                Toggle("Show legend",
                       isOn: Binding(get: { showLegend && emptyStringInput != selectedInput },
                                     set: { showLegend = $0 }))
                    .disabled(emptyStringInput == selectedInput)

                Toggle("Normalise by input byte length",
                       isOn: Binding(get: { comparisonAcrossInputsInput == selectedInput || (emptyStringInput != selectedInput && normaliseByInputByteLength) },
                                     set: { normaliseByInputByteLength = $0 }))
                    .disabled(emptyStringInput == selectedInput || comparisonAcrossInputsInput == selectedInput)
                    .padding(.leading)

                Toggle("ASCII inputs", isOn: $showASCIIInputsInComparisonChart)
                    .disabled(comparisonAcrossInputsInput != selectedInput)
                    .opacity(comparisonAcrossInputsInput == selectedInput ? 1 : 0)
                    .padding(.leading)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Y axis label padding:")

                    VStack {
                        Slider(value: $yAxisLabelPadding, in: -20...20, step: 1)
                            .frame(maxWidth: 200)
                            .padding(.leading)
                        Text("\(yAxisLabelPadding.formatted())").font(.caption)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Legend width:")

                    VStack {
                        Slider(value: $legendWidth, in: 100...1000, step: 1)
                            .frame(maxWidth: 200)
                            .padding(.leading)
                        Text("\(legendWidth.formatted())").font(.caption)
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("Swatch width:")

                    VStack {
                        Slider(value: $swatchWidth, in: lineWidth...(10 * lineWidth), step: 0.5)
                            .frame(maxWidth: 200)
                            .padding(.leading)
                        Text("\(swatchWidth.formatted())").font(.caption)
                    }
                }
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
        .onAppear(perform: load)

        Spacer(minLength: 0)
    }

    func load() {
        guard data.isEmpty else { return }

        data = records

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

    func chart(preSelectedData: [Record], xDomain: [Int]) -> (AnyView, String) {
        let restrictedXDomain = Array(xDomain.dropFirst(Int(xDomainMin)).dropLast(max(0, xDomain.count - Int(min(Double(xDomain.count), xDomainMax)) - 1)))
        let restrictedXDomainRange = (restrictedXDomain.first ?? 1)...(restrictedXDomain.last ?? 1)
        let selectedData = preSelectedData.filter { restrictedXDomainRange.contains($0.inputLengthInBytes) }

        if emptyStringInput == selectedInput {
            let emptyStringData = data
                .filter {
                    emptyStringInput == $0.input
                    && algorithmEnabled[$0.algorithm] ?? true
                }
                .sorted {
                    $0.algorithm < $1.algorithm
                }

            let xRange = __exp10(log10(Double(emptyStringData.lazy.map(\.duration).min() ?? 1)).rounded(.down))...__exp10(log10(Double(emptyStringData.lazy.map(\.duration).max() ?? 1)).rounded(.up))

            return (
                AnyView(
                    Chart {
                        ForEach(emptyStringData) { datum in
                            let labelProbablyFits = (log10(Double(datum.duration)) - log10(xRange.lowerBound)) > ((log10(xRange.upperBound) - log10(xRange.lowerBound)) / 5)

                            BarMark(xStart: .value("Runtime", Int(xRange.lowerBound)),
                                    xEnd: .value("Runtime", datum.duration),
                                    y: .value("Algorithm", datum.algorithm))
                            .foregroundStyle(by: .value("Algorithm", datum.algorithm))
                            .annotation(position: labelProbablyFits ? .overlay : .trailing,
                                        alignment: labelProbablyFits ? .trailing : .leading,
                                        spacing: nil) {
                                Text("\(Measurement(value: Double(datum.duration), unit: UnitDuration.nanoseconds).simplified.formatted(.measurement(width: .abbreviated)))")
                                    .font(.caption)
                                    .foregroundStyle(labelProbablyFits ? .white : Color(nsColor: .darkGray))
                            }
                        }
                    }
                        .chartLegend(.hidden)
                        .chartForegroundStyleScale { // This is required for the legend to be drawn.
                            algorithmColour[$0] ?? .black
                        }
                        .chartXScale(domain: xRange, type: .log)
                        .chartYAxis {
                            AxisMarks(position: .leading) {
                                AxisValueLabel(centered: true, anchor: .trailing)
                                    .font(.caption.width(.condensed))
                            }
                        }
                        .chartXAxis {
                            AxisMarks(preset: .aligned) {
                                if let value = $0.as(Double.self) {
                                    AxisValueLabel(Measurement(value: value, unit: UnitDuration.nanoseconds).simplified.formatted(.measurement(width: .abbreviated)))
                                } else {
                                    let _ = print("X axis (runtime) value is not an integer.")
                                }

                                AxisTick()
                                AxisGridLine()
                            }
                        }
                        .chartXAxisLabel("Runtime", position: .bottom, alignment: .center)
                        .chartXAxisLabel(position: .top, alignment: .center, spacing: 10) {
                            Text("Empty string").font(.headline)
                        }
                        .padding()
                        .padding(.leading, 1008)
                        .padding(.trailing, 18)),
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
                    }//.fontWidth(.condensed)
                        .foregroundStyle(.black)
                        .chartPlotStyle {
                            $0.frame(width: 700, height: 500)
                        }
                        .chartLegend(showLegend ? .visible : .hidden)
                        .chartLegend(position: .trailing, alignment: .leading, spacing: 30) { () in
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(Set(aggregatedSelectedData.lazy.map(\.algorithm)).sorted(),
                                        id: \.self) { (algorithm: String) -> HStack in
                                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                                        ZStack(alignment: .center) {
                                            Path {
                                                $0.move(to: .init(x: 0, y: lineWidth / 2))
                                                $0.addLine(to: CGPoint(x: swatchWidth, y: lineWidth / 2))
                                            }
                                                .stroke(style: algorithmStrokeStyle[algorithm] ?? .init(lineWidth: lineWidth))
                                                .frame(width: swatchWidth, height: lineWidth)
                                                .foregroundColor(algorithmColour[algorithm] ?? .black)

                                            (algorithmSymbol[algorithm] ?? .pentagon)
                                                .foregroundColor(algorithmColour[algorithm] ?? .black)
                                                .frame(width: lineWidth * 2.6666666666, height: lineWidth * 2.666666666)
                                        }.alignmentGuide(VerticalAlignment.firstTextBaseline) { _ in
                                            8
                                        }

                                        Text(algorithm)
                                            .foregroundColor(Color(nsColor: .darkGray))
                                            .font(.body.width(.condensed))
                                            .truncationMode(.middle)
                                            .allowsTightening(false)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                            }.frame(maxWidth: legendWidth)
                        }
                        .chartForegroundStyleScale { // This is required for the legend to be drawn.
                            algorithmColour[$0] ?? .black
                        }
                        .chartSymbolScale {
                            (algorithmSymbol[$0] ?? .pentagon).strokeBorder(lineWidth: .greatestFiniteMagnitude)
                        }
                        .chartLineStyleScale {
                            algorithmStrokeStyle[$0] ?? .init(lineWidth: lineWidth)
                        }
                        .chartYScale(type: .log)
//                        .chartXAxis {
//                            AxisMarks(preset: .aligned) {
//                                if let value = $0.as(String.self) {
//                                    AxisValueLabel(value, centered: true)
//                                } else {
//                                    let _ = print("X axis (input) value is not a string.")
//                                }
//
//                                AxisTick()
//                                AxisGridLine()
//                            }
//                        }
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
                                         spacing: yAxisLabelPadding)
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
                (fileTitle
                 + (normaliseByInputByteLength
                    ? " [normalised by input byte length]"
                    : "")
                 + (showLegend
                    ? ""
                    : ", sans legend")))
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
//                            .symbolSize(min(4, lineWidth)) // Symbols don't show up at all if this is used! 😤
//                            .symbolSize(by: .value("Algorithm", $0.algorithm))
                        }
                    }.fontWidth(.condensed)
                    .chartPlotStyle {
                        $0.frame(width: 700, height: 500)
                    }
                    .chartLegend(showLegend ? .visible : .hidden)
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
                        (algorithmSymbol[$0] ?? .pentagon).strokeBorder(lineWidth: .greatestFiniteMagnitude)
                    }
//                    .chartSymbolSizeScale { (_: String) in
//                        34
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
                                     spacing: yAxisLabelPadding)
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
                (fileTitle
                 + (normaliseByInputByteLength
                    ? " [normalised by input byte length]"
                    : "")
                 + (restrictedXDomain != xDomain
                    ? (1 < restrictedXDomain.count
                       ? ", input lengths \((restrictedXDomain.first ?? 0).formatted(.byteCount(style: .decimal)))…\((restrictedXDomain.last ?? 0).formatted(.byteCount(style: .decimal)))"
                       : ", input length \((restrictedXDomain.first ?? 0).formatted(.byteCount(style: .decimal)))")
                    : "")
                 + (showLegend
                    ? ""
                    : ", sans legend")))
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
