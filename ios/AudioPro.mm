#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(AudioPro, RCTEventEmitter)

RCT_EXTERN_METHOD(play:(NSDictionary *)track withOptions:(NSDictionary *)options)
RCT_EXTERN_METHOD(pause)
RCT_EXTERN_METHOD(resume)
RCT_EXTERN_METHOD(stop)
RCT_EXTERN_METHOD(seekTo:(double)position)
RCT_EXTERN_METHOD(seekForward:(double)amount)
RCT_EXTERN_METHOD(seekBack:(double)amount)
RCT_EXTERN_METHOD(setPlaybackSpeed:(double)speed)
RCT_EXTERN_METHOD(setVolume:(double)volume)
RCT_EXTERN_METHOD(clear)
RCT_EXTERN_METHOD(reactivateAudioSession)

RCT_EXTERN_METHOD(ambientPlay:(NSDictionary *)options)
RCT_EXTERN_METHOD(ambientStop)
RCT_EXTERN_METHOD(ambientSetVolume:(double)volume)
RCT_EXTERN_METHOD(ambientPause)
RCT_EXTERN_METHOD(ambientResume)
RCT_EXTERN_METHOD(ambientSeekTo:(double)positionMs)

RCT_EXTERN_METHOD(testInterruptionHandling)
RCT_EXTERN_METHOD(testAudioSessionState)
RCT_EXTERN_METHOD(debugSamsungTVState)

+ (BOOL)requiresMainQueueSetup
{
  return NO;
}

@end
