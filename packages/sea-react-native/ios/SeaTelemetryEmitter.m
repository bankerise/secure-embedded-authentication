#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(SeaTelemetryEmitter, RCTEventEmitter)

RCT_EXTERN_METHOD(copyToClipboard:(NSString *)text)
RCT_EXTERN_METHOD(purgeWebData:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end
