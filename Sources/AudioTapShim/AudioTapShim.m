#import "AudioTapShim.h"

BOOL VoxInstallInputTap(
    AVAudioInputNode *node,
    AVAudioFrameCount bufferSize,
    AVAudioFormat *format,
    AVAudioNodeTapBlock block,
    NSError **error
) {
    @try {
        [node installTapOnBus:0 bufferSize:bufferSize format:format block:block];
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            *error = [NSError errorWithDomain:@"com.andykumeda.vox.audio-tap"
                                         code:1
                                     userInfo:@{
                NSLocalizedDescriptionKey: exception.reason ?: @"Core Audio rejected the input tap format",
                @"exceptionName": exception.name
            }];
        }
        return NO;
    }
}
