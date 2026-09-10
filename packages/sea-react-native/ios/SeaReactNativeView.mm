#import "SeaReactNativeView.h"

#import <React/RCTBridgeModule.h>
#import <React/RCTConversions.h>
#import <React/RCTEventEmitter.h>

#import <react/renderer/components/SeaReactNativeViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/SeaReactNativeViewSpec/EventEmitters.h>
#import <react/renderer/components/SeaReactNativeViewSpec/Props.h>
#import <react/renderer/components/SeaReactNativeViewSpec/RCTComponentViewHelpers.h>

#import "RCTFabricComponentsPlugins.h"

// Quoted form resolves under a plain static-lib pod build; under
// `use_frameworks!` the generated Swift interface header only lands in the
// framework's own Headers/ dir, reachable solely via the module-qualified
// angle-bracket form.
#if __has_include("SeaReactNative-Swift.h")
#import "SeaReactNative-Swift.h"
#else
#import <SeaReactNative/SeaReactNative-Swift.h>
#endif

using namespace facebook::react;

// This view is the entire native glue (spec §7.4): it reads props, converts
// them to primitives, hands them to SEABridgePresenter (which is the only
// place that touches SEACore), and converts the result back to Fabric
// events. No authentication/navigation/validation logic lives here.
@implementation SeaReactNativeView {
  UIView *_view;
  UIViewController *_presentedViewController;
  BOOL _hasStarted;
  BOOL _hasFinished;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<SeaReactNativeViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const SeaReactNativeViewProps>();
    _props = defaultProps;

    _view = [[UIView alloc] init];
    self.contentView = _view;
  }

  return self;
}

- (void)updateProps:(Props::Shared const &)props oldProps:(Props::Shared const &)oldProps
{
  [super updateProps:props oldProps:oldProps];
  [self startIfNeeded];
}

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  [self startIfNeeded];
}

// Lifecycle per spec §7.2: mount -> pre-warm -> present. Props can arrive
// before the view is attached to a window (no presenter available yet) or
// vice versa, so this is called from both hooks and only actually starts
// once both a real `authorizeUrl` and a window are present.
- (void)startIfNeeded
{
  if (_hasStarted || self.window == nil) {
    return;
  }

  const auto &viewProps = *std::static_pointer_cast<const SeaReactNativeViewProps>(_props);
  if (viewProps.authorizeUrl.empty()) {
    return;
  }

  _hasStarted = YES;

  NSString *authorizeUrl = RCTNSStringFromString(viewProps.authorizeUrl);
  NSString *presentation =
      viewProps.presentation == SeaReactNativeViewPresentation::Fullscreen ? @"fullscreen" : @"sheet";
  NSString *authMode =
      viewProps.authMode == SeaReactNativeViewAuthMode::NativeBrowser ? @"nativeBrowser" : @"embedded";

  const auto &appearance = viewProps.appearance;
  UIColor *headerBackground = RCTUIColorFromSharedColor(appearance.headerBackground);
  UIColor *headerText = RCTUIColorFromSharedColor(appearance.headerText);
  UIColor *accent = RCTUIColorFromSharedColor(appearance.accent);
  UIColor *closeIconTint = RCTUIColorFromSharedColor(appearance.closeIconTint);
  // 0 is the codegen default for an unset numeric prop — treated as "not
  // provided" so the native side falls back to SEAAppearance.default's radius.
  NSNumber *cornerRadius = appearance.cornerRadius > 0 ? @(appearance.cornerRadius) : nil;
  NSString *title = RCTNSStringFromString(appearance.title);

  __weak SeaReactNativeView *weakSelf = self;
  SEABridgeCallbacks *callbacks = [[SEABridgeCallbacks alloc]
      initOnCaptured:^(NSString *paramsJson) {
        [weakSelf emitCaptured:paramsJson];
      }
      onCancelled:^{
        [weakSelf emitCancelled];
      }
      onError:^(NSString *code, NSString *_Nullable message) {
        [weakSelf emitError:code message:message];
      }];

  _presentedViewController = [SEABridgePresenter startFromAnchor:_view
                                                     authorizeUrl:authorizeUrl
                                                     presentation:presentation
                                                         authMode:authMode
                                                 headerBackground:headerBackground
                                                       headerText:headerText
                                                           accent:accent
                                                    closeIconTint:closeIconTint
                                                     cornerRadius:cornerRadius
                                                            title:title
                                                        callbacks:callbacks];
}

- (void)emitCaptured:(NSString *)paramsJson
{
  if (_hasFinished || !_eventEmitter) {
    return;
  }
  _hasFinished = YES;
  std::static_pointer_cast<const SeaReactNativeViewEventEmitter>(_eventEmitter)
      ->onCaptured({.paramsJson = std::string([paramsJson UTF8String])});
}

- (void)emitCancelled
{
  if (_hasFinished || !_eventEmitter) {
    return;
  }
  _hasFinished = YES;
  std::static_pointer_cast<const SeaReactNativeViewEventEmitter>(_eventEmitter)->onCancelled({});
}

- (void)emitError:(NSString *)code message:(NSString *_Nullable)message
{
  if (_hasFinished || !_eventEmitter) {
    return;
  }
  _hasFinished = YES;
  std::static_pointer_cast<const SeaReactNativeViewEventEmitter>(_eventEmitter)->onError({
      .code = std::string([code UTF8String]),
      .message = std::string(message ? [message UTF8String] : ""),
  });
}

// Spec §7.2 dismiss: if this view is being torn down (host unmounted it,
// e.g. right after a terminal callback) before we've heard back, dismiss
// whatever SEACore presented rather than leaving it stranded.
- (void)prepareForRecycle
{
  [super prepareForRecycle];
  if (_presentedViewController != nil && !_hasFinished) {
    [SEABridgePresenter dismiss:_presentedViewController];
  }
  _presentedViewController = nil;
  _hasStarted = NO;
  _hasFinished = NO;
}

@end

// Autolinking's third-party Fabric component discovery (react-native/scripts/
// codegen/generate-artifacts-executor.js) doesn't read codegenConfig for
// this — it regex-scans every .mm file in the library for a function of
// this exact shape (component name, then the literal suffix "Cls", then an
// open paren) and only then registers that name in the generated
// RCTThirdPartyComponentsProvider.mm lookup table RN uses at runtime to
// instantiate the native view by name. Without it, SecureAuthenticationView
// silently renders nothing — no crash, no RCTLog, nothing — because there
// is no registered class to instantiate.
//
// IMPORTANT: that scan is a naive single-line regex, not a real parser — it
// takes the first line anywhere in this file matching the shape above,
// comments included. Never describe the pattern itself in a comment here;
// say what it does instead.
#ifdef RCT_NEW_ARCH_ENABLED
Class<RCTComponentViewProtocol> SeaReactNativeViewCls(void)
{
  return SeaReactNativeView.class;
}
#endif
