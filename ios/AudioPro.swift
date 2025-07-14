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
	
	// Audio interruption event types - sent to React Native for handling
	private let EVENT_TYPE_AUDIO_INTERRUPTION_BEGAN = "AUDIO_INTERRUPTION_BEGAN"
	private let EVENT_TYPE_AUDIO_INTERRUPTION_ENDED = "AUDIO_INTERRUPTION_ENDED"

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
	private var isExternalPlaybackObserverAdded = false

	private var currentPlaybackSpeed: Float = 1.0
	private var currentTrack: NSDictionary?
	private var currentArtworkImage: UIImage?

	private var settingDebug: Bool = false
	private var settingDebugIncludeProgress: Bool = false
	private var settingProgressInterval: TimeInterval = 1.0
	private var settingShowNextPrevControls = true
	private var settingLoopAmbient: Bool = true

	private var activeVolume: Float = 1.0
	private var activeVolumeAmbient: Float = 1.0

	private var isInErrorState: Bool = false
	private var lastEmittedState: String = ""
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
		
		// Test that NotificationCenter is working at all
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(testNotificationReceived(_:)),
			name: UIApplication.didBecomeActiveNotification,
			object: nil
		)
		
		// Automatically check background audio configuration on initialization (SwiftAudioEx pattern)
		checkBackgroundAudioConfiguration()
		
		log("AudioPro module initialized with interruption observer and SwiftAudioEx patterns")
	}
	
	@objc private func testNotificationReceived(_ notification: Notification) {
		print("🚨 [AudioPro] TEST: App became active - NotificationCenter is working!")
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
		
		// Check if app has background audio capabilities
		if let backgroundModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] {
			let hasAudioBackground = backgroundModes.contains("audio")
			print("🚨 [AudioPro] Background modes: \(backgroundModes), has audio: \(hasAudioBackground)")
		} else {
			print("🚨 [AudioPro] WARNING: No UIBackgroundModes found in Info.plist!")
		}
		
		// Check current audio session state
		let session = AVAudioSession.sharedInstance()
		print("🚨 [AudioPro] Current audio session category: \(session.category.rawValue)")
		print("🚨 [AudioPro] Current audio session is active: \(session.isOtherAudioPlaying)")
		print("🚨 [AudioPro] Current audio session mode: \(session.mode.rawValue)")
		
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
		
		// Also register for route change notifications to see if those work
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleRouteChange(_:)),
			name: AVAudioSession.routeChangeNotification,
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
		print("🚨 [AudioPro] INTERRUPTION DETECTED!")
		guard let userInfo = notification.userInfo,
			  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
			  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
			print("🚨 [AudioPro] Interruption: Invalid notification data")
			return
		}

		print("🚨 [AudioPro] Interruption type: \(type.rawValue)")
		
		switch type {
		case .began:
			print("🚨 [AudioPro] Interruption BEGAN")
			log("Audio session interruption began - pausing playback")
			
			// Save current state
			let wasPlaying = shouldBePlaying
			
			// Pause playback but don't change shouldBePlaying flag
			// This allows us to resume properly when interruption ends
			player?.pause()
			stopTimer()
			sendPausedStateEvent()
			
			// Log the state for debugging
			print("🚨 [AudioPro] Interruption began - wasPlaying: \(wasPlaying), shouldBePlaying: \(shouldBePlaying)")
			
		case .ended:
			print("🚨 [AudioPro] Interruption ENDED")
			guard let userInfo = notification.userInfo,
				  let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
				print("🚨 [AudioPro] Interruption ended: No options provided")
				return
			}
			
			let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
			print("🚨 [AudioPro] Interruption options: \(options.rawValue)")
			
			if options.contains(.shouldResume) {
				print("🚨 [AudioPro] System suggests resuming playback")
				log("Audio session interruption ended - attempting to resume playback")
				
				// Try to reactivate audio session and resume if we were playing
				if shouldBePlaying {
					DispatchQueue.global(qos: .userInitiated).async { [weak self] in
						guard let self = self else { return }
						
						do {
							let session = AVAudioSession.sharedInstance()
							try session.setActive(true, options: .notifyOthersOnDeactivation)
							print("🚨 [AudioPro] Audio session reactivated successfully")
							
							DispatchQueue.main.async {
								// Resume playback
								self.player?.play()
								self.startProgressTimer()
								self.sendPlayingStateEvent()
								
								print("🚨 [AudioPro] Playback resumed after interruption")
							}
						} catch {
							print("🚨 [AudioPro] Failed to reactivate audio session: \(error.localizedDescription)")
							DispatchQueue.main.async {
								self.log("Failed to resume after interruption: \(error.localizedDescription)")
								// Try resuming anyway
								self.player?.play()
								self.startProgressTimer()
								self.sendPlayingStateEvent()
							}
						}
					}
				} else {
					print("🚨 [AudioPro] Not resuming - shouldBePlaying is false")
				}
			} else {
				print("🚨 [AudioPro] System does not suggest resuming")
				log("Audio session interruption ended - manual resume required")
			}
			
		@unknown default:
			print("🚨 [AudioPro] Unknown interruption type: \(type.rawValue)")
			break
		}
	}
	
	/// Reactivates the audio session after an interruption
	/// This is called from React Native when it decides to resume playback
	@objc(reactivateAudioSession)
	func reactivateAudioSession() {
		do {
			let session = AVAudioSession.sharedInstance()
			
			// Check if session is already active
			if !session.isOtherAudioPlaying {
				try session.setActive(true, options: .notifyOthersOnDeactivation)
				log("Audio session reactivated successfully from React Native")
			} else {
				log("Other audio is playing, keeping session active")
			}
		} catch {
			log("Failed to reactivate audio session: \(error.localizedDescription)")
			emitPlaybackError("Unable to reactivate audio session")
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
	
	@objc private func handleRouteChange(_ notification: Notification) {
		print("🚨 [AudioPro] ROUTE CHANGE DETECTED!")
		guard let userInfo = notification.userInfo,
			  let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
			  let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
			print("🚨 [AudioPro] Route change: Invalid notification data")
			return
		}
		
		print("🚨 [AudioPro] Route change reason: \(reason.rawValue)")
		switch reason {
		case .newDeviceAvailable:
			print("🚨 [AudioPro] New audio device available")
		case .oldDeviceUnavailable:
			print("🚨 [AudioPro] Audio device disconnected")
		case .categoryChange:
			print("🚨 [AudioPro] Audio category changed")
		case .override:
			print("🚨 [AudioPro] Audio route overridden")
		case .wakeFromSleep:
			print("🚨 [AudioPro] Device woke from sleep")
		case .noSuitableRouteForCategory:
			print("🚨 [AudioPro] No suitable route for category")
		case .routeConfigurationChange:
			print("🚨 [AudioPro] Route configuration changed")
		@unknown default:
			print("🚨 [AudioPro] Unknown route change reason")
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
			if isExternalPlaybackObserverAdded {
				player.removeObserver(self, forKeyPath: "externalPlaybackActive")
				isExternalPlaybackObserverAdded = false
			}
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
		// Ensure all setup is on the main thread to prevent race conditions.
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }

			// Reset error state when playing a new track
			self.isInErrorState = false
			// Reset last emitted state when playing a new track
			self.lastEmittedState = ""
			// Reset explicitly stopped flag when playing
			self.isExplicitlyStopped = false
			self.currentTrack = track

			// Clear previous artwork but don't wait for new artwork
			self.currentArtworkImage = nil
			
			// IMMEDIATE: Set basic metadata first (never block for artwork)
			self.setBasicNowPlayingMetadata()
			
			// ASYNC: Load artwork in background without blocking
			if let artworkPath = track["artwork"] as? String {
				self.log("Loading artwork asynchronously: \(artworkPath)")
				self.loadArtworkAsync(from: artworkPath)
			} else {
				// Set fallback artwork for AirPlay compatibility
				self.currentArtworkImage = self.createSamsungTVFallbackArtwork()
				self.updateArtworkInNowPlayingInfo()
			}
			
			// Continue with player setup immediately
			self.continuePlayerSetup(track: track, options: options)
		}
	}

	/// Enhanced artwork loading method specifically designed for React Native assets and Samsung TV compatibility
	/// This method attempts multiple loading strategies and always ensures we have a valid image before completion
	private func loadReactNativeArtwork(from artworkPath: String, completion: @escaping () -> Void) {
		log("[Artwork] Starting artwork loading from: \(artworkPath)")
		
		// Strategy 1: Try to load as React Native bundle resource first (most reliable)
		if let bundleImage = loadFromReactNativeBundleSync(artworkPath: artworkPath) {
			self.currentArtworkImage = self.prepareImageForSamsungTV(bundleImage)
			log("[Artwork] ✅ Successfully loaded from React Native bundle")
			completion()
			return
		}
		
		// Strategy 2: Handle different URI schemes
		if let artworkUrl = URL(string: artworkPath) {
			log("[Artwork] Trying URL-based loading. Scheme: \(artworkUrl.scheme ?? "nil")")
			
			// Handle HTTP/HTTPS URLs (remote images)
			if artworkUrl.scheme == "http" || artworkUrl.scheme == "https" {
				loadRemoteArtworkForSamsungTV(from: artworkUrl, completion: completion)
				return
			}
			
			// Handle file:// URLs 
			if artworkUrl.isFileURL || artworkUrl.scheme == "file" {
				loadLocalArtworkForSamsungTV(from: artworkUrl, completion: completion)
				return
			}
		}
		
		// Strategy 3: Fallback - try to extract filename and load from bundle
		let fileName = URL(string: artworkPath)?.lastPathComponent ?? artworkPath
		if let bundleImage = loadFromAppBundleSync(fileName: fileName) {
			self.currentArtworkImage = self.prepareImageForSamsungTV(bundleImage)
			log("[Artwork] ✅ Successfully loaded from app bundle as fallback")
			completion()
			return
		}
		
		// Strategy 4: If all else fails, create a high-quality fallback image
		// Samsung TVs REQUIRE artwork to prevent loading spinner
		log("[Artwork] ⚠️ All loading strategies failed, creating Samsung TV compatible fallback")
		self.currentArtworkImage = self.createSamsungTVFallbackArtwork()
		completion()
	}
	
	/// Synchronously loads artwork from React Native bundle with multiple filename strategies
	private func loadFromReactNativeBundleSync(artworkPath: String) -> UIImage? {
		// Extract potential filename from various React Native asset URI formats
		var fileName = ""
		
		// Handle React Native asset URLs
		if artworkPath.contains("RCTAssetURLProvider") || artworkPath.contains("assets-library") || artworkPath.contains("ph://") {
			// Try to extract filename from React Native asset path
			if let url = URL(string: artworkPath) {
				fileName = url.lastPathComponent
			}
		} else if let url = URL(string: artworkPath) {
			fileName = url.lastPathComponent
		} else {
			fileName = artworkPath
		}
		
		// Clean up filename
		if fileName.contains("?") {
			fileName = String(fileName.split(separator: "?")[0])
		}
		if fileName.contains("#") {
			fileName = String(fileName.split(separator: "#")[0])
		}
		
		log("[Artwork] Attempting bundle load with filename: \(fileName)")
		return loadFromAppBundleSync(fileName: fileName)
	}
	
	/// Synchronously loads artwork from app bundle with comprehensive filename matching
	private func loadFromAppBundleSync(fileName: String) -> UIImage? {
		// Try exact filename first
		if let image = UIImage(named: fileName) {
			log("[Artwork] Found exact match: \(fileName)")
			return image
		}
		
		// Try without file extension
		let nameWithoutExtension = fileName.components(separatedBy: ".").first ?? fileName
		if let image = UIImage(named: nameWithoutExtension) {
			log("[Artwork] Found without extension: \(nameWithoutExtension)")
			return image
		}
		
		// Try with common image formats
		let extensions = ["png", "jpg", "jpeg", "PNG", "JPG", "JPEG"]
		for ext in extensions {
			let fileNameWithExt = nameWithoutExtension + "." + ext
			if let image = UIImage(named: fileNameWithExt) {
				log("[Artwork] Found with extension: \(fileNameWithExt)")
				return image
			}
		}
		
		log("[Artwork] No bundle image found for: \(fileName)")
		return nil
	}

	/// Load artwork from local file path with Samsung TV optimization
	private func loadLocalArtworkForSamsungTV(from url: URL, completion: @escaping () -> Void) {
		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }
			
			do {
				let imageData = try Data(contentsOf: url)
				if let loadedImage = UIImage(data: imageData) {
					DispatchQueue.main.async {
						self.currentArtworkImage = self.prepareImageForSamsungTV(loadedImage)
						self.log("[Artwork] ✅ Successfully loaded local file: \(url.lastPathComponent)")
						completion()
					}
				} else {
					DispatchQueue.main.async {
						self.log("[Artwork] ❌ Failed to create UIImage from local file data")
						self.currentArtworkImage = self.createSamsungTVFallbackArtwork()
						completion()
					}
				}
			} catch {
				DispatchQueue.main.async {
					self.log("[Artwork] ❌ Failed to load local file: \(error.localizedDescription)")
					self.currentArtworkImage = self.createSamsungTVFallbackArtwork()
					completion()
				}
			}
		}
	}

	/// Load artwork from remote URL with Samsung TV optimization and timeout
	private func loadRemoteArtworkForSamsungTV(from url: URL, completion: @escaping () -> Void) {
		log("[Artwork] Loading remote artwork from: \(url)")
		
		// Create a URLSession with timeout for faster fallback
		let config = URLSessionConfiguration.default
		config.timeoutIntervalForRequest = 10.0
		config.timeoutIntervalForResource = 15.0
		let session = URLSession(configuration: config)
		
		session.dataTask(with: url) { [weak self] data, response, error in
			guard let self = self else { return }
			
			DispatchQueue.main.async {
				if let error = error {
					self.log("[Artwork] ❌ Remote artwork failed: \(error.localizedDescription)")
					self.currentArtworkImage = self.createSamsungTVFallbackArtwork()
				} else if let data = data, let image = UIImage(data: data) {
					self.currentArtworkImage = self.prepareImageForSamsungTV(image)
					self.log("[Artwork] ✅ Successfully loaded remote artwork")
				} else {
					self.log("[Artwork] ❌ Invalid remote artwork data")
					self.currentArtworkImage = self.createSamsungTVFallbackArtwork()
				}
				completion()
			}
		}.resume()
	}
	
	/// Prepares an image for optimal Samsung TV AirPlay compatibility
	/// Samsung TVs work best with exactly 600x600 pixel images
	private func prepareImageForSamsungTV(_ originalImage: UIImage) -> UIImage {
		let targetSize = CGSize(width: 600, height: 600)
		
		// If image is already exactly 600x600, return as-is for optimal performance
		if originalImage.size.width == 600 && originalImage.size.height == 600 {
			log("[Artwork] Image already optimized for Samsung TV (600x600)")
			return originalImage
		}
		
		log("[Artwork] Optimizing image for Samsung TV: \(originalImage.size) -> \(targetSize)")
		
		UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0) // Use scale 1.0 for consistency
		defer { UIGraphicsEndImageContext() }
		
		// Calculate aspect-fit dimensions
		let originalSize = originalImage.size
		let aspectRatio = originalSize.width / originalSize.height
		
		let drawSize: CGSize
		let drawRect: CGRect
		
		if aspectRatio > 1 {
			// Landscape - fit to width, center vertically
			drawSize = CGSize(width: targetSize.width, height: targetSize.width / aspectRatio)
			drawRect = CGRect(
				x: 0,
				y: (targetSize.height - drawSize.height) / 2,
				width: drawSize.width,
				height: drawSize.height
			)
		} else {
			// Portrait or square - fit to height, center horizontally
			drawSize = CGSize(width: targetSize.height * aspectRatio, height: targetSize.height)
			drawRect = CGRect(
				x: (targetSize.width - drawSize.width) / 2,
				y: 0,
				width: drawSize.width,
				height: drawSize.height
			)
		}
		
		// Draw with high quality
		originalImage.draw(in: drawRect)
		return UIGraphicsGetImageFromCurrentImageContext() ?? originalImage
	}
	
	/// Creates a high-quality fallback artwork specifically for Samsung TV compatibility
	/// Samsung TVs show a loading spinner when no artwork is present, so we must always provide something
	private func createSamsungTVFallbackArtwork() -> UIImage {
		let size = CGSize(width: 600, height: 600)
		
		UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
		defer { UIGraphicsEndImageContext() }
		
		// Create an attractive gradient background instead of plain gray
		let context = UIGraphicsGetCurrentContext()
		let colorSpace = CGColorSpaceCreateDeviceRGB()
		
		// Use music-themed colors
		let colors = [
			UIColor(red: 0.05, green: 0.05, blue: 0.15, alpha: 1.0).cgColor, // Dark navy
			UIColor(red: 0.15, green: 0.1, blue: 0.25, alpha: 1.0).cgColor,  // Purple
			UIColor(red: 0.2, green: 0.15, blue: 0.3, alpha: 1.0).cgColor    // Lighter purple
		]
		
		if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: nil) {
			context?.drawLinearGradient(
				gradient,
				start: CGPoint(x: 0, y: 0),
				end: CGPoint(x: size.width, y: size.height),
				options: []
			)
		}
		
		// Add a radio wave icon in the center
		let iconSize: CGFloat = 200
		let iconRect = CGRect(
			x: (size.width - iconSize) / 2,
			y: (size.height - iconSize) / 2,
			width: iconSize,
			height: iconSize
		)
		
		// Draw radio wave symbol
		UIColor.white.withAlphaComponent(0.2).setFill()
		let outerPath = UIBezierPath(ovalIn: iconRect)
		outerPath.fill()
		
		// Inner circle
		let innerSize: CGFloat = iconSize * 0.6
		let innerRect = CGRect(
			x: (size.width - innerSize) / 2,
			y: (size.height - innerSize) / 2,
			width: innerSize,
			height: innerSize
		)
		UIColor.white.withAlphaComponent(0.3).setFill()
		let innerPath = UIBezierPath(ovalIn: innerRect)
		innerPath.fill()
		
		// Center dot
		let dotSize: CGFloat = iconSize * 0.2
		let dotRect = CGRect(
			x: (size.width - dotSize) / 2,
			y: (size.height - dotSize) / 2,
			width: dotSize,
			height: dotSize
		)
		UIColor.white.withAlphaComponent(0.5).setFill()
		let dotPath = UIBezierPath(ovalIn: dotRect)
		dotPath.fill()
		
		let fallbackImage = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
		log("[Artwork] Created Samsung TV compatible fallback artwork")
		return fallbackImage
	}

	/// Continues player setup after artwork loading is complete.
	/// This ensures the player is always set up regardless of artwork loading success/failure.
	private func continuePlayerSetup(track: NSDictionary, options: NSDictionary) {
		self.settingDebug = options["debug"] as? Bool ?? false
		self.settingDebugIncludeProgress = options["debugIncludesProgress"] as? Bool ?? false
		let speed = Float(options["playbackSpeed"] as? Double ?? 1.0)
		let volume = Float(options["volume"] as? Double ?? 1.0)
		let autoPlay = options["autoPlay"] as? Bool ?? true
		
		// Get URL from track
		guard let urlString = track["url"] as? String, let url = URL(string: urlString) else {
			self.onError("Invalid URL provided")
			return
		}
		
		// Clean up previous player if it exists
		self.prepareForNewPlayback()
		
		// Send loading state immediately so UI can update
		if autoPlay {
			self.shouldBePlaying = true
			self.sendStateEvent(state: self.STATE_LOADING, position: 0, duration: 0, track: self.currentTrack)
		}
		
		// Configure audio session first to ensure proper setup
		do {
			try self.configureAudioSession()
		} catch {
			self.log("Failed to configure audio session: \(error.localizedDescription)")
			self.emitPlaybackError("Unable to configure audio playback")
			// Continue anyway, as playback might still work
		}
		
		// Create player item with URL
		let headers = options["headers"] as? NSDictionary
		let playerItem = self.createPlayerItem(with: url, headers: headers)
		
		// Set preferred forward buffer duration for better buffering
		playerItem.preferredForwardBufferDuration = 5.0

		// Create player with the item
		self.player = AVPlayer(playerItem: playerItem)
		self.player?.volume = volume
		self.player?.allowsExternalPlayback = true
		
		// Add observer for AirPlay (external playback) status changes
		self.player?.addObserver(self, forKeyPath: "externalPlaybackActive", options: [.new], context: nil)
		self.isExternalPlaybackObserverAdded = true
		
		// Set automatic buffering
		self.player?.automaticallyWaitsToMinimizeStalling = true
		
		// Always use normal playback speed for live streams
		self.player?.rate = 1.0
		self.currentPlaybackSpeed = 1.0
		
		// Setup observers for the player item
		self.setupPlayerItemObservers(playerItem)
		
		// Update the remote command center
		self.setupRemoteTransportControls()
		
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

	@objc(pause)
	func pause() {
		print("🚨 [AudioPro] PAUSE CALLED")
		log("[Pause] Called. player=\(player != nil), shouldBePlaying=\(shouldBePlaying), player?.rate=\(String(describing: player?.rate))")
		shouldBePlaying = false
		isExplicitlyStopped = false  // This is a pause, not a stop
		player?.pause()
		stopTimer()
		sendPausedStateEvent()
		updateNowPlayingPlaybackValues()
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
					self.updateNowPlayingPlaybackValues()
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

		// For a clean stop, explicitly clear the now playing info from the control center.
		MPNowPlayingInfoCenter.default().nowPlayingInfo = [:]
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
		currentArtworkImage = nil

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
			if isExternalPlaybackObserverAdded {
				player.removeObserver(self, forKeyPath: "externalPlaybackActive")
				isExternalPlaybackObserverAdded = false
			}
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
			currentArtworkImage = nil
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
				self.updateNowPlayingPlaybackValues()
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

		updateNowPlayingPlaybackValues()

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

		updateNowPlayingPlaybackValues()

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

					// Ensure Now Playing info is properly set when player is ready
					updateNowPlayingPlaybackValues()
					
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
				
				// Update Now Playing values when playback resumes
				updateNowPlayingPlaybackValues()
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
					
					// Update Now Playing values when paused
					updateNowPlayingPlaybackValues()
				} else {
					if shouldBePlaying && hasListeners {
						// Use sendPlayingStateEvent to ensure lastEmittedState is updated
						sendPlayingStateEvent()
						startProgressTimer()
					}
					
					// Update Now Playing values when playing
					updateNowPlayingPlaybackValues()
				}
			}
		case "externalPlaybackActive":
			if let player = object as? AVPlayer {
				if player.isExternalPlaybackActive {
					log("[AirPlay] 🎯 AirPlay/Samsung TV playback STARTED")
					
					// Simple refresh of Now Playing info for AirPlay
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
						self?.updateNowPlayingPlaybackValues()
					}
				} else {
					log("[AirPlay] 📺 AirPlay/Samsung TV playback ENDED - returning to local playback")
					
					// Simple refresh when returning from AirPlay
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
						self?.updateNowPlayingPlaybackValues()
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

	/// Sets the static metadata for the Now Playing info center.
	/// This must be called on the main thread.
	/// CRITICAL: Only call this AFTER artwork loading is complete to ensure Samsung TV compatibility
	private func setNowPlayingMetadata() {
		// Ensure we're on the main thread
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			
			log("[Samsung TV] Setting Now Playing metadata")
			
			// Create completely fresh metadata dictionary
			var nowPlayingInfo = [String: Any]()

			// Set basic metadata
			if let trackInfo = self.currentTrack {
				nowPlayingInfo[MPMediaItemPropertyTitle] = trackInfo["title"] as? String ?? "Live Radio"
				nowPlayingInfo[MPMediaItemPropertyArtist] = trackInfo["artist"] as? String ?? "Now Streaming"
			} else {
				nowPlayingInfo[MPMediaItemPropertyTitle] = "Live Radio"
				nowPlayingInfo[MPMediaItemPropertyArtist] = "Now Streaming"
			}
			
			// CRITICAL: Always set live stream flag for radio to prevent seeking controls
			nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
			
			// CRITICAL: Always ensure artwork is present - Samsung TV shows loading spinner without it
			// At this point, currentArtworkImage is guaranteed to be valid (either loaded or fallback)
			if let artworkImage = self.currentArtworkImage {
				self.log("[Samsung TV] Setting artwork - Image size: \(artworkImage.size)")
				self.setSamsungTVCompatibleArtwork(image: artworkImage, in: &nowPlayingInfo)
			} else {
				// This should never happen due to our fallback system, but just in case
				self.log("[Samsung TV] WARNING: No artwork available, creating emergency fallback")
				let emergencyFallback = self.createSamsungTVFallbackArtwork()
				self.setSamsungTVCompatibleArtwork(image: emergencyFallback, in: &nowPlayingInfo)
			}

			// Set initial playback state (will be updated by updateNowPlayingPlaybackValues)
			nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
			nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
			
			// Apply the metadata in one atomic operation
			MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
			self.log("[Samsung TV] ✅ Now Playing metadata set successfully with guaranteed artwork")
		}
	}
	
	/// Sets artwork in metadata with Samsung TV specific optimizations
	/// This method ensures the artwork callback NEVER returns nil, which is critical for Samsung TV compatibility
	private func setSamsungTVCompatibleArtwork(image: UIImage, in nowPlayingInfo: inout [String: Any]) {
		// Samsung TVs work best with exactly 600x600 bounds
		let samsungTVBounds = CGSize(width: 600, height: 600)
		
		// Create a strong reference to prevent deallocation during callback
		let stableImage = image
		
		// CRITICAL: Artwork callback must NEVER return nil for Samsung TV compatibility
		let artwork = MPMediaItemArtwork(boundsSize: samsungTVBounds) { requestedSize in
			self.log("[Samsung TV] Artwork callback - Requested: \(requestedSize), Providing: \(stableImage.size)")
			
			// Samsung TVs are very specific about size requirements
			// If they request exactly our bounds size, return the image as-is for best performance
			if abs(requestedSize.width - samsungTVBounds.width) < 1.0 && 
			   abs(requestedSize.height - samsungTVBounds.height) < 1.0 {
				self.log("[Samsung TV] ✅ Exact size match - returning optimized image")
				return stableImage
			}
			
			// For any other size request, safely resize but never return nil
			guard requestedSize.width > 0 && requestedSize.height > 0 else {
				self.log("[Samsung TV] ⚠️ Invalid size requested, returning stable image")
				return stableImage
			}
			
			// Attempt resize with fallback to original
			let resizedImage = self.safeResizeImage(stableImage, to: requestedSize) ?? stableImage
			self.log("[Samsung TV] ✅ Resized for request: \(requestedSize)")
			return resizedImage
		}
		
		nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
		log("[Samsung TV] ✅ Samsung TV compatible artwork callback configured")
	}
	
	/// Safely resizes an image with proper error handling and memory management
	private func safeResizeImage(_ image: UIImage, to size: CGSize) -> UIImage? {
		return autoreleasepool {
			UIGraphicsBeginImageContextWithOptions(size, false, 1.0) // Fixed scale for consistency
			defer { UIGraphicsEndImageContext() }
			
			image.draw(in: CGRect(origin: .zero, size: size))
			return UIGraphicsGetImageFromCurrentImageContext()
		}
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
		log("Error occurred: \(errorMessage)")
		
		// Set error state to prevent duplicate events
		isInErrorState = true
		
		// Stop playback without emitting another state change
		stopPlaybackWithoutStateChange()
		
		// Emit error state
		sendEvent(type: EVENT_TYPE_PLAYBACK_ERROR, track: currentTrack, payload: ["message": errorMessage])
		
		// For live streams, attempt automatic recovery after a short delay
		DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
			guard let self = self else { return }
			
			// Only attempt recovery if we still have a track and no new track has been loaded
			guard let track = self.currentTrack, self.isInErrorState else { return }
			
			self.log("Attempting automatic error recovery for live stream")
			
			// Reset error state
			self.isInErrorState = false
			self.lastEmittedState = ""
			
			// Restart the stream
			let options: NSDictionary = [
				"autoPlay": true,
				"debug": self.settingDebug
			]
			
			self.play(track: track, options: options)
		}
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
		print("🚨 [AudioPro] CONFIGURING AUDIO SESSION")
		
		// Configure audio session for playback
		let session = AVAudioSession.sharedInstance()
		
		// Log current state before configuration
		print("🚨 [AudioPro] Before config - Category: \(session.category.rawValue), Mode: \(session.mode.rawValue), Active: \(session.isOtherAudioPlaying)")
		
		// Set playback category with options for better lock screen control support
		// Use .allowAirPlay and .allowBluetoothA2DP for better device compatibility
		try session.setCategory(.playback, mode: .default, options: [.allowAirPlay, .allowBluetoothA2DP])
		print("🚨 [AudioPro] Category set to .playback")
		
		// Set audio session active synchronously to ensure it's ready before playback starts
		try session.setActive(true, options: .notifyOthersOnDeactivation)
		print("🚨 [AudioPro] Audio session activated")
		
		// Log final state after configuration
		print("🚨 [AudioPro] After config - Category: \(session.category.rawValue), Mode: \(session.mode.rawValue), Active: \(session.isOtherAudioPlaying)")
		
		// Interruption observer is already set up in init()
		log("Audio session configured for playback with enhanced options")
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

	@objc(testInterruptionHandling)
	func testInterruptionHandling() {
		print("🚨 [AudioPro] MANUAL TEST: Simulating interruption handling")
		
		// Simulate what happens when we were playing before interruption
		shouldBePlaying = true
		
		// Simulate interruption ended with shouldResume
		print("🚨 [AudioPro] MANUAL TEST: Calling reactivateAudioSession and resume")
		reactivateAudioSession()
		
		// Small delay then resume
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
			self?.resume()
		}
	}
	
	@objc(testAudioSessionState)
	func testAudioSessionState() {
		let session = AVAudioSession.sharedInstance()
		print("🚨 [AudioPro] AUDIO SESSION STATE:")
		print("  - Category: \(session.category.rawValue)")
		print("  - Mode: \(session.mode.rawValue)")
		print("  - Is active: \(session.isOtherAudioPlaying)")
		print("  - Output volume: \(session.outputVolume)")
		print("  - Sample rate: \(session.sampleRate)")
		print("  - I/O buffer duration: \(session.ioBufferDuration)")
		print("  - Current player rate: \(player?.rate ?? 0)")
		print("  - Should be playing: \(shouldBePlaying)")
		print("  - Has listeners: \(hasListeners)")
	}


	
	/// Updates only the dynamic playback values without touching metadata structure
	private func updateNowPlayingPlaybackValues() {
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			
			// Get existing metadata to preserve it
			var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
			
			// Update only dynamic properties
			if let player = self.player {
				let rate = player.rate
				let time = player.currentTime().seconds
				let validTime = (time.isNaN || time.isInfinite) ? 0 : time

				nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = rate
				nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = validTime

				if let currentItem = player.currentItem {
					let itemDuration = currentItem.duration.seconds
					if !itemDuration.isNaN && !itemDuration.isInfinite {
						nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = itemDuration
					}
				}
				
				self.log("[AirPlay Fix] Updated playback values - rate: \(rate), time: \(validTime)")
			} else {
				// If player is nil, reflect a stopped state
				nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0
				nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0
			}
			
			// Apply the updated values
			MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
		}
	}

	private func checkBackgroundAudioConfiguration() {
		// Check background modes configuration (SwiftAudioEx requirement)
		if let backgroundModes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] {
			let hasAudioBackground = backgroundModes.contains("audio")
			let hasAirPlayBackground = backgroundModes.contains("audio") // AirPlay requires "audio" background mode
			
			log("[SwiftAudioEx Check] Background modes found: \(backgroundModes)")
			log("[SwiftAudioEx Check] Has audio background mode: \(hasAudioBackground)")
			log("[SwiftAudioEx Check] AirPlay will work: \(hasAirPlayBackground)")
			
			if !hasAudioBackground {
				log("[SwiftAudioEx Check] ❌ WARNING: Missing 'audio' background mode!")
				log("[SwiftAudioEx Check] Add 'Audio, AirPlay, and Picture in Picture' capability in Xcode")
				log("[SwiftAudioEx Check] This is required for AirPlay to work properly")
			} else {
				log("[SwiftAudioEx Check] ✅ Background audio configuration is correct")
			}
		} else {
			log("[SwiftAudioEx Check] ❌ ERROR: No UIBackgroundModes found in Info.plist!")
			log("[SwiftAudioEx Check] AirPlay will not work without background audio capabilities")
		}
	}

	/// Sets basic Now Playing metadata immediately (title, artist, live stream flag)
	/// This is called immediately when play() starts - never blocks for artwork
	private func setBasicNowPlayingMetadata() {
		// Always set on main thread
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			
			log("[AirPlay Fix] Setting basic metadata immediately")
			
			// Create basic metadata dictionary
			var nowPlayingInfo = [String: Any]()

			// Set basic track info
			if let trackInfo = self.currentTrack {
				nowPlayingInfo[MPMediaItemPropertyTitle] = trackInfo["title"] as? String ?? "Live Radio"
				nowPlayingInfo[MPMediaItemPropertyArtist] = trackInfo["artist"] as? String ?? "Now Streaming"
			} else {
				nowPlayingInfo[MPMediaItemPropertyTitle] = "Live Radio"
				nowPlayingInfo[MPMediaItemPropertyArtist] = "Now Streaming"
			}
			
			// CRITICAL: Always set live stream flag for radio streams
			nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = true
			
			// Set initial playback values
			nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0.0
			nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = 0.0
			
			// Apply immediately - artwork will be added later
			MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
			
			log("[AirPlay Fix] Basic metadata set - artwork will load asynchronously")
		}
	}

	/// Loads artwork asynchronously in the background - never blocks playback or metadata setup
	private func loadArtworkAsync(from artworkPath: String) {
		DispatchQueue.global(qos: .background).async { [weak self] in
			guard let self = self else { return }
			
			var loadedImage: UIImage?
			
			// Try to load from React Native asset
			if artworkPath.hasPrefix("file://") {
				let fileURL = URL(string: artworkPath)
				loadedImage = fileURL.flatMap { UIImage(contentsOfFile: $0.path) }
			} else if !artworkPath.hasPrefix("http") {
				// React Native asset bundle
				let assetName = artworkPath.replacingOccurrences(of: "file://", with: "")
				loadedImage = UIImage(named: assetName)
			} else {
				// Remote URL - skip for now to avoid network delays
				log("[AirPlay Fix] Skipping remote artwork to avoid delays: \(artworkPath)")
			}
			
			// Resize to Samsung TV optimal size if loaded
			if let image = loadedImage {
				loadedImage = self.resizeImageForSamsungTV(image)
				log("[AirPlay Fix] Artwork loaded and resized: \(image.size)")
			} else {
				// Use fallback for AirPlay compatibility
				loadedImage = self.createSamsungTVFallbackArtwork()
				log("[AirPlay Fix] Using fallback artwork for AirPlay compatibility")
			}
			
			// Update artwork in Now Playing info
			DispatchQueue.main.async { [weak self] in
				guard let self = self else { return }
				self.currentArtworkImage = loadedImage
				self.updateArtworkInNowPlayingInfo()
			}
		}
	}

	/// Updates only the artwork in Now Playing info without disrupting existing metadata
	private func updateArtworkInNowPlayingInfo() {
		guard let artworkImage = currentArtworkImage else { return }
		
		DispatchQueue.main.async { [weak self] in
			guard let self = self else { return }
			
			// Get existing Now Playing info to preserve it
			var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [String: Any]()
			
			// Only update artwork - preserve all other metadata
			let artwork = MPMediaItemArtwork(boundsSize: artworkImage.size) { _ in
				return artworkImage
			}
			nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
			
			// Apply updated info
			MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
			
			log("[AirPlay Fix] Artwork updated in Now Playing info without disrupting metadata")
		}
	}

	/// Simple resize to Samsung TV optimal size (600x600)
	private func resizeImageForSamsungTV(_ image: UIImage) -> UIImage {
		let targetSize = CGSize(width: 600, height: 600)
		
		UIGraphicsBeginImageContextWithOptions(targetSize, false, 0.0)
		image.draw(in: CGRect(origin: .zero, size: targetSize))
		let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
		UIGraphicsEndImageContext()
		
		return resizedImage
	}
}