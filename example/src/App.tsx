import { useEffect, useState } from 'react';

import { SafeAreaView, Text, TouchableOpacity, View, Image, ActivityIndicator } from 'react-native';

import {
	AudioPro,
	AudioProState,
	AudioProContentType,
	type AudioProEvent,
	AudioProEventType,
} from 'react-native-audio-pro';

import { styles } from './styles';
import { getStateColor } from './utils';

// Example radio stream
const radioStream = {
	id: 'radio-stream-1',
	url: 'https://stream-akamai.castr.com/5b9352dbda7b8c769937e459/live_2361c920455111ea85db6911fe397b9e/index.fmp4.m3u8',
	title: 'Example Radio Stream',
	artwork: 'https://rnap.dev/artwork-usgs-8tfu4320oxI-unsplash.jpg',
	artist: 'Radio Station',
};

export default function App() {
	const [playerState, setPlayerState] = useState(AudioProState.IDLE);
	const [error, setError] = useState<string | null>(null);
	const [volume, setVolume] = useState(1.0);

	// Set up the audio player on component mount
	useEffect(() => {
		// Configure the audio player
		AudioPro.configure({
			contentType: AudioProContentType.MUSIC,
			debug: true,
			progressIntervalMs: 1000,
		});

		// Set up event listener
		const subscription = AudioPro.addEventListener((event: AudioProEvent) => {
			switch (event.type) {
				case AudioProEventType.STATE_CHANGED:
					if (event.payload?.state) {
						setPlayerState(event.payload.state);
					}
					break;

				case AudioProEventType.PLAYBACK_ERROR:
					if (event.payload?.error) {
						setError(event.payload.error);
					}
					break;
			}
		});

		// Clean up listener on unmount
		return () => {
			subscription.remove();
		};
	}, []);

	// Play the radio stream
	const handlePlay = () => {
		setError(null);
		AudioPro.play(radioStream);
	};

	// Stop the radio stream
	const handleStop = () => {
		AudioPro.stop();
	};

	// Increase volume
	const handleVolumeUp = () => {
		const newVolume = Math.min(1.0, volume + 0.1);
		setVolume(newVolume);
		AudioPro.setVolume(newVolume);
	};

	// Decrease volume
	const handleVolumeDown = () => {
		const newVolume = Math.max(0.0, volume - 0.1);
		setVolume(newVolume);
		AudioPro.setVolume(newVolume);
	};

	// Get button text based on player state
	const getButtonText = () => {
		switch (playerState) {
			case AudioProState.PLAYING:
				return 'Stop';
			case AudioProState.LOADING:
				return 'Loading...';
			default:
				return 'Play';
		}
	};

	// Get button handler based on player state
	const getButtonHandler = () => {
		return playerState === AudioProState.PLAYING ? handleStop : handlePlay;
	};

	return (
		<SafeAreaView style={styles.container}>
			<View style={styles.container}>
				<Text style={styles.title}>Radio Player Example</Text>
			</View>

			<View style={styles.container}>
				{/* Radio station artwork */}
				<Image
					source={{ uri: radioStream.artwork }}
					style={styles.artwork}
					resizeMode="cover"
				/>

				{/* Radio station info */}
				<View style={styles.container}>
					<Text style={styles.title}>{radioStream.title}</Text>
					<Text style={styles.artist}>{radioStream.artist}</Text>

					{/* Player state indicator */}
					<View style={styles.generalRow}>
						<View
							style={[
								styles.controlText,
								{ backgroundColor: getStateColor(playerState) },
							]}
						/>
						<Text style={styles.stateText}>{playerState}</Text>
					</View>
				</View>

				{/* Error message */}
				{error && (
					<View style={styles.errorContainer}>
						<Text style={styles.errorText}>{error}</Text>
					</View>
				)}

				{/* Controls */}
				<View style={styles.controlsRow}>
					{/* Volume controls */}
					<View style={styles.speedRow}>
						<TouchableOpacity style={styles.controlText} onPress={handleVolumeDown}>
							<Text style={styles.controlText}>-</Text>
						</TouchableOpacity>

						<Text style={styles.speedText}>Volume: {Math.round(volume * 100)}%</Text>

						<TouchableOpacity style={styles.controlText} onPress={handleVolumeUp}>
							<Text style={styles.controlText}>+</Text>
						</TouchableOpacity>
					</View>

					{/* Play/Stop button */}
					<TouchableOpacity
						style={[
							styles.controlText,
							playerState === AudioProState.LOADING && styles.loadingContainer,
						]}
						onPress={getButtonHandler()}
						disabled={playerState === AudioProState.LOADING}
					>
						{playerState === AudioProState.LOADING ? (
							<ActivityIndicator color="#fff" />
						) : (
							<Text style={styles.controlText}>{getButtonText()}</Text>
						)}
					</TouchableOpacity>
				</View>
			</View>
		</SafeAreaView>
	);
}
