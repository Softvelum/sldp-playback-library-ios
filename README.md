# iOS library and sample player for SLDP playback

## Usage

### Add sldp playback library
Drag and drop this folder
```swift
sldp
```
files in your project.

### Add bridging header
```swift
sldp/SldpPlayer-Bridging-Header.h
```

### Simple Example
Use this code to add SLDP playback in your existing app.
```swift
let sampleBufferLayer = AVSampleBufferDisplayLayer()
sampleBufferLayer.frame = view.bounds
sampleBufferLayer.videoGravity = AVLayerVideoGravity.resizeAspect
view.layer.addSublayer(sampleBufferLayer)

let config = StreamConfig()
config.uri = URL(string: "wss://demo-nimble.softvelum.com/live/bbb")!

engine = SldpEngineProxy()
engine.setDelegate(self)
engine.setVideoLayer(sampleBufferLayer)

engine.createStream(config)
```

### Sample player

Open player.xcodeproj, this project contains complete code to make your own SLDP player from scratch.



Also check our SLDP open source playback on Android [in this blog post](https://softvelum.com/2025/08/sldp-exoplayer-media3-open-source/).

