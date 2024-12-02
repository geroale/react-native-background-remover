#import "DeepLabV3.h"

#ifdef RCT_NEW_ARCH_ENABLED
#import "RNBackgroundRemoverSpec.h"

@interface BackgroundRemover : NSObject <NativeBackgroundRemoverSpec>
#else
#import <React/RCTBridgeModule.h>

@interface BackgroundRemover : NSObject <RCTBridgeModule>
#endif

@end
