import AVFoundation
import AVKit
import UIKit

class ViewController: UIViewController, AVPictureInPictureControllerDelegate, SldpEngineDelegate {

    var videoLayer: CALayer?
    var engine: SldpEngineProxy?
    var id: Int32 = -1

    var videoTracks:[TrackInfoApp] = []
    var audioTracks:[TrackInfoApp] = []

    var btnQuality: UIBarButtonItem?

    let uri = "wss://demo-nimble.softvelum.com/live/bbb"

    // Autohide home indicator (bar at the bottom of screen)
    override var prefersHomeIndicatorAutoHidden: Bool {
        return true
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    @objc func Settings_Click() {
        guard engine != nil else {
            return
        }
        if !videoTracks.isEmpty {
            showSelector(source: videoTracks, title: String.localizedStringWithFormat(NSLocalizedString("Resolution", comment: "")))
        } else if !audioTracks.isEmpty {
            showSelector(source: audioTracks, title: String.localizedStringWithFormat(NSLocalizedString("Bitrate", comment: "")))
        }
    }

    func showSelector(source: [TrackInfoApp], title: String) {
        let selectMenu = UIAlertController(title: title, message: "", preferredStyle: .actionSheet)
        if let popoverController = selectMenu.popoverPresentationController { //This required to present action sheet on iPad
            let button = toolbarItems?.last
            popoverController.barButtonItem = button
            popoverController.permittedArrowDirections = [.down]
        }
        source.forEach { track in
            let action = UIAlertAction(title: track.description, style: .default) { _ in
                //self.player?.playTrack(track.id)
            }
            selectMenu.addAction(action)
        }

        let cancel = UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel)
        selectMenu.addAction(cancel)

        present(selectMenu, animated: true)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let flexible = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: self, action: #selector(Settings_Click))
        let quality = UIBarButtonItem(title: NSLocalizedString("Quality", comment: ""), style: .plain, target: self, action: #selector(Settings_Click))
        quality.isEnabled = false
        btnQuality = quality
        toolbarItems = [flexible, quality]

        AudioSessionUtils.sharedInstance.startAudio()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        view.backgroundColor = UIColor.black

        let sampleBufferLayer = AVSampleBufferDisplayLayer()
        sampleBufferLayer.frame = view.bounds
        sampleBufferLayer.videoGravity = AVLayerVideoGravity.resizeAspect
        view.layer.addSublayer(sampleBufferLayer)

        let config = StreamConfig()
        config.uri = URL(string: uri)!

        engine = SldpEngineProxy()
        engine?.setDelegate(self)
        engine?.setVideoLayer(sampleBufferLayer)

        id = engine?.createStream(config) ?? -1
        videoLayer = sampleBufferLayer

        navigationController?.isNavigationBarHidden = false
        navigationController?.isToolbarHidden = false
        navigationController?.hidesBarsOnTap = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        engine?.setDelegate(nil)

        if (id != -1) {
            engine?.releaseStream(id)
            id = -1
        }

        engine?.setVideoLayer(nil)
        videoLayer?.removeFromSuperlayer()

        navigationController?.isNavigationBarHidden = false
        navigationController?.isToolbarHidden = true
        navigationController?.hidesBarsOnTap = false
    }

    override func viewDidLayoutSubviews() {
        videoLayer?.frame = view.bounds
        super.viewDidLayoutSubviews()
    }

    func updateTracks(tracks: [AnyHashable: Any]) {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .none

        guard let allTracks = tracks as? [NSNumber: TrackInfo] else {
            return
        }

        videoTracks.removeAll()
        audioTracks.removeAll()

        for (_, info) in allTracks {
            if (info.type == .video) {
                let track = TrackInfoApp(id: info.trackId, width: info.width, height: info.height, bandwidth: 0)
                videoTracks.append(track)
                NSLog("video track: \(track.description)")

            } else if (info.type == .audio && info.bandwidth > 0) {
                let track = TrackInfoApp(id: info.trackId, width: 0, height: 0, bandwidth: info.bandwidth)
                audioTracks.append(track)
                NSLog("audio track: \(track.description)")
            }
        }

        videoTracks.sort()
        audioTracks.sort()

        btnQuality?.isEnabled = !(videoTracks.isEmpty && audioTracks.isEmpty)
    }

    func streamStateDidChangeId(_ streamId: Int32, state: StreamState, status: StreamStatus) {
        NSLog("streamStateDidChange: id:\(streamId) state:\(state.rawValue) status:\(status.rawValue)")

        switch state {
        case .setup:
            if let tracks = engine?.getTracks() {
                updateTracks(tracks: tracks)
            }
        case .disconnected where streamId != -1:
            DispatchQueue.main.async {
                if let message = status.localizedMessage {
                    NSLog(message)
                }
                let cancelId = self.id
                self.id = -1 // ignore .disconnect notification processing for stream that we want to release
                self.engine?.releaseStream(cancelId, clearImage: true)
                if (status != .authFail) {
                    // try to restart playback
                    let config = StreamConfig()
                    config.uri = URL(string: self.uri)!
                    self.id = self.engine?.createStream(config) ?? -1
                }
            }
        default:
            break
        }
    }

}
