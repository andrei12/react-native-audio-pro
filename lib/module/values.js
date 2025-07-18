"use strict";

/**
 * Default seek interval in milliseconds (30 seconds)
 */
export const DEFAULT_SEEK_MS = 30000;

/**
 * Content type for audio playback
 */
export let AudioProContentType = /*#__PURE__*/function (AudioProContentType) {
  /** Music content type */
  AudioProContentType["MUSIC"] = "MUSIC";
  /** Speech content type */
  AudioProContentType["SPEECH"] = "SPEECH";
  return AudioProContentType;
}({});

/**
 * Possible states of the audio player
 */
export let AudioProState = /*#__PURE__*/function (AudioProState) {
  /** Initial state, no track loaded */
  AudioProState["IDLE"] = "IDLE";
  /** Track is loaded but not playing */
  AudioProState["STOPPED"] = "STOPPED";
  /** Track is being loaded */
  AudioProState["LOADING"] = "LOADING";
  /** Track is currently playing */
  AudioProState["PLAYING"] = "PLAYING";
  /** Track is paused */
  AudioProState["PAUSED"] = "PAUSED";
  /** An error has occurred */
  AudioProState["ERROR"] = "ERROR";
  return AudioProState;
}({});

/**
 * Types of events that can be emitted by the audio player
 */
export let AudioProEventType = /*#__PURE__*/function (AudioProEventType) {
  /** Player state has changed */
  AudioProEventType["STATE_CHANGED"] = "STATE_CHANGED";
  /** Playback progress update */
  AudioProEventType["PROGRESS"] = "PROGRESS";
  /** Track has ended */
  AudioProEventType["TRACK_ENDED"] = "TRACK_ENDED";
  /** Seek operation has completed */
  AudioProEventType["SEEK_COMPLETE"] = "SEEK_COMPLETE";
  /** Playback speed has changed */
  AudioProEventType["PLAYBACK_SPEED_CHANGED"] = "PLAYBACK_SPEED_CHANGED";
  /** Remote next button pressed */
  AudioProEventType["REMOTE_NEXT"] = "REMOTE_NEXT";
  /** Remote previous button pressed */
  AudioProEventType["REMOTE_PREV"] = "REMOTE_PREV";
  /** Playback error has occurred */
  AudioProEventType["PLAYBACK_ERROR"] = "PLAYBACK_ERROR";
  /** Audio interruption began (timer, call, etc.) */
  AudioProEventType["AUDIO_INTERRUPTION_BEGAN"] = "AUDIO_INTERRUPTION_BEGAN";
  /** Audio interruption ended */
  AudioProEventType["AUDIO_INTERRUPTION_ENDED"] = "AUDIO_INTERRUPTION_ENDED";
  return AudioProEventType;
}({});

/**
 * Sources for seek-complete events.
 */
export let AudioProTriggerSource = /*#__PURE__*/function (AudioProTriggerSource) {
  /** Seek initiated by user or app code */
  AudioProTriggerSource["USER"] = "USER";
  /** Seek initiated by system or remote controls */
  AudioProTriggerSource["SYSTEM"] = "SYSTEM";
  return AudioProTriggerSource;
}({});

/**
 * Types of events that can be emitted by the ambient audio player
 */
export let AudioProAmbientEventType = /*#__PURE__*/function (AudioProAmbientEventType) {
  /** Ambient track has ended */
  AudioProAmbientEventType["AMBIENT_TRACK_ENDED"] = "AMBIENT_TRACK_ENDED";
  /** Ambient audio error has occurred */
  AudioProAmbientEventType["AMBIENT_ERROR"] = "AMBIENT_ERROR";
  return AudioProAmbientEventType;
}({});

/**
 * Default configuration options for the audio player
 */
export const DEFAULT_CONFIG = {
  /** Default content type */
  contentType: AudioProContentType.MUSIC,
  /** Whether debug logging is enabled */
  debug: false,
  /** Whether to include progress events in debug logs */
  debugIncludesProgress: false,
  /** Interval in milliseconds for progress events */
  progressIntervalMs: 1000,
  /** Whether to show next/previous controls */
  showNextPrevControls: true
};
//# sourceMappingURL=values.js.map