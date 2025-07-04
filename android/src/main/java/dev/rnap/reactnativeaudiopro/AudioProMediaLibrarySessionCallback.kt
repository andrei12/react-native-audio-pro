package dev.rnap.reactnativeaudiopro

import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.CommandButton
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

/** A [MediaLibraryService.MediaLibrarySession.Callback] implementation. */
@UnstableApi
open class AudioProMediaLibrarySessionCallback : MediaLibraryService.MediaLibrarySession.Callback {

	private val nextButton = CommandButton.Builder(CommandButton.ICON_NEXT)
		.setDisplayName("Next")
		.setSessionCommand(
			SessionCommand(
				CUSTOM_COMMAND_NEXT,
				Bundle.EMPTY
			)
		)
		.build()

	private val prevButton = CommandButton.Builder(CommandButton.ICON_PREVIOUS)
		.setDisplayName("Previous")
		.setSessionCommand(
			SessionCommand(
				CUSTOM_COMMAND_PREV,
				Bundle.EMPTY
			)
		)
		.build()

	private fun getCommandButtons(): List<CommandButton> {
		// Always return empty list to disable next/prev/seek controls
		return emptyList()
	}

	companion object {
		private const val CUSTOM_COMMAND_NEXT =
			"dev.rnap.reactnativeaudiopro.NEXT"
		private const val CUSTOM_COMMAND_PREV =
			"dev.rnap.reactnativeaudiopro.PREV"
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
		return MediaSession.ConnectionResult.AcceptedResultBuilder(session)
			.setAvailableSessionCommands(mediaNotificationSessionCommands)
			.setMediaButtonPreferences(getCommandButtons())
			.build()
	}

	@OptIn(UnstableApi::class) // MediaSession.isMediaNotificationController
	override fun onCustomCommand(
		session: MediaSession,
		controller: MediaSession.ControllerInfo,
		customCommand: SessionCommand,
		args: Bundle,
	): ListenableFuture<SessionResult> {
		if (CUSTOM_COMMAND_NEXT == customCommand.customAction) {
			AudioProController.emitNext()
			return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
		} else if (CUSTOM_COMMAND_PREV == customCommand.customAction) {
			AudioProController.emitPrev()
			return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
		}
		return Futures.immediateFuture(SessionResult(SessionError.ERROR_NOT_SUPPORTED))
	}

	override fun onAddMediaItems(
		mediaSession: MediaSession,
		controller: MediaSession.ControllerInfo,
		mediaItems: List<MediaItem>,
	): ListenableFuture<List<MediaItem>> {
		return Futures.immediateFuture(mediaItems)
	}
}
