export type Track = {
	id: string;
	url: string;
	title: string;
	artwork: string;
	artist: string;
	isLive?: boolean;
};

export const playlist: Track[] = [
	{
		id: 'remote-track-1',
		url: 'https://rnap.dev/audio-soundhelix-song-1-tschurger.mp3',
		title: 'Soundhelix Song 1',
		artwork: 'https://rnap.dev/artwork-usgs-bAji8qv_LlY-unsplash.jpg',
		artist: 'T. Schurger',
	},
	{
		id: 'stream-track-1',
		url: 'https://stream-akamai.castr.com/5b9352dbda7b8c769937e459/live_2361c920455111ea85db6911fe397b9e/index.fmp4.m3u8',
		title: 'Castr Stream (HLS)',
		artwork: 'https://rnap.dev/artwork-usgs-8tfu4320oxI-unsplash.jpg',
		artist: 'Castr',
		isLive: true,
	},
	{
		id: 'error-track-1',
		url: 'https://error',
		title: 'This track should error',
		artwork: 'https://error',
		artist: 'For test purposes',
	},
];
