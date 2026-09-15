#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

BOOL VoxInstallInputTap(
    AVAudioInputNode *node,
    AVAudioFrameCount bufferSize,
    AVAudioFormat *_Nullable format,
    AVAudioNodeTapBlock block,
    NSError *_Nullable *_Nullable error
);

NS_ASSUME_NONNULL_END
