//
//  ContentView.swift
//  ChartResults
//
//  Created by Wade Tregaskis on 6/9/2024.
//

import Charts
import Darwin
import SwiftUI

struct Record: Identifiable {
    let id: Int

    let input: String
    let inputLengthInCharacters: Int
    let inputLengthInBytes: Int
    let replacementEffect: String
    let algorithm: String
    let duration: Int
}

let emptyStringInput = "Empty string"
let lineWidth: CGFloat = 3

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

    var body: some View {
        if data.isEmpty {
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
            }.padding()
        } else {
            VStack {
                HStack {
                    Picker("Input", selection: $selectedInput) {
                        ForEach(Set(data.lazy.map(\.input)).sorted(), id: \.self) {
                            Text($0).tag($0)
                        }
                    }.onChange(of: selectedInput) { oldValue, newValue in
                        if newValue != oldValue {
                            let validReplacementEffects = Set(data.lazy.filter { $0.input == newValue }.map(\.replacementEffect))

                            guard let effect = selectedReplacementEffect, validReplacementEffects.contains(effect) else {
                                let newReplacementEffect = validReplacementEffects.sorted().first
                                print("Selected replacement effect (\(selectedReplacementEffect.orNilString)) is no longer valid (input changed from \(oldValue.orNilString) to \(newValue.orNilString)), so setting it to \(newReplacementEffect.orNilString).")
                                selectedReplacementEffect = newReplacementEffect
                                return
                            }
                        }
                    }

                    Picker("Input", selection: $selectedReplacementEffect) {
                        ForEach(Set(data.lazy.filter { $0.input == selectedInput }.map(\.replacementEffect)).sorted(), id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                }.padding()

                VStack(alignment: .leading) {
                    ForEach(Set(data.lazy.map(\.algorithm)).sorted(), id: \.self) { algorithm in
                        Toggle(algorithm,
                               isOn: Binding(get: { algorithmEnabled[algorithm] ?? true },
                                             set: { algorithmEnabled[algorithm] = $0 }))
                    }
                }.padding()

                if emptyStringInput == selectedInput {
                    Chart {
                        ForEach(data.lazy.filter { algorithmEnabled[$0.algorithm] ?? true }) {
                            BarMark(x: .value("Runtime (Nanoseconds)", $0.duration),
                                    y: .value("Algorithm", $0.algorithm))
                        }
                    }.padding()
                } else {
                    let selectedData = data.lazy.filter { $0.input == selectedInput && $0.replacementEffect == selectedReplacementEffect && algorithmEnabled[$0.algorithm] ?? true }.sorted { $0.algorithm < $1.algorithm || ($0.algorithm == $1.algorithm && $0.inputLengthInBytes < $1.inputLengthInBytes) }
                    let xDomain = Set(selectedData.lazy.map(\.inputLengthInBytes)).sorted()
                    let nonEmptyStringData = data.lazy.filter { emptyStringInput != $0.input }.map(\.duration)
                    let yRange = __exp10(log10(Double(nonEmptyStringData.min() ?? 1)).rounded(.down))...__exp10(log10(Double(nonEmptyStringData.max() ?? 1)).rounded(.up))

                    let _ = print("X-axis domain: \(xDomain), Y-axis range: \(yRange)")

                    Chart {
                        ForEach(selectedData) {
                            LineMark(x: .value("Input length", $0.inputLengthInBytes),
                                     y: .value("Runtime", $0.duration),
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
//                        .chartSymbolSizeScale { // The compiler just hangs if this modifier is used, irrespective of what its contents are. 😤
//                            min(4, lineWidth)
//                        }
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
                        .chartXScale(domain: (xDomain.first ?? 1)...(xDomain.last ?? 1), type: .log)
                        .chartXAxis {
                            AxisMarks(preset: .aligned, values: xDomain) {
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
                        .chartYAxisLabel("Runtime", position: .trailing, alignment: .center, spacing: -10)
                        .chartXAxisLabel(position: .top, alignment: .center, spacing: 10) {
                            if let selectedInput {
                                if let selectedReplacementEffect {
                                    Text("""
                                         \(Text(selectedInput).font(.headline))
                                         \(Text(selectedReplacementEffect).font(.subheadline))
                                         """).multilineTextAlignment(.center)
                                } else {
                                    Text(selectedInput).font(.headline)
                                }
                            }
                        }
                        .padding()
                        .padding(.leading, 20)
                }
            }
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
