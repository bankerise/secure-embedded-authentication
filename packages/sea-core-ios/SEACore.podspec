require 'json'

Pod::Spec.new do |s|
  s.name         = 'SEACore'
  s.version      = '0.0.1'
  s.summary      = 'Bankerise SEA — hardened embedded WebView auth core (iOS).'
  s.homepage     = 'https://github.com/bankerise/secure-embedded-authentication'
  s.license      = { :type => 'Apache-2.0', :file => 'LICENSE' }
  s.author       = 'Bankerise'
  s.platform     = :ios, '15.0'
  s.swift_version = '5.9'
  s.source       = {
    :git => 'https://github.com/bankerise/secure-embedded-authentication.git',
    :tag => "sea-core-ios/#{s.version}"
  }

  # s.source checks out the whole monorepo at the given tag, so paths below
  # are repo-root-relative rather than package-relative.
  s.source_files = 'packages/sea-core-ios/Sources/SEACore/**/*.swift'
  s.resources    = 'packages/sea-core-ios/Sources/SEACore/Resources/**/*.lproj'
end
