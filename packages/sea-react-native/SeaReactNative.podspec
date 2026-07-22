require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "SeaReactNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => "15.0" }
  s.swift_version = "5.9"
  s.source       = { :git => "https://github.com/bankerise/bankerise-sea.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift,cpp}"
  s.private_header_files = "ios/**/*.h"

  # Dev-mode: the app's Podfile pins this to the local sea-core-ios path
  # (spec §4.5); this dependency just names it so CocoaPods resolves the
  # transitive link.
  s.dependency "SEACore"

  install_modules_dependencies(s)
end
