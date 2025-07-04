import {
	AudioProContentType,
	type AudioProEvent,
	AudioProEventType,
	type AudioProTrack,
	AudioPro,
} from 'react-native-audio-pro';

import { playlist } from './playlist';

// Track the current playlist position
let currentIndex = 0;

export function setupAudioPro(): void {
	// Configure audio settings
	AudioPro.configure({
		contentType: AudioProContentType.MUSIC,
		debug: true,
		debugIncludesProgress: false,
		progressIntervalMs: 1000,
	});

	// Set up event listeners that persist for the app's lifetime
	AudioPro.addEventListener((event: AudioProEvent) => {
		switch (event.type) {
			case AudioProEventType.TRACK_ENDED:
				// Auto-play next track when current track ends
				playNextTrack();
				break;

			case AudioProEventType.REMOTE_NEXT:
				// Handle next button press from lock screen/notification
				playNextTrack();
				break;

			case AudioProEventType.REMOTE_PREV:
				// Handle previous button press from lock screen/notification
				playPreviousTrack();
				break;

			case AudioProEventType.PLAYBACK_ERROR:
				console.warn('Playback error:', event.payload?.error);
				break;
		}
	});
}

function playNextTrack(): void {
	if (playlist.length === 0) return;

	currentIndex = (currentIndex + 1) % playlist.length;
	const nextTrack = playlist[currentIndex];

	AudioPro.play(nextTrack as AudioProTrack);
}

function playPreviousTrack(): void {
	if (playlist.length === 0) return;

	currentIndex = currentIndex > 0 ? currentIndex - 1 : playlist.length - 1;
	const prevTrack = playlist[currentIndex];

	AudioPro.play(prevTrack as AudioProTrack);
}

export function getCurrentTrackIndex(): number {
	return currentIndex;
}

export function setCurrentTrackIndex(index: number): void {
	if (index >= 0 && index < playlist.length) {
		currentIndex = index;
	}
}

// For progress interval adjustment demo
let progressInterval = 1000;

export function getProgressInterval(): number {
	return progressInterval;
}

export function setProgressInterval(ms: number): void {
	progressInterval = ms;
}
