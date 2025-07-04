import React, { useEffect, useState } from 'react';
import { View, Text, TouchableOpacity, Alert } from 'react-native';

import { AudioPro, AudioProEventType } from 'react-native-audio-pro';

import { playlist } from './playlist';
import { styles } from './styles';

export default function App() {
	const [currentTrack] = useState(playlist[0]);
	const [isPlaying, setIsPlaying] = useState(false);
	const [wasPlayingBeforeInterruption, setWasPlayingBeforeInterruption] = useState(false);

	useEffect(() => {
		// Configure AudioPro
		AudioPro.configure({
			debug: true,
			debugIncludesProgress: false,
		});

		// Set up event listener
		const removeListener = AudioPro.addEventListener((event) => {
			console.log('AudioPro Event:', event);

			switch (event.type) {
				case AudioProEventType.STATE_CHANGED:
					const state = event.payload?.state;
					setIsPlaying(state === 'PLAYING');
					break;

				case AudioProEventType.AUDIO_INTERRUPTION_BEGAN:
					console.log('🔴 Audio interruption began');
					const wasPlaying = (event.payload as any)?.wasPlaying || false;
					setWasPlayingBeforeInterruption(wasPlaying);

					if (wasPlaying) {
						// Pause the audio when interruption begins
						AudioPro.pause();
						console.log('🔴 Paused audio due to interruption');
					}
					break;

				case AudioProEventType.AUDIO_INTERRUPTION_ENDED:
					console.log('🟢 Audio interruption ended');
					const shouldResume = (event.payload as any)?.shouldResume || false;

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

				case AudioProEventType.PLAYBACK_ERROR:
					Alert.alert('Playback Error', event.payload?.error || 'Unknown error');
					break;
			}
		});

		return removeListener;
	}, [wasPlayingBeforeInterruption]);

	const handlePlay = () => {
		AudioPro.play(currentTrack);
	};

	const handlePause = () => {
		AudioPro.pause();
	};

	const handleResume = () => {
		AudioPro.resume();
	};

	const handleStop = () => {
		AudioPro.stop();
	};

	return (
		<View style={styles.container}>
			<Text style={styles.title}>Audio Pro Example</Text>
			<Text style={styles.subtitle}>Professional Audio Interruption Handling</Text>

			<View style={styles.trackInfo}>
				<Text style={styles.trackTitle}>{currentTrack.title}</Text>
				<Text style={styles.trackArtist}>{currentTrack.artist}</Text>
			</View>

			<View style={styles.controls}>
				<TouchableOpacity style={styles.button} onPress={handlePlay}>
					<Text style={styles.buttonText}>Play</Text>
				</TouchableOpacity>

				<TouchableOpacity style={styles.button} onPress={handlePause}>
					<Text style={styles.buttonText}>Pause</Text>
				</TouchableOpacity>

				<TouchableOpacity style={styles.button} onPress={handleResume}>
					<Text style={styles.buttonText}>Resume</Text>
				</TouchableOpacity>

				<TouchableOpacity style={styles.button} onPress={handleStop}>
					<Text style={styles.buttonText}>Stop</Text>
				</TouchableOpacity>
			</View>

			<View style={styles.status}>
				<Text style={styles.statusText}>
					Status: {isPlaying ? 'Playing' : 'Paused/Stopped'}
				</Text>
			</View>
		</View>
	);
}
