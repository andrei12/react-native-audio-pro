import Foundation
import AVFoundation
import React
import MediaPlayer
import UIKit

@objc(AudioPro)
class AudioPro: RCTEventEmitter {

	////////////////////////////////////////////////////////////
	// MARK: - Properties & Constants
	////////////////////////////////////////////////////////////

	private var player: AVPlayer?
	private var timer: Timer?
	private var hasListeners = false
	private let EVENT_NAME = "AudioProEvent"
	private let AMBIENT_EVENT_NAME = "AudioProAmbientEvent"

	private var ambientPlayer: AVPlayer?
	private var ambientPlayerItem: AVPlayerItem?


	// Event types
	private let EVENT_TYPE_STATE_CHANGED = "STATE_CHANGED"
	private let EVENT_TYPE_TRACK_ENDED = "TRACK_ENDED"
	private let EVENT_TYPE_PLAYBACK_ERROR = "PLAYBACK_ERROR"
	private let EVENT_TYPE_PROGRESS = "PROGRESS"
	private let EVENT_TYPE_SEEK_COMPLETE = "SEEK_COMPLETE"
	private let EVENT_TYPE_REMOTE_NEXT = "REMOTE_NEXT"
	private let EVENT_TYPE_REMOTE_PREV = "REMOTE_PREV"
	private let EVENT_TYPE_PLAYBACK_SPEED_CHANGED = "PLAYBACK_SPEED_CHANGED"

	// Seek trigger sources
	private let TRIGGER_SOURCE_USER = "USER"
	private let TRIGGER_SOURCE_SYSTEM = "SYSTEM"

	// Ambient audio event types
	private let EVENT_TYPE_AMBIENT_TRACK_ENDED = "AMBIENT_TRACK_ENDED"
	private let EVENT_TYPE_AMBIENT_ERROR = "AMBIENT_ERROR"

	// States
	private let STATE_IDLE = "IDLE"
	private let STATE_STOPPED = "STOPPED"
	private let STATE_LOADING = "LOADING"
	private let STATE_PLAYING = "PLAYING"
	private let STATE_PAUSED = "PAUSED"
	private let STATE_ERROR = "ERROR"

	private let GENERIC_ERROR_CODE = 900
	private var shouldBePlaying = false
	private var isRemoteCommandCenterSetup = false

	private var isRateObserverAdded = false
	private var isStatusObserverAdded = false

	private var currentPlaybackSpeed: Float = 1.0
	private var currentTrack: NSDictionary?

	private var settingDebug: Bool = false
	private var settingDebugIncludeProgress: Bool = false
	private var settingProgressInterval: TimeInterval = 1.0
	private var settingShowNextPrevControls = true
	private var settingLoopAmbient: Bool = true

	private var activeVolume: Float = 1.0
	private var activeVolumeAmbient: Float = 1.0

	private var isInErrorState: Bool = false
	private var lastEmittedState: String = ""
	private var wasPlayingBeforeInterruption: Bool = false
	private var pendingStartTimeMs: Double? = nil
	private var isExplicitlyStopped: Bool = false  // Track if user explicitly stopped (vs just paused)

	////////////////////////////////////////////////////////////
	// MARK: - Initialization
	////////////////////////////////////////////////////////////

	override init() {
		super.init()
		// Set up interruption observer immediately when module is created
		// This ensures we can handle interruptions even before playback starts
		setupAudioSessionInterruptionObserver()
		log("AudioPro module initialized with interruption observer")
	}

	////////////////////////////////////////////////////////////
	// MARK: - React Native Event Emitter Overrides
	////////////////////////////////////////////////////////////

	override func supportedEvents() -> [String]! {
		return [EVENT_NAME, AMBIENT_EVENT_NAME]
	}

	override static func requiresMainQueueSetup() -> Bool {
		return false
	}

	override func startObserving() {
		hasListeners = true
	}

	override func stopObserving() {
		hasListeners = false
	}

