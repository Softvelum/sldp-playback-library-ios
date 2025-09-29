import Foundation

extension StreamStatus {
    var localizedMessage: String? {
        switch self {
        case .success:
            return nil
        case .connectionFail:
            return String.localizedStringWithFormat(NSLocalizedString("Could not connect to server. Please check stream URL and network connection.", comment: ""))
        case .handshakeFail:
            return String.localizedStringWithFormat(NSLocalizedString("Handshake with server is failed. Please check stream URL.", comment: ""))
        case .authFail:
            return String.localizedStringWithFormat(NSLocalizedString("Authentication error. Please check stream credentials.", comment: ""))
        case .playbackFail:
            return String.localizedStringWithFormat(NSLocalizedString("Unknown playback error.", comment: ""))
        case .noData:
            return String.localizedStringWithFormat(NSLocalizedString("Stream timeout. Trying to restart.", comment: ""))
        default:
            return String.localizedStringWithFormat(NSLocalizedString("Unknown connection error.", comment: ""))
        }

    }
}
