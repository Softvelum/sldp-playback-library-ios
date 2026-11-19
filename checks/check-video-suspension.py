#!/usr/bin/env python3
"""Exercise real renderer suspension with a deterministic asynchronous AV timeline."""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="sldp-suspension-") as folder:
    output = Path(folder)
    sources = ["SldpBaseMediaPlayer.m", "SldpMediaPlayerV11.m", "SldpVideoDecoderBase.m", "SldpVideoDecoderExternal.m"]
    command = ["xcrun", "clang", "-fobjc-arc", "-fmodules", "-fmodules-cache-path=" + str(output / "cache"), "-I", str(root / "sldp")]
    for framework in ("Foundation", "AVFoundation", "AudioToolbox", "VideoToolbox", "CoreMedia", "CoreVideo", "QuartzCore"):
        command += ["-framework", framework]
    command += [str(root / "sldp" / name) for name in sources]
    command += [str(root / "checks/video-suspension.m"), "-o", str(output / "check")]
    subprocess.run(command, check=True)
    subprocess.run([str(output / "check")], check=True)
