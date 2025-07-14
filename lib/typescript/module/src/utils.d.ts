import type { AudioProTrack } from './types';
/**
 * Validates that a given path is a valid URL (http, https, or file).
 * If the path is undefined, it is considered valid (as it's optional).
 *
 * @param path - The path to validate
 * @internal
 */
export declare function validateFilePath(path: string | undefined): void;
/**
 * A simplified URL validation function that doesn't rely on the URL constructor.
 * It performs basic checks on the URL string to determine if it's valid.
 */
export declare function isValidUrl(url: string): boolean;
/**
 * Validates a track object to ensure it has all required properties with correct types
 *
 * @param track - The track object to validate
 * @returns true if the track is valid, false otherwise
 */
export declare function validateTrack(track: AudioProTrack): boolean;
/**
 * Guards against operations that require a track to be playing
 *
 * @param methodName - The name of the method being called
 * @returns true if a track is playing, false otherwise
 */
export declare function guardTrackPlaying(methodName: string): boolean;
/**
 * Logs debug messages if debug mode is enabled
 *
 * @param args - Arguments to log
 */
export declare function logDebug(...args: unknown[]): void;
/**
 * Normalizes a volume value to ensure it's between 0 and 1,
 * with at most 2 decimal places of precision.
 * Handles special cases for values near 0 and 1 to avoid floating-point artifacts.
 *
 * @param volume The volume value to normalize
 * @returns A normalized volume value between 0 and 1 with 2 decimal precision
 */
export declare function normalizeVolume(volume: number): number;
//# sourceMappingURL=utils.d.ts.map