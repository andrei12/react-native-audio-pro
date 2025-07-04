# Audio Interruption Handling

This document shows how to handle audio interruptions (like timer alarms, phone calls, etc.) on the React Native side using the new interruption events.

## Overview

Instead of handling interruptions natively, this approach gives you full control over how your app responds to audio interruptions from the JavaScript/TypeScript side.

## Implementation

### 1. Listen for Interruption Events

```typescript
import { AudioPro, AudioProEventType } from 'react-native-audio-pro';

export function useAudioInterruptionHandler() {
	const [wasPlayingBeforeInterruption, setWasPlayingBeforeInterruption] = useState(false);

	useEffect(() => {
		const removeListener = AudioPro.addEventListener((event) => {
			switch (event.type) {
				case AudioProEventType.AUDIO_INTERRUPTION_BEGAN:
					console.log('🔴 Audio interruption began');
					const wasPlaying = event.payload?.wasPlaying || false;
					setWasPlayingBeforeInterruption(wasPlaying);

					if (wasPlaying) {
						// Pause the audio when interruption begins
						AudioPro.pause();
						console.log('🔴 Paused audio due to interruption');
					}
					break;

				case AudioProEventType.AUDIO_INTERRUPTION_ENDED:
					console.log('🟢 Audio interruption ended');
					const shouldResume = event.payload?.shouldResume || false;

					if (shouldResume && wasPlayingBeforeInterruption) {
						// Reactivate audio session and resume playback
						AudioPro.reactivateAudioSession();
						setTimeout(() => {
							AudioPro.resume();
							console.log('🟢 Resumed audio after interruption');
						}, 100); // Small delay to ensure audio session is ready
					} else {
						console.log(
							'🟡 Not resuming - shouldResume:',
							shouldResume,
							'wasPlaying:',
							wasPlayingBeforeInterruption,
						);
					}

					// Reset the flag
					setWasPlayingBeforeInterruption(false);
					break;
			}
		});

		return removeListener;
	}, [wasPlayingBeforeInterruption]);
}
```

### 2. Event Payloads

#### AUDIO_INTERRUPTION_BEGAN

```typescript
{
  type: 'AUDIO_INTERRUPTION_BEGAN',
  track: AudioProTrack,
  payload: {
    wasPlaying: boolean,      // Whether audio was playing when interruption began
    currentTime: number,      // Current playback position in seconds
    interruptionType: 'began'
  }
}
```

#### AUDIO_INTERRUPTION_ENDED

```typescript
{
  type: 'AUDIO_INTERRUPTION_ENDED',
  track: AudioProTrack,
  payload: {
    shouldResume: boolean,    // Whether iOS recommends resuming (per Apple guidelines)
    interruptionType: 'ended',
    options: number          // Raw iOS interruption options value
  }
}
```

### 3. Best Practices

#### Always Check `shouldResume` Flag

According to Apple's guidelines, you should only auto-resume if the `shouldResume` flag is `true`. This flag is `false` for interruptions where the user switched to another app that started playing audio.

#### Reactivate Audio Session

Always call `AudioPro.reactivateAudioSession()` before resuming playback after an interruption. This ensures the audio session is properly configured.

#### Add a Small Delay

Add a small delay (100ms) between reactivating the audio session and resuming playback to ensure the session is ready.

#### Track Playing State

Keep track of whether audio was playing before the interruption to make informed decisions about whether to resume.

### 4. Advanced Usage

#### Custom Interruption Logic

```typescript
case AudioProEventType.AUDIO_INTERRUPTION_ENDED:
  const shouldResume = event.payload?.shouldResume || false;

  if (shouldResume && wasPlayingBeforeInterruption) {
    // For radio streams, you might want to restart instead of resume
    if (isLiveRadio) {
      AudioPro.reactivateAudioSession();
      setTimeout(() => {
        AudioPro.stop();
        AudioPro.play(currentTrack);
      }, 100);
    } else {
      // For regular audio files, resume is fine
      AudioPro.reactivateAudioSession();
      setTimeout(() => {
        AudioPro.resume();
      }, 100);
    }
  }
  break;
```

#### User Notification

```typescript
case AudioProEventType.AUDIO_INTERRUPTION_BEGAN:
  if (wasPlaying) {
    // Show user notification that audio was paused
    showNotification('Audio paused due to interruption');
  }
  break;
```

## Benefits of This Approach

1. **Full Control**: Handle interruptions exactly how your app needs to
2. **Consistent Behavior**: Same logic across iOS and Android (when Android support is added)
3. **Debugging**: Easy to add logging and debug interruption handling
4. **Flexibility**: Different behavior for different types of content (radio vs files)
5. **User Experience**: Can show notifications or UI updates during interruptions

## Comparison with Native Handling

| Aspect               | Native Handling | React Native Handling |
| -------------------- | --------------- | --------------------- |
| Control              | Limited         | Full control          |
| Debugging            | Hard to debug   | Easy to debug         |
| Customization        | Difficult       | Easy                  |
| Platform consistency | iOS-specific    | Cross-platform ready  |
| Error handling       | Built-in        | Custom                |

This approach aligns with the [React Native audio focus guide](https://sanjeevsinghofficial.medium.com/detecting-audio-focus-gain-and-loss-in-react-native-a-step-by-step-guide-3058a01c3064) and gives you the professional control you need for a production audio app.
