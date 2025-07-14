# Samsung TV AirPlay Troubleshooting Guide

This guide helps resolve common Samsung TV AirPlay issues, particularly the loading spinner and artwork problems that users report.

## Common Issues

### 1. Loading Spinner Never Goes Away

**Symptoms:** Audio plays correctly but TV shows persistent loading spinner
**Root Cause:** Samsung TVs require specific artwork metadata formatting

### 2. Artwork Not Displaying

**Symptoms:** Audio plays but no artwork shows on Samsung TV
**Root Cause:** Artwork callback timing or format issues

## Recent Improvements (Latest Version)

The library now includes Samsung TV-specific optimizations:

1. **Enhanced Artwork Handling**: Artwork is pre-sized to Samsung TV's preferred 600x600 format
2. **Stable Artwork Callbacks**: Eliminates weak reference issues that cause artwork failures
3. **Fallback Artwork**: Creates a subtle placeholder when no artwork is available
4. **Metadata Timing**: Improved timing to prevent Samsung TV metadata conflicts
5. **AirPlay Detection**: Better handling of Samsung TV AirPlay connection states

## Recommended Track Format

```javascript
const track = {
	id: 'unique-track-id',
	url: 'https://your-audio-stream.mp3',
	title: 'Track Title',
	artist: 'Artist Name',
	artwork: 'https://your-artwork-url.jpg', // IMPORTANT: Always provide artwork
};

// Configure for optimal Samsung TV compatibility
AudioPro.configure({
	debug: true, // Enable to see Samsung TV-specific logs
});

AudioPro.play(track);
```

## Troubleshooting Steps

### Step 1: Verify Artwork URL

Samsung TVs are very sensitive to artwork loading failures:

```javascript
// ✅ Good - Always provide a valid artwork URL
const track = {
	artwork: 'https://example.com/cover.jpg',
};

// ❌ Bad - Missing or empty artwork often causes loading spinner
const track = {
	artwork: null, // or undefined or ''
};
```

### Step 2: Check Network Connectivity

Samsung TVs may struggle with slow artwork loading:

- Use CDN-hosted images when possible
- Prefer HTTPS URLs
- Ensure artwork URLs are accessible from the TV's network
- Consider using local bundle images for faster loading

### Step 3: Enable Debug Logging

Enable debug mode to see Samsung TV-specific logs:

```javascript
AudioPro.configure({
	debug: true,
});
```

Look for logs containing `[Samsung TV]` that indicate:

- Artwork loading status
- AirPlay connection state
- Metadata setting results

### Step 4: Use Optimal Artwork Format

Samsung TVs work best with:

- **Size**: 600x600 pixels (library automatically resizes)
- **Format**: JPEG or PNG
- **URL**: Accessible via HTTPS

### Step 5: Test AirPlay Connection

The library now detects Samsung TV AirPlay connections and logs:

```
[Samsung TV] AirPlay/Samsung TV playback has started. Preserving artwork metadata.
[Samsung TV] AirPlay started with artwork present - Samsung TV should display correctly
```

## Advanced Debugging

### Network Configuration

Samsung TVs may have issues with:

- Mixed HTTP/HTTPS content
- CORS restrictions
- Network firewalls blocking artwork requests

### Samsung TV Models

Different Samsung TV models have varying AirPlay implementations:

- **2019+ Models**: Generally better AirPlay 2 support
- **2018 Models**: May require firmware updates
- **Older Models**: Limited or no AirPlay support

### Known Workarounds

1. **Restart the Samsung TV** after connecting to clear any cached metadata
2. **Use local artwork** bundled with your app when possible
3. **Ensure consistent network connection** during AirPlay session
4. **Update Samsung TV firmware** to latest version

## Testing Your Implementation

1. **Test with Different Artwork URLs**: Try both remote HTTPS and local file:// URLs
2. **Monitor Debug Logs**: Look for Samsung TV-specific messages
3. **Test Various Samsung TV Models**: If possible, test on different TV models/years
4. **Check Network Requirements**: Ensure artwork URLs are accessible from TV's network

## Common Error Patterns

### "Catalog returned nil image"

This Samsung TV error indicates artwork callback failure. The library now prevents this with stable artwork references.

### "No endpoint found for device"

This indicates AirPlay connection issues. Try:

- Restart both devices
- Check network connectivity
- Update Samsung TV firmware

### Persistent Loading Spinner

Usually caused by missing or invalid artwork. The library now provides fallback artwork to prevent this.

## Library Configuration for Samsung TVs

```javascript
// Optimal configuration for Samsung TV compatibility
AudioPro.configure({
	debug: true, // See Samsung TV logs
	progressIntervalMs: 1000, // Standard interval
});

// Always provide complete track metadata
const track = {
	id: 'track-1',
	url: 'https://stream-url.mp3',
	title: 'Song Title',
	artist: 'Artist Name',
	artwork: 'https://artwork-url.jpg', // Critical for Samsung TVs
};

AudioPro.play(track);
```

## When to Contact Support

If issues persist after following this guide:

1. **Enable debug logging** and capture logs during AirPlay connection
2. **Note your Samsung TV model and firmware version**
3. **Test with multiple audio sources** to isolate the issue
4. **Provide network configuration details** if artwork loading fails

The library's Samsung TV optimizations should resolve most common issues. The improvements focus on the specific metadata timing and artwork handling requirements that Samsung TVs need for reliable AirPlay operation.
