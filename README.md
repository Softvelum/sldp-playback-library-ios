# An iOS library for SLDP playback

Read more about our SLDP open source playback [in this blog post](https://softvelum.com/2025/08/sldp-exoplayer-media3-open-source/).

## Usage

### Add sldp playback library
Drag and drop this folder
```swift
sldp
```

files in your project

### Add bridging header
```swift
sldp/SldpPlayer-Bridging-Header.h
```

### Simple Example
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
