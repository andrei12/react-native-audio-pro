package dev.rnap.reactnativeaudiopro

import android.content.Context
import android.os.Bundle
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionResult
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/** A [MediaLibraryService.MediaLibrarySession.Callback] implementation. */
@UnstableApi
open class AudioProMediaLibrarySessionCallback : MediaLibraryService.MediaLibrarySession.Callback {

	private val nextButton = CommandButton.Builder()
		.setDisplayName("Next")
		.setIconResId(androidx.media3.session.R.drawable.media3_notification_seek_to_next)
		.setSessionCommand(SessionCommand(COMMAND_SKIP_TO_NEXT, Bundle()))
		.build()

	private val prevButton = CommandButton.Builder()
		.setDisplayName("Previous")
		.setIconResId(androidx.media3.session.R.drawable.media3_notification_seek_to_prev)
		.setSessionCommand(SessionCommand(COMMAND_SKIP_TO_PREVIOUS, Bundle()))
		.build()

	private fun getCommandButtons(): List<CommandButton> {
		// Always return empty list to disable next/prev/seek controls
		return emptyList()
	}

	companion object {
		const val COMMAND_SKIP_TO_NEXT = "skip_to_next"
		const val COMMAND_SKIP_TO_PREVIOUS = "skip_to_previous"
	}

	private fun getCustomCommands(): List<SessionCommand> {
		return listOf(
			SessionCommand(COMMAND_SKIP_TO_NEXT, Bundle()),
			SessionCommand(COMMAND_SKIP_TO_PREVIOUS, Bundle())
		)
	}

	@OptIn(UnstableApi::class) // MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS
	val mediaNotificationSessionCommands
		get() = MediaSession.ConnectionResult.DEFAULT_SESSION_AND_LIBRARY_COMMANDS.buildUpon()
			.also { builder ->
				getCommandButtons().forEach { commandButton ->
					commandButton.sessionCommand?.let { builder.add(it) }
				}
			}
			.build()

	@OptIn(UnstableApi::class)
	override fun onConnect(
		session: MediaSession,
		controller: MediaSession.ControllerInfo,
	): MediaSession.ConnectionResult {
		val connectionResult = super.onConnect(session, controller)

		val availableSessionCommands = connectionResult.availableSessionCommands.buildUpon()

		// Add custom commands
		for (customCommand in getCustomCommands()) {
			availableSessionCommands.add(customCommand)
		}

		return MediaSession.ConnectionResult.accept(
			availableSessionCommands.build(),
			connectionResult.availablePlayerCommands
		)
	}

	@OptIn(UnstableApi::class) // MediaSession.isMediaNotificationController
	override fun onCustomCommand(
		session: MediaSession,
		controller: MediaSession.ControllerInfo,
		customCommand: SessionCommand,
		args: Bundle,
	): ListenableFuture<SessionResult> {
		val player = session.player
		when (customCommand.customAction) {
			COMMAND_SKIP_TO_NEXT -> {
				AudioProController.instance?.skipToNext()
			}
			COMMAND_SKIP_TO_PREVIOUS -> {
				AudioProController.instance?.skipToPrevious()
			}
		}
		return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
	}

	override fun onAddMediaItems(
		mediaSession: MediaSession,
		controller: MediaSession.ControllerInfo,
		mediaItems: List<MediaItem>,
	): ListenableFuture<List<MediaItem>> {
		return Futures.immediateFuture(mediaItems)
	}

	override fun onGetLibraryRoot(
		session: MediaLibraryService.MediaLibrarySession,
		browser: MediaSession.ControllerInfo,
		params: MediaLibraryService.LibraryParams?
	): ListenableFuture<LibraryResult<MediaLibraryService.LibraryParams>> {
		return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_NOT_SUPPORTED))
	}

	override fun onGetItem(
		session: MediaLibraryService.MediaLibrarySession,
		browser: MediaSession.ControllerInfo,
		mediaId: String
	): ListenableFuture<LibraryResult<MediaItem>> {
		return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_NOT_SUPPORTED))
	}

	override fun onGetChildren(
		session: MediaLibraryService.MediaLibrarySession,
		browser: MediaSession.ControllerInfo,
		parentId: String,
		page: Int,
		pageSize: Int,
		params: MediaLibraryService.LibraryParams?
	): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
		return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_NOT_SUPPORTED))
	}

	override fun onSubscribe(
		session: MediaLibraryService.MediaLibrarySession,
		browser: MediaSession.ControllerInfo,
		parentId: String,
		params: MediaLibraryService.LibraryParams?
	): ListenableFuture<LibraryResult<Void>> {
		return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_NOT_SUPPORTED))
	}

	override fun onUnsubscribe(
		session: MediaLibraryService.MediaLibrarySession,
		browser: MediaSession.ControllerInfo,
		parentId: String
	): ListenableFuture<LibraryResult<Void>> {
		return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_NOT_SUPPORTED))
	}

	override fun onSearch(
		session: MediaLibraryService.MediaLibrarySession,
		browser: MediaSession.ControllerInfo,
		query: String,
		params: MediaLibraryService.LibraryParams?
	): ListenableFuture<LibraryResult<Void>> {
		return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_NOT_SUPPORTED))
	}

	override fun onGetSearchResult(
		session: MediaLibraryService.MediaLibrarySession,
		browser: MediaSession.ControllerInfo,
		query: String,
		page: Int,
		pageSize: Int,
		params: MediaLibraryService.LibraryParams?
	): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> {
		return Futures.immediateFuture(LibraryResult.ofError(LibraryResult.RESULT_ERROR_NOT_SUPPORTED))
	}
}
