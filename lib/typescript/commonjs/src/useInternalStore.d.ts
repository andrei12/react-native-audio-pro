import { AudioProState } from './values';
import type { AudioProConfigureOptions, AudioProEvent, AudioProPlaybackErrorPayload, AudioProTrack } from './types';
export interface AudioProStore {
    playerState: AudioProState;
    position: number;
    duration: number;
    playbackSpeed: number;
    volume: number;
    debug: boolean;
    debugIncludesProgress: boolean;
    trackPlaying: AudioProTrack | null;
    configureOptions: AudioProConfigureOptions;
    error: AudioProPlaybackErrorPayload | null;
    setDebug: (debug: boolean) => void;
    setDebugIncludesProgress: (includeProgress: boolean) => void;
    setTrackPlaying: (track: AudioProTrack | null) => void;
    setConfigureOptions: (options: AudioProConfigureOptions) => void;
    setPlaybackSpeed: (speed: number) => void;
    setVolume: (volume: number) => void;
    setError: (error: AudioProPlaybackErrorPayload | null) => void;
    updateFromEvent: (event: AudioProEvent) => void;
}
export declare const useInternalStore: import("zustand").UseBoundStore<import("zustand").StoreApi<AudioProStore>>;
//# sourceMappingURL=useInternalStore.d.ts.map