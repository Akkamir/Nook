import SwiftUI

enum DayPhase: Equatable {
    case sunrise  // 6h–9h
    case day      // 9h–18h
    case sunset   // 18h–21h
    case night    // 21h–6h

    static func current() -> DayPhase {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<9:   return .sunrise
        case 9..<18:  return .day
        case 18..<21: return .sunset
        default:      return .night
        }
    }

    var overlayColor: Color {
        switch self {
        case .sunrise: return Color(red: 1.0, green: 0.75, blue: 0.2)
        case .day:     return Color.clear
        case .sunset:  return Color(red: 1.0, green: 0.45, blue: 0.1)
        case .night:   return Color(red: 0.08, green: 0.08, blue: 0.25)
        }
    }

    var overlayOpacity: Double {
        switch self {
        case .sunrise: return 0.18
        case .day:     return 0.0
        case .sunset:  return 0.22
        case .night:   return 0.52
        }
    }
}
