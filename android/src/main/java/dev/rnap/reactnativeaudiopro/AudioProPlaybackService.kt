package dev.rnap.reactnativeaudiopro

import android.Manifest
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

open class AudioProPlaybackService : MediaLibraryService() {

	private lateinit var mediaLibrarySession: MediaLibrarySession

	companion object {
		private const val NOTIFICATION_ID = 789
		private const val CHANNEL_ID = "audio_pro_notification_channel_id"
	}

	/**
	 * Returns the single top session activity. It is used by the notification when the app task is
	 * active and an activity is in the fore or background.
	 *
	 * Tapping the notification then typically should trigger a single top activity. This way, the
	 * user navigates to the previous activity when pressing back.
	 *
	 * If null is returned, [MediaSession.setSessionActivity] is not set by the demo service.
	 */
	open fun getSingleTopActivity(): PendingIntent? = null

	/**
	 * Returns a back stacked session activity that is used by the notification when the service is
	 * running standalone as a foreground service. This is typically the case after the app has been
	 * dismissed from the recent tasks, or after automatic playback resumption.
	 *
	 * Typically, a playback activity should be started with a stack of activities underneath. This
	 * way, when pressing back, the user doesn't land on the home screen of the device, but on an
	 * activity defined in the back stack.
	 *
	 * See [androidx.core.app.TaskStackBuilder] to construct a back stack.
	 *
	 * If null is returned, [MediaSession.setSessionActivity] is not set by the demo service.
	 */
	open fun getBackStackedActivity(): PendingIntent? = null

	/**
	 * Creates the library session callback to implement the domain logic. Can be overridden to return
	 * an alternative callback, for example a subclass of [AudioProMediaLibrarySessionCallback].
	 *
	 * This method is called when the session is built by the [AudioProPlaybackService].
	 */
	@OptIn(UnstableApi::class)
	protected open fun createLibrarySessionCallback(): MediaLibrarySession.Callback {
		return AudioProMediaLibrarySessionCallback()
	}

	@OptIn(UnstableApi::class) // MediaSessionService.setListener
	override fun onCreate() {
		super.onCreate()
		initializeSessionAndPlayer()
		setListener(MediaSessionServiceListener())
	}

	override fun onGetSession(controllerInfo: ControllerInfo): MediaLibrarySession {
		return mediaLibrarySession
	}

	/**
	 * Called when the task is removed from the recent tasks list
	 * This happens when the user swipes away the app from the recent apps list
	 */
	override fun onTaskRemoved(rootIntent: android.content.Intent?) {
		android.util.Log.d("AudioProPlaybackService", "Task removed, stopping service")

		// Force stop playback and release resources
		try {
			if (::mediaLibrarySession.isInitialized) {
				// Stop playback
				mediaLibrarySession.player.stop()
				// Release player and session
				mediaLibrarySession.player.release()
				mediaLibrarySession.release()
			}
		} catch (e: Exception) {
			android.util.Log.e("AudioProPlaybackService", "Error stopping playback", e)
		}

		// Remove notification and stop service
		removeNotificationAndStopService()

		super.onTaskRemoved(rootIntent)
	}

	// MediaSession.setSessionActivity
	// MediaSessionService.clearListener
	@OptIn(UnstableApi::class)
	override fun onDestroy() {
		android.util.Log.d("AudioProPlaybackService", "Service being destroyed")

		// Make sure to release all resources
		try {
			if (::mediaLibrarySession.isInitialized) {
				// Stop playback first
				mediaLibrarySession.player.stop()
				// Release session and player
				mediaLibrarySession.release()
				mediaLibrarySession.player.release()
			}
			clearListener()
		} catch (e: Exception) {
			android.util.Log.e("AudioProPlaybackService", "Error during service destruction", e)
		}

		// Remove notification
		removeNotificationAndStopService()

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

	@OptIn(UnstableApi::class)
	private fun initializeSessionAndPlayer() {
		// Create a composite data source factory that can handle both HTTP and file URIs
		val dataSourceFactory = object : DataSource.Factory {
			override fun createDataSource(): DataSource {
				// Create HTTP data source factory with custom headers if available
				val httpDataSourceFactory = DefaultHttpDataSource.Factory()

				// Apply custom headers if they exist
				AudioProController.headersAudio?.let { headers ->
					if (headers.isNotEmpty()) {
						httpDataSourceFactory.setDefaultRequestProperties(headers)
						android.util.Log.d(
							"AudioProPlaybackService",
							"Applied custom headers: $headers"
						)
					}
				}

				// Create a DefaultDataSource that will handle both HTTP and file URIs
				// It will delegate to FileDataSource for file:// URIs and to HttpDataSource for http(s):// URIs
				return DefaultDataSource.Factory(applicationContext, httpDataSourceFactory)
					.createDataSource()
			}
		}

		val mediaSourceFactory = DefaultMediaSourceFactory(dataSourceFactory)

		val player =
			ExoPlayer.Builder(this)
				.setMediaSourceFactory(mediaSourceFactory)
				.setAudioAttributes(
					AudioAttributes.Builder()
						.setUsage(C.USAGE_MEDIA)
						.setContentType(AudioProController.settingAudioContentType)
						.build(),
					/* handleAudioFocus = */ true
				)
				.build()
		player.setHandleAudioBecomingNoisy(true)
		player.repeatMode = Player.REPEAT_MODE_OFF
		player.addAnalyticsListener(EventLogger())

		mediaLibrarySession =
			MediaLibrarySession.Builder(this, player, createLibrarySessionCallback())
				.also { builder -> getSingleTopActivity()?.let { builder.setSessionActivity(it) } }
				.build()
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
					//.setSmallIcon(R.drawable.media3_notification_small_icon)
					//.setContentTitle(getString(R.string.notification_content_title))
					//.setStyle(
					//  NotificationCompat.BigTextStyle().bigText(getString(R.string.notification_content_text))
					//)
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