	private func setupAudioSessionInterruptionObserver() {
		print("🚨 [AudioPro] SETTING UP INTERRUPTION OBSERVER")
		
		// Register for audio session interruption notifications
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAudioSessionInterruption(_:)),
			name: AVAudioSession.interruptionNotification,
			object: nil
		)
		
		// Register for media server reset notifications per Apple guidelines
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleMediaServicesReset(_:)),
			name: AVAudioSession.mediaServicesWereResetNotification,
			object: nil
		)

		print("🚨 [AudioPro] INTERRUPTION OBSERVER SETUP COMPLETE")
		log("Registered for audio session interruption and media server reset notifications")
		
		// Test that the observer is working by posting a test notification
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
			print("🚨 [AudioPro] TESTING INTERRUPTION OBSERVER - if you see this, the observer is working")
		}
	}

	private func removeAudioSessionInterruptionObserver() {
		NotificationCenter.default.removeObserver(
			self,
			name: AVAudioSession.interruptionNotification,
			object: nil
		)
		
		// Remove media server reset observer
		NotificationCenter.default.removeObserver(
			self,
			name: AVAudioSession.mediaServicesWereResetNotification,
			object: nil
		)
	}

	@objc private func handleAudioSessionInterruption(_ notification: Notification) {
		// UNCONDITIONAL logging to verify this handler is called
		print("🚨 [AudioPro] INTERRUPTION HANDLER CALLED!")
		
		guard let userInfo = notification.userInfo,
			  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
			  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
			print("🚨 [AudioPro] INTERRUPTION: Invalid notification data")
			return
		}

		switch type {
		case .began:
			print("🚨 [AudioPro] INTERRUPTION BEGAN!")
			log("🔴 Audio session interruption began (timer/call/alarm)")
			// Determine if we *intended* to be playing when the interruption began.
			// Using `shouldBePlaying` is more reliable than `player?.rate` because the
			// system sets `rate` to 0 *before* posting the `.began` notification. This
			// caused false negatives for short interruptions such as Clock alarms.
			// We still fall back to checking the current rate to cover edge-cases in
			// which `shouldBePlaying` might be out-of-sync.
			wasPlayingBeforeInterruption = shouldBePlaying || (player?.rate ?? 0) != 0
			log("🔴 wasPlayingBeforeInterruption = \(wasPlayingBeforeInterruption) (shouldBePlaying=\(shouldBePlaying), rate=\(player?.rate ?? 0))")

			if wasPlayingBeforeInterruption {
				// Pause playback but don't emit state change
				player?.pause()
				stopTimer()
				
				// Update UI state to paused
				shouldBePlaying = false
				sendPausedStateEvent()
				
				// CRITICAL: Update lock screen controls to show paused state
				updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 0.0)
				log("🔴 Lock screen controls updated to show PAUSED state")
			}
		case .ended:
			print("🚨 [AudioPro] INTERRUPTION ENDED!")
			log("🟡 Audio session interruption ended")
			
			// Per Apple guidelines: Check if we were playing before interruption
			guard wasPlayingBeforeInterruption else {
				log("🟡 Was not playing before interruption, no action needed")
				wasPlayingBeforeInterruption = false
				return
			}
			
			// Get the interruption options (may not be present for all interruption types)
			let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt
			let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue ?? 0)
			
			log("🟡 Interruption options: \(optionsValue ?? 0), shouldResume: \(options.contains(.shouldResume))")
			
			// Check for shouldResume flag as per Apple guidelines
			if options.contains(.shouldResume) {
				log("🟢 Interruption ended WITH shouldResume flag - auto-resuming playback")
				attemptResumeAfterInterruption()
			} else {
				log("🔴 Interruption ended WITHOUT shouldResume flag - staying paused per Apple guidelines")
				// Per Apple guidelines: Don't auto-resume if shouldResume flag is not present
				// Update internal state and UI to reflect that we're paused, not playing
				shouldBePlaying = false
				stopTimer()
				
				// Update UI to show paused state (critical for user experience)
				sendPausedStateEvent()
				
				// Update now playing info to reflect paused state
				updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 0.0)
				
				log("🔴 UI updated to PAUSED state - user must manually resume")
			}

			// Reset the flag
			wasPlayingBeforeInterruption = false
		@unknown default:
			break
		}
	}
	
	/// Handles media server reset per Apple's Audio Guidelines
	/// The media server provides audio functionality through a shared server process.
	/// When it resets, all audio objects become orphaned and must be recreated.
	@objc private func handleMediaServicesReset(_ notification: Notification) {
		log("Media services were reset - recreating audio objects per Apple guidelines")
		
		// Remember current state
		let wasPlaying = shouldBePlaying
		let currentPosition = player?.currentTime().seconds ?? 0
		let savedTrack = currentTrack
		
		// Per Apple guidelines: Dispose of orphaned audio objects and create new ones
		cleanup(emitStateChange: false, clearTrack: false)
		
		// Reset internal audio states as required by Apple
		shouldBePlaying = false
		wasPlayingBeforeInterruption = false
		isInErrorState = false
		lastEmittedState = ""
		
		// If we had a track and were playing, attempt to restore playback
		if let track = savedTrack, wasPlaying {
			log("Attempting to restore playback after media server reset")
			
			// Recreate the player with the same track
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
				guard let self = self else { return }
				
				// Use the existing play method to recreate everything
				let options: NSDictionary = [
					"autoPlay": false, // Don't auto-play, let user decide
					"debug": self.settingDebug
				]
				
				self.play(track: track, options: options)
				
				// Update UI to show that manual restart is needed
				self.sendPausedStateEvent()
				self.log("Media server reset recovery complete - manual restart required")
			}
		} else {
			// No active playback to restore
			sendStateEvent(state: STATE_IDLE, position: 0, duration: 0, track: nil)
		}
	}
	
	/// Attempts to resume playback after an interruption when shouldResume flag is present
	/// Per Apple's Audio Guidelines for User-Controlled Playback Apps
	private func attemptResumeAfterInterruption() {
		do {
			let session = AVAudioSession.sharedInstance()
			
			// Check if session is already active
			if !session.isOtherAudioPlaying {
				try session.setActive(true, options: .notifyOthersOnDeactivation)
				log("Audio session reactivated successfully after interruption")
			} else {
				log("Other audio is playing, keeping session active")
			}
			
			// Ensure we still have a valid player and track
			guard let player = player, let _ = player.currentItem, let _ = currentTrack else {
				log("Player or track lost during interruption, cannot resume")
				shouldBePlaying = false
				sendPausedStateEvent()
				return
			}
			
			// Attempt to resume playback
			player.play()
			shouldBePlaying = true
			
			// Emit a LOADING state first; observers will emit PLAYING when rate actually rises > 0
			let info = getPlaybackInfo()
			sendStateEvent(state: STATE_LOADING, position: info.position, duration: info.duration, track: info.track)
			
			// Update now playing info to show we're preparing to resume (rate 0)
			let currentTime = player.currentTime().seconds
			let validTime = (currentTime.isNaN || currentTime.isInfinite) ? 0 : currentTime
			updateNowPlayingInfo(time: validTime, rate: 0.0)
			
			// Remote controls: keep them enabled but don't alter next/prev yet
			updateNextPrevControlsState()
			
			// Progress timer will start once rate observer fires.
			log("Playback resume initiated after interruption – awaiting player rate > 0")

			// Retry logic: if after 3 s the player rate is still 0 while we expect playback, retry once.
			DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
				guard let self = self else { return }
				if self.shouldBePlaying, let player = self.player, player.rate == 0 {
					self.log("Resume watchdog: rate still 0 after 3s – retrying play() once")
					player.play()
					// If it still fails after retry, we'll leave UI in paused state for user.
					DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
						guard let self = self else { return }
						if self.shouldBePlaying, let player = self.player, player.rate == 0 {
							self.log("Resume watchdog: second attempt failed – reverting to PAUSED state")
							self.shouldBePlaying = false
							self.sendPausedStateEvent()
							self.updateNowPlayingInfo(time: player.currentTime().seconds, rate: 0.0)
						}
					}
				}
			}
			
		} catch {
			log("Failed to reactivate audio session after interruption: \(error.localizedDescription)")
			
			// Update state to reflect failure to resume
			shouldBePlaying = false
			stopTimer()
			sendPausedStateEvent()
			updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 0.0)
			
			// Emit error to inform the app
			emitPlaybackError("Unable to resume audio playback")
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Debug Logging Helper
	////////////////////////////////////////////////////////////

	private func log(_ items: Any...) {
		guard settingDebug else { return }

		if !settingDebugIncludeProgress && items.count > 0 {
			if let firstItem = items.first, "\(firstItem)" == EVENT_TYPE_PROGRESS {
				return
			}
		}

		print("~~~ [AudioPro]", items.map { "\($0)" }.joined(separator: " "))
	}

	private func sendEvent(type: String, track: Any?, payload: [String: Any]?) {
		guard hasListeners else { return }

		var body: [String: Any] = [
			"type": type,
			"track": track as Any
		]

		if let payload = payload {
			body["payload"] = payload
		}

		log(type)

		sendEvent(withName: EVENT_NAME, body: body)
	}


	////////////////////////////////////////////////////////////
	// MARK: - Timers & Progress Updates
	////////////////////////////////////////////////////////////

	private func startProgressTimer() {
		DispatchQueue.main.async {
			self.timer?.invalidate()
			self.sendProgressNoticeEvent()
			self.timer = Timer.scheduledTimer(withTimeInterval: self.settingProgressInterval, repeats: true) { [weak self] _ in
				self?.sendProgressNoticeEvent()
			}
		}
	}

	private func stopTimer() {
		DispatchQueue.main.async {
			self.timer?.invalidate()
			self.timer = nil
		}
	}

	private func sendProgressNoticeEvent() {
		guard let player = player, let _ = player.currentItem, player.rate != 0 else { return }
		let info = getPlaybackInfo()

		let payload: [String: Any] = [
			"position": info.position,
			"duration": info.duration
		]
		sendEvent(type: EVENT_TYPE_PROGRESS, track: info.track, payload: payload)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Playback Control (Play, Pause, Resume, Stop)
	////////////////////////////////////////////////////////////

	/// Prepares the player for new playback without emitting state changes or destroying the media session
	/// - This function:
	/// - Pauses the player if it's playing
	/// - Removes KVO observers from the previous AVPlayerItem
	/// - Stops the progress timer
	/// - Does not emit any state or clear currentTrack
	/// - Does not destroy the media session
	private func prepareForNewPlayback() {
		// Pause the player if it's playing
		player?.pause()

		// Stop the progress timer
		stopTimer()

		// Remove KVO observers from the previous AVPlayerItem
		if let player = player {
			if isRateObserverAdded {
				player.removeObserver(self, forKeyPath: "rate")
				isRateObserverAdded = false
			}
			if let currentItem = player.currentItem {
				if isStatusObserverAdded {
					currentItem.removeObserver(self, forKeyPath: "status")
					isStatusObserverAdded = false
				}
				
				// Remove buffering observers
				currentItem.removeObserver(self, forKeyPath: "playbackBufferEmpty", context: nil)
				currentItem.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp", context: nil)
				currentItem.removeObserver(self, forKeyPath: "playbackBufferFull", context: nil)
			}
		}

		// Remove playback ended notification observer
		NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: player?.currentItem)
	}

	@objc(play:withOptions:)
	func play(track: NSDictionary, options: NSDictionary) {
		// Reset error state when playing a new track
		isInErrorState = false
		// Reset last emitted state when playing a new track
		lastEmittedState = ""
		// Reset explicitly stopped flag when playing
		isExplicitlyStopped = false
		currentTrack = track
		settingDebug = options["debug"] as? Bool ?? false
		settingDebugIncludeProgress = options["debugIncludesProgress"] as? Bool ?? false
		let speed = Float(options["playbackSpeed"] as? Double ?? 1.0)
		let volume = Float(options["volume"] as? Double ?? 1.0)
		let autoPlay = options["autoPlay"] as? Bool ?? true
		let contentType = options["contentType"] as? String ?? ""
		
		// Get URL from track
		guard let urlString = track["url"] as? String, let url = URL(string: urlString) else {
			onError("Invalid URL provided")
			return
		}
		
		// Clean up previous player if it exists
		prepareForNewPlayback()
		
		// Send loading state immediately so UI can update
		if autoPlay {
			shouldBePlaying = true
			sendStateEvent(state: STATE_LOADING, position: 0, duration: 0, track: currentTrack)
		}
		
		// Configure audio session first to ensure proper setup
		do {
			try configureAudioSession()
		} catch {
			log("Failed to configure audio session: \(error.localizedDescription)")
			emitPlaybackError("Unable to configure audio playback")
			// Continue anyway, as playback might still work
		}
		
		// Move heavy operations to background queue
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }
			
			// Create player item with URL
			let headers = options["headers"] as? NSDictionary
			let playerItem = self.createPlayerItem(with: url, headers: headers)
			
			// Set preferred forward buffer duration for better buffering
			playerItem.preferredForwardBufferDuration = 5.0
			
			// Return to main queue for player setup
			DispatchQueue.main.async {
				// Create player with the item
				self.player = AVPlayer(playerItem: playerItem)
				self.player?.volume = volume
				
				// Set automatic buffering
				self.player?.automaticallyWaitsToMinimizeStalling = true
				
				// Always use normal playback speed for live streams
				self.player?.rate = 1.0
				self.currentPlaybackSpeed = 1.0
				
				// Setup observers for the player item
				self.setupPlayerItemObservers(playerItem)
				
				// Update the remote command center
				self.setupRemoteTransportControls()
				
				// Update the now playing info
				self.updateNowPlayingInfo(time: 0, rate: autoPlay ? 1.0 : 0.0)
				
				// Start playback if autoPlay is true
				if autoPlay {
					self.player?.play()
					
					// Set a timeout to check if playback started
					DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
						guard let self = self else { return }
						if self.shouldBePlaying && self.player?.rate == 0 {
							// If still not playing after 5 seconds, try to restart playback
							self.log("Playback didn't start after 5 seconds, trying to restart")
							self.player?.play()
						}
					}
				} else {
					self.shouldBePlaying = false
					self.sendStateEvent(state: self.STATE_PAUSED, position: 0, duration: 0)
				}
			}
		}
	}

	@objc(pause)
	func pause() {
		print("🚨 [AudioPro] PAUSE CALLED")
		log("[Pause] Called. player=\(player != nil), shouldBePlaying=\(shouldBePlaying), player?.rate=\(String(describing: player?.rate))")
		shouldBePlaying = false
		isExplicitlyStopped = false  // This is a pause, not a stop
		player?.pause()
		stopTimer()
		sendPausedStateEvent()
		updateNowPlayingInfo(time: player?.currentTime().seconds ?? 0, rate: 0)
		print("🚨 [AudioPro] PAUSE COMPLETED, rate=\(String(describing: player?.rate))")
		log("[Pause] Completed. player=\(player != nil), player?.rate=\(String(describing: player?.rate))")
	}

	@objc(resume)
	func resume() {
		log("[Resume] Called. player=\(player != nil), isExplicitlyStopped=\(isExplicitlyStopped), shouldBePlaying=\(shouldBePlaying), player?.rate=\(String(describing: player?.rate))")
		
		// If we don't have a track, nothing to resume
		guard let _ = currentTrack else {
			log("[Resume] No track to resume")
			onError("Cannot resume: no track loaded")
			return
		}
		
		// ONLY restart from scratch if explicitly stopped (user called stop())
		if isExplicitlyStopped {
			log("[Resume] Restarting from explicit stop")
			isExplicitlyStopped = false
			let options: NSDictionary = ["autoPlay": true, "debug": settingDebug]
			play(track: currentTrack!, options: options)
			return
		}
		
		// For everything else (pause, interruptions), just resume the existing player
		// If player is nil but we weren't explicitly stopped, something went wrong - restart
		guard let player = player, let _ = player.currentItem else {
			log("[Resume] Player lost unexpectedly, restarting")
			let options: NSDictionary = ["autoPlay": true, "debug": settingDebug]
			play(track: currentTrack!, options: options)
			return
		}
		
		log("[Resume] Simple resume - just starting existing player")
		shouldBePlaying = true
		
		// Try to reactivate audio session and resume
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }
			
			do {
				let session = AVAudioSession.sharedInstance()
				if !session.isOtherAudioPlaying {
					try session.setActive(true, options: .notifyOthersOnDeactivation)
					self.log("[Resume] Audio session reactivated")
				}
				
				DispatchQueue.main.async {
					// Double-check player is still valid
					guard let player = self.player, let _ = player.currentItem else {
						self.log("[Resume] Player lost during session activation")
						return
					}
					
					// Just resume playback
					player.play()
					self.log("[Resume] Player resumed, rate=\(player.rate)")
					
					// Update UI and controls
					let currentTime = player.currentTime().seconds
					let validTime = (currentTime.isNaN || currentTime.isInfinite) ? 0 : currentTime
					self.updateNowPlayingInfo(time: validTime, rate: 1.0)
					self.updateNextPrevControlsState()
					self.startProgressTimer()
					
					// Send playing state
					self.sendPlayingStateEvent()
				}
			} catch {
				DispatchQueue.main.async {
					self.log("[Resume] Audio session activation failed: \(error.localizedDescription)")
					// Still try to resume
					guard let player = self.player else { return }
					player.play()
					self.startProgressTimer()
					self.sendPlayingStateEvent()
				}
			}
		}
	}

	/// stop is meant to halt playback and update the state without destroying persistent info
	/// such as artwork and remote control settings. This allows the lock screen/Control Center
	/// to continue displaying the track details for a potential resume.
	@objc func stop() {
		log("[Stop] Called. player=\(player != nil), shouldBePlaying=\(shouldBePlaying)")
		// Reset error state when explicitly stopping
		isInErrorState = false
		// Reset last emitted state when stopping playback
		lastEmittedState = ""
		shouldBePlaying = false
		isExplicitlyStopped = true  // Mark as explicitly stopped

		pendingStartTimeMs = nil

		// For live streams, we need to tear down the player connection rather than just pausing
		// because seeking to zero on a live stream puts the player in an invalid state
		log("Stopping playback - cleaning up player for live stream")
		
		// Clean up the player but preserve track metadata and remote controls
		prepareForNewPlayback()
		
		// For live streams, fully disconnect by clearing the player
		// This ensures resume() will restart the stream connection
		player = nil
		
		stopTimer()
		// Do not set currentTrack = nil as STOPPED state should preserve track metadata
		sendStoppedStateEvent()

		// Update now playing info to reflect a stopped state but keep the artwork intact.
		updateNowPlayingInfo(time: 0, rate: 0)
	}

	/// Resets the player to IDLE state, fully tears down the player instance,
	/// and removes all media sessions.
	@objc(clear)
	func clear() {
		log("Clear called")
		resetInternal(STATE_IDLE)
	}

	/// Shared internal function that performs the teardown and emits the correct state.
	/// Used by both clear() and error transitions.
	/// - Parameter finalState: The state to emit after resetting (IDLE or ERROR)
	private func resetInternal(_ finalState: String) {
		// Reset error state
		isInErrorState = finalState == STATE_ERROR
		// Reset last emitted state
		lastEmittedState = ""
		shouldBePlaying = false
		isExplicitlyStopped = false

		// Reset volume to default
		activeVolume = 1.0

		pendingStartTimeMs = nil

		// Stop playback
		player?.pause()

		// Clear track and stop timers
		stopTimer()
		currentTrack = nil

		// Release resources and remove observers
		// We've already cleared currentTrack, so we don't need to do it again in cleanup
		cleanup(emitStateChange: false, clearTrack: false)

		// Emit the final state
		// Explicitly pass nil as the track parameter to ensure the state is emitted consistently
		sendStateEvent(state: finalState, position: 0, duration: 0, track: nil)
	}

	/// cleanup fully tears down the player instance and removes observers and remote controls.
	/// This is used when switching tracks or recovering from an error.
	/// - Parameter emitStateChange: Whether to emit a STOPPED state change event (default: true)
	/// - Parameter clearTrack: Whether to clear the currentTrack (default: true)
	@objc func cleanup(emitStateChange: Bool = true, clearTrack: Bool = true) {
		log("Cleanup", "emitStateChange:", emitStateChange, "clearTrack:", clearTrack)

		// Reset pending start time
		pendingStartTimeMs = nil

		shouldBePlaying = false

		NotificationCenter.default.removeObserver(self)

		// Explicitly remove audio session interruption observer
		removeAudioSessionInterruptionObserver()

		if let player = player {
			if isRateObserverAdded {
				player.removeObserver(self, forKeyPath: "rate")
				isRateObserverAdded = false
			}
			if let currentItem = player.currentItem, isStatusObserverAdded {
				currentItem.removeObserver(self, forKeyPath: "status")
				isStatusObserverAdded = false
			}
		}

		player?.pause()
		player = nil

		stopTimer()

		// Only clear the track if requested
		if clearTrack {
			currentTrack = nil
		}

		// Only emit state change if requested and not in error state
		if emitStateChange && !isInErrorState {
			sendStoppedStateEvent()
		}

		// Clear the now playing info and remote control events
		DispatchQueue.main.async {
			MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
			UIApplication.shared.endReceivingRemoteControlEvents()
			self.removeRemoteTransportControls()
			self.isRemoteCommandCenterSetup = false
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Seeking Methods
	////////////////////////////////////////////////////////////

	/// Common seek implementation used by all seek methods
	private func performSeek(to position: Double, isAbsolute: Bool = true) {
		guard let player = player else {
			onError("Cannot seek: no track is playing")
			return
		}

		guard let currentItem = player.currentItem else {
			onError("Cannot seek: no item loaded")
			return
		}

		let duration = currentItem.duration.seconds
		let currentTime = player.currentTime().seconds

		// For relative seeking (forward/back), we need valid current time
		if !isAbsolute && (currentTime.isNaN || currentTime.isInfinite) {
			onError("Cannot seek: invalid track position")
			return
		}

		// For all seeks, we need valid duration
		if duration.isNaN || duration.isInfinite {
			onError("Cannot seek: invalid track duration")
			return
		}

		stopTimer()

		// Calculate target position based on whether this is absolute or relative
		let targetPosition: Double
		if isAbsolute {
			// For seekTo, convert ms to seconds
			targetPosition = position / 1000.0
		} else {
			// For seekForward/Back, position is the amount in ms
			let amountInSeconds = position / 1000.0
			targetPosition = isAbsolute ? amountInSeconds :
							 (position >= 0) ? min(currentTime + amountInSeconds, duration) :
											  max(0, currentTime + amountInSeconds)
		}

		// Ensure position is within valid range
		let validPosition = max(0, min(targetPosition, duration))
		let time = CMTime(seconds: validPosition, preferredTimescale: 1000)

		player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] completed in
			guard let self = self else { return }
			if completed {
				self.updateNowPlayingInfoWithCurrentTime(validPosition)
				self.completeSeekingAndSendSeekCompleteNoticeEvent(newPosition: validPosition * 1000)

				// Force update the now playing info to ensure controls work
				if isAbsolute { // Only do this for absolute seeks to avoid redundant updates
					DispatchQueue.main.async {
						var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
						info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = validPosition
						info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
						// Always set live stream indicator for live audio streams
						info[MPNowPlayingInfoPropertyIsLiveStream] = true
						MPNowPlayingInfoCenter.default().nowPlayingInfo = info
					}
				}
			} else if player.rate != 0 {
				self.startProgressTimer()
			}
		}
	}

	@objc(seekTo:)
	func seekTo(positionMs: Double) {
		// Seeking is disabled for radio streams
		log("seekTo() ignored for radio stream")
	}

	@objc(seekForward:)
	func seekForward(offsetMs: Double) {
		// Seeking is disabled for radio streams
		log("seekForward() ignored for radio stream")
	}

	@objc(seekBack:)
	func seekBack(offsetMs: Double) {
		// Seeking is disabled for radio streams
		log("seekBack() ignored for radio stream")
	}


	private func completeSeekingAndSendSeekCompleteNoticeEvent(newPosition: Double) {
		if hasListeners {
			let info = getPlaybackInfo()

			let payload: [String: Any] = [
				"position": info.position,
				"duration": info.duration,
				"triggeredBy": TRIGGER_SOURCE_USER
			]
			sendEvent(type: EVENT_TYPE_SEEK_COMPLETE, track: info.track, payload: payload)
		}
		if player?.rate != 0 {
			// Resume progress timer after a short delay to ensure UI is in sync
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.10) {
				self.startProgressTimer()
			}
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Playback Speed
	////////////////////////////////////////////////////////////

	@objc(setPlaybackSpeed:)
	func setPlaybackSpeed(speed: Double) {
		currentPlaybackSpeed = Float(speed)

		guard let player = player else {
			onError("Cannot set playback speed: no track is playing")
			return
		}

		log("Setting playback speed to ", speed)
		player.rate = Float(speed)

		updateNowPlayingInfo(rate: Float(speed))

		if hasListeners {
			let playbackInfo = getPlaybackInfo()
			let payload: [String: Any] = ["speed": speed]
			sendEvent(type: EVENT_TYPE_PLAYBACK_SPEED_CHANGED, track: playbackInfo.track, payload: payload)
		}
	}

	@objc(setVolume:)
	func setVolume(volume: Double) {
		activeVolume = Float(volume)

		guard let player = player else {
			log("Cannot set volume: no track is playing")
			return
		}

		log("Setting volume to ", volume)
		player.volume = Float(volume)
	}

	////////////////////////////////////////////////////////////
	// MARK: - KVO & Notification Handlers
	////////////////////////////////////////////////////////////

	/**
	 * Handles track completion according to the contract in logic.md:
	 * - Native is responsible for detecting the end of a track
	 * - Native must pause the player, seek to position 0, and emit both:
	 *   - STATE_CHANGED: STOPPED
	 *   - TRACK_ENDED
	 */
	@objc private func playerItemDidPlayToEndTime(_ notification: Notification) {
		guard let _ = player?.currentItem else { return }

		if isInErrorState {
			log("Ignoring track end notification while in ERROR state")
			return
		}

		let info = getPlaybackInfo()

		isInErrorState = false
		lastEmittedState = ""
		shouldBePlaying = false

		player?.seek(to: .zero)
		stopTimer()

		updateNowPlayingInfo(time: 0, rate: 0)

		sendStateEvent(state: STATE_STOPPED, position: 0, duration: info.duration, track: currentTrack)

		if hasListeners {
			let payload: [String: Any] = [
				"position": info.duration,
				"duration": info.duration
			]
			sendEvent(type: EVENT_TYPE_TRACK_ENDED, track: currentTrack, payload: payload)
		}
	}

	override func observeValue(
		forKeyPath keyPath: String?,
		of object: Any?,
		change: [NSKeyValueChangeKey: Any]?,
		context: UnsafeMutableRawPointer?
	) {
		// Guard against state changes while in error state
		guard !isInErrorState else {
			log("Ignoring state change while in ERROR state")
			return
		}

		guard let keyPath = keyPath else { return }

		switch keyPath {
		case "status":
			if let item = object as? AVPlayerItem {
				switch item.status {
				case .readyToPlay:
					log("Player item ready to play")
					
					// If we're supposed to be playing, ensure we're actually playing
					if shouldBePlaying {
						player?.play()
						// Force a state update to PLAYING since we're ready
						sendPlayingStateEvent()
						startProgressTimer()
					}
					
					if let pendingStartTimeMs = pendingStartTimeMs {
						performSeek(to: pendingStartTimeMs, isAbsolute: true)
						self.pendingStartTimeMs = nil
					}
				case .failed:
					if let error = item.error {
						onError("Player item failed: \(error.localizedDescription)")
					} else {
						onError("Player item failed with unknown error")
					}
				case .unknown:
					break
				@unknown default:
					break
				}
			}
		case "playbackBufferEmpty":
			log("Playback buffer is empty, may need to wait for buffering")
			if shouldBePlaying && hasListeners {
				let info = getPlaybackInfo()
				sendStateEvent(state: STATE_LOADING, position: info.position, duration: info.duration, track: info.track)
			}
			
		case "playbackLikelyToKeepUp":
			log("Playback likely to keep up, can start/resume playback")
			if let item = object as? AVPlayerItem, item.isPlaybackLikelyToKeepUp && shouldBePlaying {
				// If we're supposed to be playing and buffering is good, ensure we're playing
				player?.play()
				sendPlayingStateEvent()
				startProgressTimer()
			}
			
		case "playbackBufferFull":
			log("Playback buffer is full")
			if shouldBePlaying {
				// Buffer is full, make sure we're playing
				player?.play()
				sendPlayingStateEvent()
				startProgressTimer()
			}
			
		case "rate":
			if let newRate = change?[.newKey] as? Float {
				if newRate == 0 {
					if shouldBePlaying && hasListeners {
						// Only show loading if we're supposed to be playing but rate dropped to 0
						// This could be due to buffering
						let info = getPlaybackInfo()
						
						// Check if the buffer is empty before showing loading state
						if let currentItem = player?.currentItem, currentItem.isPlaybackBufferEmpty {
							sendStateEvent(state: STATE_LOADING, position: info.position, duration: info.duration, track: info.track)
						}
						stopTimer()
					}
				} else {
					if shouldBePlaying && hasListeners {
						// Use sendPlayingStateEvent to ensure lastEmittedState is updated
						sendPlayingStateEvent()
						startProgressTimer()
					}
				}
			}
		default:
			super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
		}
	}

	////////////////////////////////////////////////////////////
	// MARK: - Private Helpers & Error Handling
	////////////////////////////////////////////////////////////

	private func getPlaybackInfo() -> (position: Int, duration: Int, track: NSDictionary?) {
		guard let player = player, let currentItem = player.currentItem else {
			return (0, 0, currentTrack)
		}
		let currentTimeSec = player.currentTime().seconds
		let durationSec = currentItem.duration.seconds
		let validCurrentTimeSec = (currentTimeSec.isNaN || currentTimeSec.isInfinite) ? 0 : currentTimeSec
		let validDurationSec = (durationSec.isNaN || durationSec.isInfinite) ? 0 : durationSec

		// Calculate position and duration in milliseconds
		let positionMs = Int(round(validCurrentTimeSec * 1000))
		let durationMs = Int(round(validDurationSec * 1000))

		// Sanitize negative values
		let sanitizedPositionMs = positionMs < 0 ? 0 : positionMs
		let sanitizedDurationMs = durationMs < 0 ? 0 : durationMs

		return (position: sanitizedPositionMs, duration: sanitizedDurationMs, track: currentTrack)
	}

	private func sendStateEvent(state: String, position: Int? = nil, duration: Int? = nil, track: NSDictionary? = nil) {
		guard hasListeners else { return }

		// When in error state, only allow ERROR or IDLE states to be emitted
		// IDLE is allowed because clear() should reset the player regardless of previous state
		if isInErrorState && state != STATE_ERROR && state != STATE_IDLE {
			log("Ignoring \(state) state after ERROR")
			return
		}

		// Filter out duplicate state emissions
		// This prevents rapid-fire transitions of the same state being emitted repeatedly
		if state == lastEmittedState {
			log("Ignoring duplicate \(state) state emission")
			return
		}

		// Use provided values or get from getPlaybackInfo() which already sanitizes values
		let info = position == nil || duration == nil ? getPlaybackInfo() : (position: position!, duration: duration!, track: track)

		let payload: [String: Any] = [
			"state": state,
			"position": info.position,
			"duration": info.duration
		]
		sendEvent(type: EVENT_TYPE_STATE_CHANGED, track: info.track ?? track, payload: payload)

		// Track the last emitted state
		lastEmittedState = state
	}

	private func sendStoppedStateEvent() {
		sendStateEvent(state: STATE_STOPPED, position: 0, duration: 0, track: currentTrack)
	}

	private func sendPlayingStateEvent() {
		sendStateEvent(state: STATE_PLAYING, track: currentTrack)
	}

	private func sendPausedStateEvent() {
		sendStateEvent(state: STATE_PAUSED, track: currentTrack)
	}

	/// Stops playback without emitting a state change event
	/// Used for error handling to avoid emitting STOPPED after ERROR
	private func stopPlaybackWithoutStateChange() {
		// Use the cleanup method with emitStateChange set to false
		cleanup(emitStateChange: false)
	}

	/// Updates Now Playing Info with specified parameters, preserving existing values
	private func updateNowPlayingInfo(time: Double? = nil, rate: Float? = nil, duration: Double? = nil, track: NSDictionary? = nil) {
		var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()

		// Update time if provided
		if let time = time {
			nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
		}

		// Update rate if provided, otherwise use current player rate
		nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate ?? player?.rate ?? 0

		// Update duration if provided, otherwise try to get from current item
		if let duration = duration {
			nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = duration
		} else if let currentItem = player?.currentItem {
			let itemDuration = currentItem.duration.seconds
			if !itemDuration.isNaN && !itemDuration.isInfinite {
				nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = itemDuration
			}
		}

		// Ensure we have the basic track info from either provided track or current track
		let trackInfo = track ?? currentTrack
		if let trackInfo = trackInfo {
			if nowPlayingInfo[MPMediaItemPropertyTitle] == nil, let title = trackInfo["title"] as? String {
				nowPlayingInfo[MPMediaItemPropertyTitle] = title
			}
			if nowPlayingInfo[MPMediaItemPropertyArtist] == nil, let artist = trackInfo["artist"] as? String {
				nowPlayingInfo[MPMediaItemPropertyArtist] = artist
			}
			if nowPlayingInfo[MPMediaItemPropertyAlbumTitle] == nil, let album = trackInfo["album"] as? String {
				nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
			}
		}

		// Always set live stream indicator for radio streams
		nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true

		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
	}

	private func updateNowPlayingInfoWithCurrentTime(_ time: Double) {
		updateNowPlayingInfo(time: time)
	}

	/**
	 * Emits a PLAYBACK_ERROR event without transitioning to the ERROR state.
	 * Use this for non-critical errors that don't require player teardown.
	 *
	 * According to the contract in logic.md:
	 * - PLAYBACK_ERROR and ERROR state are separate and must not be conflated
	 * - PLAYBACK_ERROR can be emitted with or without a corresponding state change
	 * - Useful for soft errors (e.g., image fetch failed, headers issue, non-fatal network retry)
	 */
	func emitPlaybackError(_ errorMessage: String, code: Int = 900) {
		if hasListeners {
			let errorPayload: [String: Any] = [
				"error": errorMessage,
				"errorCode": code
			]
			sendEvent(type: EVENT_TYPE_PLAYBACK_ERROR, track: currentTrack, payload: errorPayload)
		}
	}

	/**
	 * Handles critical errors according to the contract in logic.md:
	 * - onError() should transition to ERROR state
	 * - onError() should emit STATE_CHANGED: ERROR and PLAYBACK_ERROR
	 * - onError() should clear the player state just like clear()
	 *
	 * This method is for unrecoverable player failures that require player teardown.
	 * For non-critical errors that don't require state transition, use emitPlaybackError() instead.
	 */
	func onError(_ errorMessage: String) {
		// If we're already in an error state, just log and return
		if isInErrorState {
			log("Already in error state, ignoring additional error: \(errorMessage)")
			return
		}

		if hasListeners {
			// First, emit PLAYBACK_ERROR event with error details
			let errorPayload: [String: Any] = [
				"error": errorMessage,
				"errorCode": GENERIC_ERROR_CODE
			]
			sendEvent(type: EVENT_TYPE_PLAYBACK_ERROR, track: currentTrack, payload: errorPayload)
		}

		// Then use the shared resetInternal function to:
		// 1. Clear the player state (like clear())
		// 2. Emit STATE_CHANGED: ERROR
		resetInternal(STATE_ERROR)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Remote Control Commands & Magic Tap Support
	////////////////////////////////////////////////////////////

	private func setupRemoteTransportControls() {
		let commandCenter = MPRemoteCommandCenter.shared()
		
		// Clear existing commands first to avoid duplicates
		commandCenter.playCommand.removeTarget(nil)
		commandCenter.pauseCommand.removeTarget(nil)
		commandCenter.stopCommand.removeTarget(nil)
		commandCenter.togglePlayPauseCommand.removeTarget(nil)
		commandCenter.changePlaybackPositionCommand.removeTarget(nil)
		commandCenter.skipForwardCommand.removeTarget(nil)
		commandCenter.skipBackwardCommand.removeTarget(nil)
		commandCenter.nextTrackCommand.removeTarget(nil)
		commandCenter.previousTrackCommand.removeTarget(nil)
		
		// Add play command
		commandCenter.playCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			self.log("🟢 Remote command: PLAY (from lock screen/control center)")
			
			// Can always resume if we have a track, even from stopped state
			if self.currentTrack != nil {
				self.resume()
				return .success
			} else {
				self.log("Remote play failed: no track to play")
				return .commandFailed
			}
		}
		
		// Add pause command
		commandCenter.pauseCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			self.log("🔴 Remote command: PAUSE (from lock screen/control center)")
			self.pause()
			return .success
		}
		
		// Add stop command
		commandCenter.stopCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			self.log("Remote command: stop")
			self.stop()
			return .success
		}
		
		// Add toggle play/pause command
		commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
			guard let self = self else { return .commandFailed }
			self.log("🔄 Remote command: TOGGLE PLAY/PAUSE (from lock screen/control center)")
			
			// Handle stopped state (no player) - can resume if we have a track
			if self.player == nil {
				if self.currentTrack != nil {
					self.log("Remote toggle: resuming from stopped state")
					self.resume()
					return .success
				} else {
					self.log("Remote toggle failed: no track to resume")
					return .commandFailed
				}
			}
			
			// Handle normal play/pause toggle
			guard let player = self.player, let _ = player.currentItem else {
				self.log("Remote toggle failed: no player or item")
				return .commandFailed
			}
			
			if player.rate == 0 || !self.shouldBePlaying {
				self.log("🔄 Toggle -> RESUME")
				self.resume()
			} else {
				self.log("🔄 Toggle -> PAUSE")
				self.pause()
			}
			return .success
		}
		
		// Disable seeking commands for live streams
		commandCenter.changePlaybackPositionCommand.isEnabled = false
		commandCenter.skipForwardCommand.isEnabled = false
		commandCenter.skipBackwardCommand.isEnabled = false
		
		// Disable next/previous track commands
		commandCenter.nextTrackCommand.isEnabled = false
		commandCenter.previousTrackCommand.isEnabled = false
		
		// CRITICAL: Register for remote control events to receive background interruption notifications
		// This is required for timer interruptions to work properly when app is backgrounded
		UIApplication.shared.beginReceivingRemoteControlEvents()
		
		isRemoteCommandCenterSetup = true
	}

	private func removeRemoteTransportControls() {
		let commandCenter = MPRemoteCommandCenter.shared()
		commandCenter.playCommand.removeTarget(nil)
		commandCenter.pauseCommand.removeTarget(nil)
		commandCenter.togglePlayPauseCommand.removeTarget(nil) // Magic Tap cleanup
		commandCenter.nextTrackCommand.removeTarget(nil)
		commandCenter.previousTrackCommand.removeTarget(nil)
		commandCenter.changePlaybackPositionCommand.removeTarget(nil)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Ambient Audio Methods
	////////////////////////////////////////////////////////////

	/**
	 * Play an ambient audio track
	 * This is a completely isolated system from the main audio player
	 */
	@objc(ambientPlay:)
	func ambientPlay(options: NSDictionary) {
		// Get the URL from options
		guard let urlString = options["url"] as? String, let url = URL(string: urlString) else {
			onAmbientError("Invalid URL provided to ambientPlay()")
			return
		}

		// Get loop option, default to true if not provided
		settingLoopAmbient = options["loop"] as? Bool ?? true

		log("Ambient Play", urlString, "loop:", settingLoopAmbient)

		// Stop any existing ambient playback
		ambientStop()

		// Create a new player item
		ambientPlayerItem = AVPlayerItem(url: url)

		// Create a new player
		ambientPlayer = AVPlayer(playerItem: ambientPlayerItem)
		ambientPlayer?.volume = activeVolumeAmbient

		// Add observer for track completion
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(ambientPlayerItemDidPlayToEndTime(_:)),
			name: .AVPlayerItemDidPlayToEndTime,
			object: ambientPlayerItem
		)

		// Start playback immediately
		ambientPlayer?.play()
	}

	/**
	 * Stop ambient audio playback
	 */
	@objc(ambientStop)
	func ambientStop() {
		log("Ambient Stop")

		// Remove observer for track completion
		if let item = ambientPlayerItem {
			NotificationCenter.default.removeObserver(
				self,
				name: .AVPlayerItemDidPlayToEndTime,
				object: item
			)
		}

		// Stop and release the player
		ambientPlayer?.pause()
		ambientPlayer = nil
		ambientPlayerItem = nil
	}

	/**
	 * Set the volume of ambient audio playback
	 */
	@objc(ambientSetVolume:)
	func ambientSetVolume(volume: Double) {
		activeVolumeAmbient = Float(volume)
		log("Ambient Set Volume", activeVolumeAmbient)

		// Apply volume to player if it exists
		ambientPlayer?.volume = activeVolumeAmbient
	}

	/**
	 * Pause ambient audio playback
	 * No-op if already paused or not playing
	 */
	@objc(ambientPause)
	func ambientPause() {
		log("Ambient Pause")

		// Pause the player if it exists
		ambientPlayer?.pause()
	}

	/**
	 * Resume ambient audio playback
	 * No-op if already playing or no active track
	 */
	@objc(ambientResume)
	func ambientResume() {
		log("Ambient Resume")

		// Resume the player if it exists
		ambientPlayer?.play()
	}

	/**
	 * Seek to position in ambient audio track
	 * Silently ignore if not supported or no active track
	 *
	 * @param positionMs Position in milliseconds
	 */
	@objc(ambientSeekTo:)
	func ambientSeekTo(positionMs: Double) {
		log("Ambient Seek To", positionMs)

		// Convert milliseconds to seconds for CMTime
		let seconds = positionMs / 1000.0

		// Create a CMTime value for the seek position
		let time = CMTime(seconds: seconds, preferredTimescale: 1000)

		// Seek to the specified position
		ambientPlayer?.seek(to: time)
	}

	/**
	 * Handle ambient track completion
	 */
	@objc private func ambientPlayerItemDidPlayToEndTime(_ notification: Notification) {
		log("Ambient Track Ended")

		if settingLoopAmbient {
			// If looping is enabled, seek to beginning and continue playback
			ambientPlayer?.seek(to: CMTime.zero)
			ambientPlayer?.play()
		} else {
			// If looping is disabled, stop playback and emit event
			ambientStop()
			sendAmbientEvent(type: EVENT_TYPE_AMBIENT_TRACK_ENDED, payload: nil)
		}
	}

	/**
	 * Emit an ambient error event
	 */
	private func onAmbientError(_ message: String) {
		log("Ambient Error:", message)

		// Stop playback
		ambientStop()

		// Emit error event
		let payload: [String: Any] = ["error": message]
		sendAmbientEvent(type: EVENT_TYPE_AMBIENT_ERROR, payload: payload)
	}

	/**
	 * Send an ambient event to JavaScript
	 */
	private func sendAmbientEvent(type: String, payload: [String: Any]?) {
		guard hasListeners else { return }

		var body: [String: Any] = ["type": type]

		if let payload = payload {
			body["payload"] = payload
		}

		sendEvent(withName: AMBIENT_EVENT_NAME, body: body)
	}

	////////////////////////////////////////////////////////////
	// MARK: - Remote Control Commands & Magic Tap Support
	////////////////////////////////////////////////////////////

	private func updateNextPrevControlsState() {
		let commandCenter = MPRemoteCommandCenter.shared()
		
		// Always disable next/previous for radio streams
		commandCenter.nextTrackCommand.isEnabled = false
		commandCenter.previousTrackCommand.isEnabled = false
		
		// Always disable seeking for radio streams
		commandCenter.seekForwardCommand.isEnabled = false
		commandCenter.seekBackwardCommand.isEnabled = false
		commandCenter.skipForwardCommand.isEnabled = false
		commandCenter.skipBackwardCommand.isEnabled = false
		commandCenter.changePlaybackPositionCommand.isEnabled = false
	}

	private func configureAudioSession() throws {
		// Configure audio session for playback
		let session = AVAudioSession.sharedInstance()
		
		// Set playback category with options for better lock screen control support
		// Use .allowAirPlay and .allowBluetoothA2DP for better device compatibility
		try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
		
		// Set audio session active synchronously to ensure it's ready before playback starts
		try session.setActive(true, options: .notifyOthersOnDeactivation)
		
		// Interruption observer is already set up in init()
		log("Audio session configured for playback with enhanced options")
	}

	private func updateNowPlayingInfo(time: Double, rate: Float) {
		guard let track = currentTrack else { return }
		
		// Preserve existing now playing info to avoid clearing artwork
		var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
		
		// Set title, artist, and album only if not already set
		if let title = track["title"] as? String {
			nowPlayingInfo[MPMediaItemPropertyTitle] = title
		}
		
		if let artist = track["artist"] as? String {
			nowPlayingInfo[MPMediaItemPropertyArtist] = artist
		}
		
		if let album = track["album"] as? String {
			nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = album
		}
		
		// Always set as live stream for radio
		nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
		
		// Set playback rate
		nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
		
		// Set elapsed time
		nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time
		
		// Update the now playing info (this preserves artwork if already loaded)
		MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
		
		// Load and set artwork if available and not already loaded
		if let artworkUrlString = track["artwork"] as? String, 
		   let artworkUrl = URL(string: artworkUrlString),
		   nowPlayingInfo[MPMediaItemPropertyArtwork] == nil {
			loadArtwork(from: artworkUrl) { [weak self] image in
				guard let self = self, let image = image else { return }
				
				var updatedInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
				updatedInfo[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
				MPNowPlayingInfoCenter.default().nowPlayingInfo = updatedInfo
			}
		}
	}

	private func createPlayerItem(with url: URL, headers: NSDictionary?) -> AVPlayerItem {
		// Create player item with custom headers if provided
		if let headers = headers, let audioHeaders = headers["audio"] as? NSDictionary {
			// Convert and validate headers to Swift dictionary
			var headerFields = [String: String]()
			for (key, value) in audioHeaders {
				// Validate header key and value for security
				if let headerField = key as? String, 
				   let headerValue = value as? String,
				   headerField.count < 256, // Reasonable limit
				   headerValue.count < 1024, // Reasonable limit
				   !headerField.isEmpty,
				   headerField.rangeOfCharacter(from: CharacterSet.controlCharacters) == nil,
				   headerValue.rangeOfCharacter(from: CharacterSet.controlCharacters) == nil {
					headerFields[headerField] = headerValue
				}
			}
			
			// Only use headers if we have valid ones
			if !headerFields.isEmpty {
				let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headerFields])
				return AVPlayerItem(asset: asset)
			}
		}
		
		// No headers or invalid headers, use simple URL initialization
		return AVPlayerItem(url: url)
	}

	private func setupPlayerItemObservers(_ playerItem: AVPlayerItem) {
		// Add observer for status changes
		playerItem.addObserver(self, forKeyPath: "status", options: [.new, .old], context: nil)
		isStatusObserverAdded = true
		
		// Add rate observer to the player
		player?.addObserver(self, forKeyPath: "rate", options: [.new, .old], context: nil)
		isRateObserverAdded = true
		
		// Add observers for buffering progress
		playerItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
		playerItem.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: nil)
		playerItem.addObserver(self, forKeyPath: "playbackBufferFull", options: [.new], context: nil)
		
		// Add notification observer for track completion
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(playerItemDidPlayToEndTime(_:)),
			name: .AVPlayerItemDidPlayToEndTime,
			object: playerItem
		)
	}

	private func loadArtwork(from url: URL, completion: @escaping (UIImage?) -> Void) {
		// Use URLSession for secure, asynchronous network requests per Apple guidelines
		let request = URLRequest(url: url, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 30.0)
		
		URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
			guard let self = self else { return }
			
			// Validate response
			if let error = error {
				self.log("Failed to load artwork: \(error.localizedDescription)")
				DispatchQueue.main.async { completion(nil) }
				return
			}
			
			// Validate HTTP response status
			if let httpResponse = response as? HTTPURLResponse,
			   !(200...299).contains(httpResponse.statusCode) {
				self.log("Failed to load artwork: HTTP \(httpResponse.statusCode)")
				DispatchQueue.main.async { completion(nil) }
				return
			}
			
			// Validate and process image data
			guard let data = data,
				  data.count > 0,
				  data.count < 10_000_000, // Limit to 10MB for security
				  let image = UIImage(data: data) else {
				self.log("Invalid or oversized artwork data")
				DispatchQueue.main.async { completion(nil) }
				return
			}
			
			DispatchQueue.main.async {
				completion(image)
			}
		}.resume()
	}
}