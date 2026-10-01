# Enhancement Feature

amp includes an AI-powered video enhancement feature that improves the quality of low-bitrate videos (e.g., WhatsApp, messaging apps) using advanced upscaling algorithms.

## How It Works

amp uses a two-layer enhancement system:

1. **Real-time enhancement**: During playback, GLSL shaders (FSRCNNX, SSimSuperRes, RAVU) provide immediate quality improvement with minimal performance impact.

2. **Offline enhancement**: For severely compressed videos (<10 Mbit/s), amp can process videos using Stream-DiffVSR, a state-of-the-art diffusion model that provides superior quality. Enhanced versions are cached for future playback.

## Using Enhancement

### Automatic Enhancement

When you open a low-bitrate video, amp automatically detects it and offers enhancement:

1. A banner appears suggesting enhancement
2. Click "Enhance Now" to start processing
3. The video plays immediately with real-time shaders
4. Background processing creates a higher-quality version
5. When complete, you're prompted to switch to the enhanced version

### Manual Enhancement

You can also manually trigger enhancement:

1. Go to Settings → Rendering
2. Ensure "Auto-enhance low-bitrate videos" is enabled
3. Open a low-bitrate video
4. Enhancement starts automatically in the background

### Managing Enhanced Videos

Enhanced videos are stored in `~/Library/Application Support/amp/Enhanced/`:

1. Go to Settings → Rendering → Manage Enhanced Videos
2. View all cached enhanced videos
3. Delete individual videos or clear all
4. Cache size limit: 50 GB (oldest videos are automatically removed when full)

## Performance

- **Real-time enhancement**: Maintains ≥30 FPS at 1080p on Apple Silicon M1+
- **Offline enhancement**: ~2-4 seconds per frame on M1 Pro/Max (32GB), ~0.3-0.8 seconds per frame on RTX 3090 Ti

## Supported Formats

- Input: Any video format supported by amp (MP4, MOV, MKV, etc.)
- Output: H.264 MP4 with enhanced quality
- Bitrate detection: Videos <10 Mbit/s are candidates for enhancement
- Resolution: Most effective for videos <720p

## Privacy

All enhancement processing happens locally on your Mac. No video data is sent to external servers.

## Troubleshooting

### Enhancement not starting

- Ensure "Auto-enhance low-bitrate videos" is enabled in Settings → Rendering
- Check that Stream-DiffVSR is installed (run `Scripts/setup_stream_diffvsr.sh`)
- Verify the video bitrate is <10 Mbit/s (check in video metadata)

### Enhancement too slow

- Offline enhancement is compute-intensive; expect 2-4 seconds per frame on M1
- For faster processing, use a Mac with M1 Pro/Max or later
- Consider enhancing only important videos rather than all low-bitrate content

### Cache growing too large

- Go to Settings → Rendering → Manage Enhanced Videos
- Delete old enhanced videos you no longer need
- Cache automatically evicts oldest videos when reaching 50 GB limit
