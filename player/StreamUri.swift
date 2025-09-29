import Foundation
fileprivate extension String {
    func indexOf(target: String) -> Int? {
        let range = (self as NSString).range(of: target)
        guard Range.init(range) != nil else {
            return nil
        }
        return range.location
    }
    func lastIndexOf(target: String) -> Int? {
        let range = (self as NSString).range(of: target, options: NSString.CompareOptions.backwards)
        guard Range.init(range) != nil else {
            return nil
        }
        return self.count - range.location - 1
    }
    func contains(s: String) -> Bool {
        return (self.range(of: s) != nil) ? true : false
    }
}


class StreamUri {
    var uri: String?
    var message: String?
    var scheme: String?
    var port: Int?
    var host: String?
    
    static let supportedSchemes = ["rtmp", "sldp", "ws", "http", "rtmps", "sldps", "wss", "https", "srt"]
    static let sldpSchemes = ["sldp", "sldps", "ws", "wss"]
    
    class func isHttp(scheme: String?) -> Bool {
        return ["http", "https"].contains(scheme ?? "")
    }

    class func isSldp(scheme: String?) -> Bool {
        return sldpSchemes.contains(scheme ?? "")
    }

    class func isSrt(scheme: String?) -> Bool {
        return ["srt"].contains(scheme ?? "")
    }

    class func isSupported(scheme: String?) -> Bool {
        return supportedSchemes.contains(scheme ?? "")
    }
    
    var isHttp: Bool {
        return Self.isHttp(scheme: scheme)
    }

    var isSldp: Bool {
        return Self.isSldp(scheme: scheme)
    }

    var isSrt: Bool {
        return Self.isSrt(scheme: scheme)
    }

    var isSupported: Bool {
        return Self.isSupported(scheme: scheme)
    }

    
    init(url: URL) {
        guard let scheme = url.scheme?.lowercased(), let host = url.host else {
            self.message = NSLocalizedString("Please enter a valid URL. For example rtmp://192.168.1.1:1935/live/stream.", comment: "")
            return

        }
        if !Self.isSupported(scheme: scheme) {
            self.message = String.localizedStringWithFormat(NSLocalizedString("Player doesn't support this type of protocol (%@). Please enter \"rtmp(s)://\", \"sldp(s)://\", \"srt://\" or \"http(s)://\".", comment: ""), scheme)
            return
        }
        self.scheme = scheme
        self.port = url.port
        self.host = host
        
        if let _ = url.user, let _ = url.password {
            // delete user:password part from scheme://user:password@host:port/app/stream
            if let pos = url.absoluteString.indexOf(target: "@") {
                let index = url.absoluteString.index(url.absoluteString.startIndex, offsetBy: pos + 1)
                self.uri = String()
                self.uri?.append(scheme)
                self.uri?.append("://")
                self.uri?.append(String(url.absoluteString[index...]))
            } else {
                self.uri = url.absoluteString
            }
        } else {
            if isSrt, let components = URLComponents.init(url: url, resolvingAgainstBaseURL: false) {
                var builder = URLComponents.init()
                builder.scheme = components.scheme
                builder.host = components.host
                builder.port = components.port
                self.uri = builder.url?.absoluteString
            } else {
                self.uri = url.absoluteString
            }
        }
    }
}
