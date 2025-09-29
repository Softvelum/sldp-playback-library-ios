import Foundation

struct TrackInfoApp: Hashable, Codable, Identifiable, Comparable, Equatable {
    static func < (lhs: TrackInfoApp, rhs: TrackInfoApp) -> Bool {
        return lhs.width < rhs.width || lhs.height < rhs.height || lhs.bandwidth < rhs.bandwidth
    }
    static func == (lhs: TrackInfoApp, rhs: TrackInfoApp) -> Bool {
        return (lhs.width == rhs.width && lhs.height == rhs.height) || lhs.bandwidth == rhs.bandwidth
    }
    
    var id: Int32
    var width: Int32
    var height: Int32
    var bandwidth: Int32
    
    var description: String {
        if height > 0 && width > 0 {
            return String(format: "%dx%d", width, height)
        } else if bandwidth > 0 {
            return String(format: "%d kbps", Int(bandwidth/1000))
        }
        return ""
    }
}
