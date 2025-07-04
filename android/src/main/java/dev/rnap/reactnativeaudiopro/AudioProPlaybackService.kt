package dev.rnap.reactnativeaudiopro

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.pm.PackageManager
import android.os.Build
import androidx.annotation.OptIn
import androidx.annotation.RequiresPermission
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.os.bundleOf
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.datasource.DataSource
import androidx.media3.exoplayer.util.EventLogger
import androidx.media3.session.MediaConstants
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSession.ControllerInfo
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import com.google.common.util.concurrent.ListenableFuture
import android.os.Bundle

class AudioProPlaybackService : MediaLibraryService() {

	private lateinit var player: Player
	private lateinit var mediaLibrarySession: MediaLibrarySession

	companion object {
		private const val NOTIFICATION_ID = 789
		private const val CHANNEL_ID = "react_native_audio_pro_channel"
	}

	/**
	 * Returns the single top session activity. It is used by the notification when the app task is
	 * active and an activity is in the fore or background.
	 */
	open fun getSingleTopActivity(): PendingIntent? = null

	/**
	 * Returns a back stacked session activity that is used by the notification when the service is
	 * running standalone as a foreground service.
	 */
	open fun getBackStackedActivity(): PendingIntent? = null

	override fun onCreate() {
		super.onCreate()
		
		// Create ExoPlayer instance directly
		val player = ExoPlayer.Builder(this)
			.setAudioAttributes(
				AudioAttributes.Builder()
					.setUsage(C.USAGE_MEDIA)
					.setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
					.build(),
				/* handleAudioFocus= */ true
			)
			.build()
			
		// Store player reference
		this.player = player
		
		mediaLibrarySession = MediaLibrarySession.Builder(
			this,
			player,
			AudioProMediaLibrarySessionCallback()
		).build()
		
		createNotificationChannel()
	}

	override fun onGetSession(controllerInfo: ControllerInfo): MediaLibrarySession {
		return mediaLibrarySession
	}

	/**
	 * Called when the task is removed from the recent tasks list
	 * This happens when the user swipes away the app from the recent apps list
	 */
	override fun onTaskRemoved(rootIntent: android.content.Intent?) {
		if (!player.isPlaying) {
			stopSelf()
		}
		super.onTaskRemoved(rootIntent)
	}

	@OptIn(UnstableApi::class)
	override fun onDestroy() {
		mediaLibrarySession.release()
		player.release()
		super.onDestroy()
	}

	/**
	 * Helper method to remove notification and stop the service
	 * Centralizes the notification removal and service stopping logic
	 */
	private fun removeNotificationAndStopService() {
		try {
			// Remove notification directly
			val notificationManager =
				getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
			notificationManager.cancel(NOTIFICATION_ID)

			// Stop foreground service - handle API level differences
			if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
				// For Android 12 (API 31) and above, use the new API
				stopForeground(STOP_FOREGROUND_REMOVE)
			} else {
				// For older Android versions, use the deprecated API
				@Suppress("DEPRECATION")
				stopForeground(true)
			}

			// Stop the service
			stopSelf()
		} catch (e: Exception) {
			android.util.Log.e("AudioProPlaybackService", "Error stopping service", e)
		}
	}

	private fun createNotificationChannel() {
		val channel = NotificationChannel(
			CHANNEL_ID,
			"Audio Pro Playback",
			NotificationManager.IMPORTANCE_LOW
		).apply {
			description = "Audio playback controls"
		}
		val notificationManagerCompat = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
		notificationManagerCompat.createNotificationChannel(channel)
	}

	@OptIn(UnstableApi::class) // MediaSessionService.Listener
	private inner class MediaSessionServiceListener : Listener {

		/**
		 * This method is only required to be implemented on Android 12 or above when an attempt is made
		 * by a media controller to resume playback when the {@link MediaSessionService} is in the
		 * background.
		 */
		@RequiresPermission(Manifest.permission.POST_NOTIFICATIONS)
		override fun onForegroundServiceStartNotAllowedException() {
			if (
				Build.VERSION.SDK_INT >= 33 &&
				checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
				PackageManager.PERMISSION_GRANTED
			) {
				// Notification permission is required but not granted
				return
			}
			val notificationManagerCompat =
				NotificationManagerCompat.from(this@AudioProPlaybackService)
			ensureNotificationChannel(notificationManagerCompat)
			val builder =
				NotificationCompat.Builder(this@AudioProPlaybackService, CHANNEL_ID)
					.setPriority(NotificationCompat.PRIORITY_DEFAULT)
					.setAutoCancel(true)
					.also { builder -> getBackStackedActivity()?.let { builder.setContentIntent(it) } }
			notificationManagerCompat.notify(NOTIFICATION_ID, builder.build())
		}
	}

	private fun ensureNotificationChannel(notificationManagerCompat: NotificationManagerCompat) {
		val channel =
			NotificationChannel(
				CHANNEL_ID,
				"audio_pro_notification_channel",
				NotificationManager.IMPORTANCE_DEFAULT,
			)
		notificationManagerCompat.createNotificationChannel(channel)
	}
}
