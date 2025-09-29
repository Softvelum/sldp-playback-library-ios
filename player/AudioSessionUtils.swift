import Foundation
import UIKit

class AudioSessionUtils {
    
     static let sharedInstance = AudioSessionUtils()
    
    struct holder {
        static var isAudioSessionActive = false
    }

    func startAudio() {
        observeAudioSessionNotifications(true)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            activateAudioSession()
        } catch {
            NSLog("startAudio failed: \(error.localizedDescription)")
        }
    }
    
    func activateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(true)
            holder.isAudioSessionActive = true;
        } catch {
            holder.isAudioSessionActive = false;
            NSLog("activateAudioSession failed: \(error.localizedDescription)")
        }
        NSLog("\(#function) isActive:\(holder.isAudioSessionActive), AVAudioSession Activated with category:\(audioSession.category)")
    }
    
    class var isAudioSessionActive: Bool {
        return holder.isAudioSessionActive
    }
    
    func stopAudio() {
        deactivateAudioSession()
        observeAudioSessionNotifications(false)
    }
    
    func deactivateAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setActive(false)
            holder.isAudioSessionActive = false;
        } catch {
            NSLog("deactivateAudioSession failed: \(error.localizedDescription)")
        }
        NSLog("\(#function) isActive:\(holder.isAudioSessionActive)")
    }
    
    func observeAudioSessionNotifications(_ observe:Bool) {
        let audioSession = AVAudioSession.sharedInstance()
        let center = NotificationCenter.default
        if observe {
            center.addObserver(self, selector: #selector(handleAudioSessionInterruption(notification:)), name: AVAudioSession.interruptionNotification, object: audioSession)
            center.addObserver(self, selector: #selector(handleAudioSessionRouteChange(notification:)), name: AVAudioSession.routeChangeNotification, object: audioSession)
            center.addObserver(self, selector: #selector(handleAudioSessionMediaServicesWereLost(notification:)), name: AVAudioSession.mediaServicesWereLostNotification, object: audioSession)
            center.addObserver(self, selector: #selector(handleAudioSessionMediaServicesWereReset(notification:)), name: AVAudioSession.mediaServicesWereResetNotification, object: audioSession)
        } else {
            center.removeObserver(self, name: AVAudioSession.interruptionNotification, object: audioSession)
            center.removeObserver(self, name: AVAudioSession.routeChangeNotification, object: audioSession)
            center.removeObserver(self, name: AVAudioSession.mediaServicesWereLostNotification, object: audioSession)
            center.removeObserver(self, name: AVAudioSession.mediaServicesWereResetNotification, object: audioSession)
        }
    }
    
    @objc func handleAudioSessionInterruption(notification: Notification) {
        
        if let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber, let interruptionType = AVAudioSession.InterruptionType(rawValue: UInt(value.intValue)) {
            
            let isAppActive = UIApplication.shared.applicationState == UIApplication.State.active ? true:false
            NSLog("\(#function) [Main:\(Thread.isMainThread)] [Active:\(isAppActive)] AVAudioSession Interruption:\(String(describing: notification.object)) withInfo:\(String(describing: notification.userInfo))")

            switch interruptionType {
            case .began:
                deactivateAudioSession()
            case .ended:
                activateAudioSession()
            default:
                break
            }
        }
    }
    
    @objc func handleAudioSessionRouteChange(notification: Notification) {
        
        if let value = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? NSNumber, let routeChangeReason = AVAudioSession.RouteChangeReason(rawValue: UInt(value.intValue)) {
            
            if let routeChangePreviousRoute = notification.userInfo?[AVAudioSessionRouteChangePreviousRouteKey] as? AVAudioSessionRouteDescription {
                NSLog("\(#function) routeChangePreviousRoute: \(routeChangePreviousRoute)")
            }
            
            switch routeChangeReason {
                
            case .unknown:
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonUnknown")

            case .newDeviceAvailable:
                // e.g. a headset was added or removed
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonNewDeviceAvailable")

            case .oldDeviceUnavailable:
                // e.g. a headset was added or removed
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonOldDeviceUnavailable")

            case .categoryChange:
                // called at start - also when other audio wants to play
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonCategoryChange")

            case .override:
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonOverride")

            case .wakeFromSleep:
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonWakeFromSleep")

            case .noSuitableRouteForCategory:
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory")

            case .routeConfigurationChange:
                NSLog("\(#function) routeChangeReason: AVAudioSessionRouteChangeReasonRouteConfigurationChange")

            default:
                break
            }
        }
    }
    
    @objc func handleAudioSessionMediaServicesWereReset(notification: Notification) {
        NSLog("\(#function) [Main:\(Thread.isMainThread)] Object:\(String(describing: notification.object)) withInfo:\(String(describing: notification.userInfo))")
    }
    
    @objc func handleAudioSessionMediaServicesWereLost(notification: Notification) {
        NSLog("\(#function) [Main:\(Thread.isMainThread)] Object:\(String(describing: notification.object)) withInfo:\(String(describing: notification.userInfo))")
    }
}
