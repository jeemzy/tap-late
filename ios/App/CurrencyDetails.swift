import SwiftUI
import TapLateCore

struct CurrencyDetails: View {
    let amounts: [PriceAmount]
    let choices: [Int: PriceCurrency]
    let rates: ECBRateStore
    var save: (PriceAmount, PriceCurrency) throws -> Void
    @State private var selected: Int?

    var body: some View {
        if let amount = amounts.first(where: { $0.id == selected }) ?? amounts.first {
            if amounts.count > 1 {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(amounts.enumerated()), id: \.element.id) { index, candidate in
                            Button(candidate.text) { selected = candidate.id }
                                .buttonStyle(.bordered)
                                .tint(candidate.id == amount.id ? Color.accentColor : .secondary)
                                .accessibilityLabel("Amount \(index + 1), \(candidate.text)")
                                .accessibilityAddTraits(candidate.id == amount.id ? .isSelected : [])
                        }
                    }
                }
            }
            AmountConversion(amount: amount, saved: choices[amount.id], rates: rates, save: save)
                .id(amount.id)
        }
    }
}

private struct AmountConversion: View {
    let amount: PriceAmount
    let saved: PriceCurrency?
    let rates: ECBRateStore
    var save: (PriceAmount, PriceCurrency) throws -> Void

    @State private var picking = false
    @State private var draft: PriceCurrency?
    @State private var request: PriceCurrency?
    @State private var values: [PriceCurrency: String] = [:]
    @State private var date = ""
    @State private var error: String?
    @AccessibilityFocusState private var focus: String?
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if picking {
                Text("Currency of \(amount.text)").font(.headline)
                LazyVGrid(columns: columns) {
                    ForEach(PriceCurrency.allCases, id: \.self) { code in
                        Button {
                            draft = code
                        } label: {
                            Label(code.rawValue, systemImage: draft == code ? "largecircle.fill.circle" : "circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityFocused($focus, equals: code.rawValue)
                        .accessibilityAddTraits(draft == code ? .isSelected : [])
                    }
                }
                HStack {
                    Button(saved == nil ? "Confirm & convert" : "Save & update") {
                        if let draft { convert(draft) }
                    }.buttonStyle(.glassProminent).disabled(draft == nil)
                    Button("Cancel") { picking = false; focus = "action" }.keyboardShortcut(.cancelAction)
                }
            } else if !values.isEmpty {
                LazyVGrid(columns: columns) {
                    ForEach(PriceCurrency.allCases, id: \.self) { code in
                        VStack(alignment: .leading) {
                            Text(code.rawValue).font(.caption).foregroundStyle(.secondary)
                            Text(code.symbol + (values[code] ?? "")).monospacedDigit()
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: .rect(cornerRadius: 10))
                    }
                }
                Text("Approx. · \(date)").font(.caption).accessibilityFocused($focus, equals: "results")
                HStack {
                    Button("Hide conversion") { values = [:]; focus = "action" }
                        .accessibilityFocused($focus, equals: "hide")
                    Spacer()
                    Button("Change currency", action: pick)
                }
            } else {
                if let saved {
                    HStack {
                        Text("Source: \(saved.rawValue)")
                        Spacer()
                        Button("Change currency", action: pick).disabled(request != nil)
                    }
                }
                Button(actionTitle) {
                    if let code = saved ?? amount.detected { convert(code) } else { pick() }
                }
                .buttonStyle(.glassProminent).disabled(request != nil)
                .accessibilityFocused($focus, equals: "action")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .task(id: request) {
            guard let code = request else { return }
            do {
                let snapshot = try await rates.snapshot()
                try Task.checkCancellation()
                values = try snapshot.values(for: amount.value, from: code)
                date = snapshot.date
                focus = "results"
            } catch {
                guard !Task.isCancelled else { return }
                error = "Reference rates are unavailable. Retry when connected."
                focus = "action"
            }
            request = nil
        }
    }

    private var actionTitle: String {
        if request != nil { return "Converting…" }
        if error != nil { return "Retry" }
        if let saved { return "Convert from \(saved.rawValue)" }
        return amount.detected == nil ? "Convert amount" : "Convert price"
    }

    private func pick() {
        draft = saved ?? amount.detected
        picking = true
        error = nil
        focus = (draft ?? .CNY).rawValue
    }

    private func convert(_ code: PriceCurrency) {
        do {
            try save(amount, code)
            values = [:]
            error = nil
            picking = false
            request = code
        } catch {
            self.error = "The source currency could not be saved. Try again."
        }
    }
}
