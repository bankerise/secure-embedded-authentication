require 'json'

Pod::Spec.new do |s|
  s.name         = 'SEACore'
  s.version      = '0.0.1'
  s.summary      = 'Bankerise SEA — hardened embedded WebView auth core (iOS).'
  s.homepage     = 'https://gitlab.proxym-group.net:3022/bankerise-platform/bankerise-sea'
  s.license      = { :type => 'Proprietary' }
  s.author       = 'Bankerise'
  s.platform     = :ios, '15.0'
  s.swift_version = '5.9'
  s.source       = {
    :git => 'ssh://git@gitlab.proxym-group.net:3022/bankerise-platform/bankerise-sea.git',
    :tag => "sea-core-ios/#{s.version}"
  }

  # s.source checks out the whole monorepo at the given tag, so paths below
  # are repo-root-relative rather than package-relative.
  s.source_files = 'packages/sea-core-ios/Sources/SEACore/**/*.swift'
  s.resources    = 'packages/sea-core-ios/Sources/SEACore/Resources/**/*.lproj'
end
