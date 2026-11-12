import SwiftUI

// Visual language: soft mesh-gradient fields, cream editorial panels, serif
// headlines, small monospaced uppercase labels, hairlines and dot grids.

extension Color {
    static let lullCream = Color(red: 0.957, green: 0.945, blue: 0.918)
    static let lullInk = Color(red: 0.11, green: 0.11, blue: 0.10)
    static let lullMuted = Color(red: 0.42, green: 0.41, blue: 0.38)
    static let lullForest = Color(red: 0.05, green: 0.23, blue: 0.18)

    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    static func lullSerif(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    static func lullMono(_ size: CGFloat = 11, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

/// "NEXT NAP" style label.
struct MonoLabel: View {
    let text: String
    var color: Color = .lullInk.opacity(0.7)

    init(_ text: String, color: Color = .lullInk.opacity(0.7)) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.lullMono(10.5))
            .tracking(1.2)
            .foregroundStyle(color)
    }
}

extension LullSnapshot.Mood {
    /// 3×3 mesh colors, row by row.
    var meshColors: [Color] {
        switch self {
        case .awake:
            [Color(hex: 0x9CC7E8), Color(hex: 0xB9E4D0), Color(hex: 0xDDF2A0),
             Color(hex: 0x3FAF7A), Color(hex: 0xC8E85A), Color(hex: 0x9FE3C1),
             Color(hex: 0x0E3B2E), Color(hex: 0x1F8A5B), Color(hex: 0x7CC96B)]
        case .asleep:
            [Color(hex: 0xF7C8A0), Color(hex: 0xF2B8C6), Color(hex: 0xE6B4E0),
             Color(hex: 0xF2A7C9), Color(hex: 0xB79BE8), Color(hex: 0x7C8FEA),
             Color(hex: 0x3A5BD9), Color(hex: 0x2E46B8), Color(hex: 0x2B2A6B)]
        case .feeding:
            [Color(hex: 0xFBE3C4), Color(hex: 0xF9D7A8), Color(hex: 0xF6E7B5),
             Color(hex: 0xF6B8C8), Color(hex: 0xF4C6D2), Color(hex: 0xDDEB9C),
             Color(hex: 0xEE9DB8), Color(hex: 0xF2B49A), Color(hex: 0xB9DF7A)]
        case .night:
            [Color(hex: 0x1C2B5A), Color(hex: 0x241F4F), Color(hex: 0x0F2A2A),
             Color(hex: 0x2B2A6B), Color(hex: 0x3B2F73), Color(hex: 0x123B36),
             Color(hex: 0x0B1E1A), Color(hex: 0x10172F), Color(hex: 0x0B1E1A)]
        }
    }

    /// Text color that reads on the gradient itself.
    var onGradient: Color {
        switch self {
        case .awake, .feeding: .lullForest
        case .asleep, .night: .white
        }
    }
}

/// Full-bleed mesh gradient with a faint dot grid.
struct GradientBackdrop: View {
    var mood: LullSnapshot.Mood
    var dots: Bool = true

    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.5, 0], [1, 0],
                    [0, 0.45], [0.62, 0.5], [1, 0.4],
                    [0, 1], [0.45, 1], [1, 1],
                ],
                colors: mood.meshColors
            )
            if dots { DotGrid().opacity(mood == .night ? 0.10 : 0.18) }
        }
        .animation(.easeInOut(duration: 0.8), value: mood)
    }
}

struct DotGrid: View {
    var spacing: CGFloat = 14

    var body: some View {
        Canvas { ctx, size in
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.2, height: 1.2)), with: .color(.white))
                    x += spacing
                }
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

/// Two crossing orbits — a solid one and a dashed one — with two dots.
struct OrbitMark: View {
    var color: Color = .lullInk
    var lineWidth: CGFloat = 1.2

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Ellipse()
                    .stroke(color, lineWidth: lineWidth)
                    .frame(width: w * 0.9, height: h * 0.42)
                    .rotationEffect(.degrees(-28))
                Ellipse()
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, dash: [3, 3]))
                    .frame(width: w * 0.95, height: h * 0.34)
                Circle().fill(color).frame(width: 6, height: 6).offset(x: -w * 0.33, y: -h * 0.17)
                Circle().fill(color).frame(width: 6, height: 6).offset(x: w * 0.30, y: h * 0.14)
            }
            .frame(width: w, height: h)
        }
    }
}

/// Cream editorial panel.
struct CreamPanel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lullCream, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Thin dashed rule, as on the reference posters.
struct DashedRule: View {
    var color: Color = .lullInk.opacity(0.25)

    var body: some View {
        Line()
            .stroke(color, style: StrokeStyle(lineWidth: 0.75, dash: [2, 3]))
            .frame(height: 1)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

enum LullIcon {
    static let sleep = "moon.zzz"
    static let wake = "sun.max"
    static let feed = "drop"
    static let bottle = "waterbottle"
    static let solids = "fork.knife"
    static let diaper = "circle.dotted.circle"

    static func symbol(for e: Entry) -> String {
        switch e.kind {
        case .sleep: sleep
        case .diaper: diaper
        case .feed:
            switch e.feedMethod ?? .breast {
            case .breast: feed
            case .bottle: bottle
            case .solids: solids
            }
        }
    }
}
