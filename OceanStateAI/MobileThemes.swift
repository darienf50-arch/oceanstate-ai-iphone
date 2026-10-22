import SwiftUI

enum MobileTheme: String, CaseIterable, Identifiable {
    case classic, matrix, ocean
    var id: String { rawValue }
    var title: String { switch self { case .classic: "Midnight"; case .matrix: "Matrix"; case .ocean: "Deep Ocean" } }
    var detail: String { switch self { case .classic: "Clean, quiet midnight tones"; case .matrix: "Emerald code rain and dark glass"; case .ocean: "Blue currents and soft sea light" } }
    var accent: Color { switch self { case .classic: .cyan; case .matrix: .green; case .ocean: Color(red: 0.24, green: 0.78, blue: 1) } }
    var background: Color { switch self { case .classic: Color(red: 0.025, green: 0.035, blue: 0.055); case .matrix: Color(red: 0.005, green: 0.035, blue: 0.015); case .ocean: Color(red: 0.01, green: 0.035, blue: 0.10) } }
    var css: String {
        let palette: String
        switch self {
        case .classic: palette = "--color-gray-950:#070a10;--color-gray-900:#0d1420;--color-gray-850:#111b29;--color-gray-800:#192436;--os-accent:#67e8f9;--os-glow:rgba(34,211,238,.08);"
        case .matrix: palette = "--color-gray-950:#010a05;--color-gray-900:#04140b;--color-gray-850:#092016;--color-gray-800:#103323;--os-accent:#67fa9c;--os-glow:rgba(40,255,120,.10);"
        case .ocean: palette = "--color-gray-950:#020b20;--color-gray-900:#04182c;--color-gray-850:#08263e;--color-gray-800:#0c354f;--os-accent:#70d8ff;--os-glow:rgba(35,172,255,.12);"
        }
        return """
        :root,.dark {\(palette)}
        html,body {background:var(--color-gray-950)!important;color-scheme:dark;}
        body {background-image:radial-gradient(ellipse at 85% 0%,var(--os-glow),transparent 70%)!important;}
        button,input,textarea,select {transition:background-color .2s ease,border-color .2s ease,box-shadow .2s ease;}
        button:focus-visible,input:focus-visible,textarea:focus-visible {outline:2px solid var(--os-accent)!important;outline-offset:2px;}
        ::selection {background:var(--os-glow);color:var(--os-accent);}
        @media(prefers-reduced-motion:reduce) {button,input,textarea,select {transition:none!important;}}
        """
    }
}

struct ThemeAnimation: View {
    let theme: MobileTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: reduceMotion || theme == .classic)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                if theme == .matrix {
                    let spacing: CGFloat = 27
                    for column in 0..<Int(size.width / spacing + 1) {
                        let speed = 22 + Double((column * 17) % 33)
                        let offset = (time * speed + Double(column * 83)).truncatingRemainder(dividingBy: Double(size.height + 220)) - 110
                        for row in 0..<9 {
                            let scalar = 33 + (column * 13 + row * 31 + Int(time * 3)) % 59
                            let glyph = String(UnicodeScalar(scalar)!)
                            canvas.opacity = Double(9 - row) / 9 * 0.16
                            canvas.draw(Text(glyph).font(.system(size: 13, weight: .medium, design: .monospaced)).foregroundColor(theme.accent), at: CGPoint(x: CGFloat(column) * spacing + 12, y: offset - Double(row * 19)))
                        }
                    }
                } else if theme == .ocean {
                    for layer in 0..<4 {
                        var wave = Path()
                        let baseline = size.height * (0.30 + Double(layer) * 0.21)
                        wave.move(to: CGPoint(x: 0, y: size.height))
                        for x in stride(from: 0.0, through: Double(size.width) + 8, by: 8) {
                            let y = baseline + sin(x / (95 + Double(layer) * 27) + time * (0.20 + Double(layer) * 0.055)) * (22 + Double(layer * 9))
                            wave.addLine(to: CGPoint(x: x, y: y))
                        }
                        wave.addLine(to: CGPoint(x: size.width, y: size.height)); wave.closeSubpath()
                        canvas.fill(wave, with: .linearGradient(Gradient(colors: [theme.accent.opacity(0.045), .blue.opacity(0.015)]), startPoint: CGPoint(x: size.width, y: baseline), endPoint: CGPoint(x: 0, y: size.height)))
                    }
                }
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

struct MobileThemePicker: View {
    @AppStorage("oceanstate.mobile.theme") private var selected = MobileTheme.ocean.rawValue
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(MobileTheme.allCases) { theme in
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) { selected = theme.rawValue }
                        } label: {
                            ZStack(alignment: .bottomLeading) {
                                theme.background
                                ThemeAnimation(theme: theme)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(theme.title).font(.title2.bold()); Spacer(); if selected == theme.rawValue { Image(systemName: "checkmark.circle.fill") } }
                                    Text(theme.detail).font(.subheadline).foregroundStyle(.white.opacity(0.8))
                                }.padding(20)
                            }.frame(height: 155).clipShape(RoundedRectangle(cornerRadius: 22))
                                .overlay(RoundedRectangle(cornerRadius: 22).stroke(theme.accent.opacity(selected == theme.rawValue ? 0.8 : 0.18), lineWidth: selected == theme.rawValue ? 2 : 1))
                        }.buttonStyle(.plain).foregroundStyle(theme.accent)
                            .accessibilityLabel(theme.title + (selected == theme.rawValue ? ", selected" : ""))
                    }
                    Text("Themes stay on this iPhone. Animations respect Reduce Motion and never block chat controls.").font(.caption).foregroundStyle(.secondary)
                }.padding()
            }.background(Color.black).navigationTitle("Choose your atmosphere")
                .navigationBarTitleDisplayMode(.inline).toolbar { Button("Done") { dismiss() } }
        }.preferredColorScheme(.dark)
    }
}
