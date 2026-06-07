import SwiftUI

enum PixelIconKind {
    case bit
    case spark
    case cake
    case bond
    case streak
    case milestone
    case trophy
    case night
    case returnArrow
}

struct PixelIcon: View {
    let kind: PixelIconKind
    var size: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / CGFloat(Self.gridSize)
            ZStack(alignment: .topLeading) {
                ForEach(Array(pattern.enumerated()), id: \.offset) { _, pixel in
                    Rectangle()
                        .fill(pixel.color)
                        .frame(width: ceil(unit), height: ceil(unit))
                        .position(
                            x: (CGFloat(pixel.x) + 0.5) * unit,
                            y: (CGFloat(pixel.y) + 0.5) * unit
                        )
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var pattern: [Pixel] {
        switch kind {
        case .bit:
            return pixels(
                color: Color(red: 0.45, green: 0.96, blue: 1.0),
                points: [(3,0), (2,1), (3,1), (4,1), (1,2), (2,2), (4,2), (5,2),
                         (0,3), (1,3), (5,3), (6,3), (1,4), (2,4), (4,4), (5,4),
                         (2,5), (3,5), (4,5), (3,6)]
            )
        case .spark:
            return pixels(
                color: Color(red: 0.90, green: 0.95, blue: 1.0),
                points: [(3,0), (3,1), (1,3), (2,3), (3,3), (4,3), (5,3), (3,4), (3,5), (3,6)]
            )
        case .cake:
            return pixels(
                color: Color(red: 1.0, green: 0.66, blue: 0.76),
                points: [(3,0), (2,1), (3,1), (4,1), (1,3), (2,3), (3,3), (4,3), (5,3),
                         (1,4), (3,4), (5,4), (1,5), (2,5), (3,5), (4,5), (5,5)]
            )
        case .bond:
            return pixels(
                color: Color(red: 1.0, green: 0.72, blue: 0.38),
                points: [(1,1), (2,1), (4,1), (5,1), (0,2), (3,2), (6,2),
                         (0,3), (6,3), (1,4), (5,4), (2,5), (3,5), (4,5)]
            )
        case .streak:
            return pixels(
                color: Color(red: 1.0, green: 0.48, blue: 0.22),
                points: [(3,0), (2,1), (3,1), (2,2), (4,2), (1,3), (3,3), (4,3),
                         (1,4), (2,4), (3,4), (5,4), (2,5), (3,5), (4,5), (3,6)]
            )
        case .milestone:
            return pixels(
                color: Color(red: 0.75, green: 0.88, blue: 1.0),
                points: [(1,1), (2,1), (3,1), (4,1), (5,1), (1,2), (3,2), (1,3),
                         (2,4), (3,4), (4,4), (3,5), (3,6)]
            )
        case .trophy:
            return pixels(
                color: Color(red: 1.0, green: 0.84, blue: 0.34),
                points: [(1,1), (2,1), (3,1), (4,1), (5,1), (0,2), (2,2), (3,2),
                         (4,2), (6,2), (1,3), (3,3), (5,3), (3,4), (2,5), (3,5), (4,5), (2,6), (3,6), (4,6)]
            )
        case .night:
            return pixels(
                color: Color(red: 0.70, green: 0.76, blue: 1.0),
                points: [(3,0), (2,1), (1,2), (1,3), (2,4), (3,5), (4,5), (5,4),
                         (4,4), (3,4), (2,3), (2,2), (3,1)]
            )
        case .returnArrow:
            return pixels(
                color: Color(red: 0.46, green: 1.0, blue: 0.74),
                points: [(2,1), (1,2), (2,2), (0,3), (1,3), (2,3), (3,3), (4,3),
                         (5,3), (5,4), (4,5), (3,5)]
            )
        }
    }

    private static let gridSize = 7

    private struct Pixel {
        let x: Int
        let y: Int
        let color: Color
    }

    private func pixels(color: Color, points: [(Int, Int)]) -> [Pixel] {
        points.map { Pixel(x: $0.0, y: $0.1, color: color) }
    }
}
