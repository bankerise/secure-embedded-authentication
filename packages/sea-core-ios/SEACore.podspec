require 'json'

Pod::Spec.new do |s|
  s.name         = 'SEACore'
  s.version      = '0.1.0'
  s.summary      = 'Bankerise SEA — hardened embedded WebView auth core (iOS).'
  s.homepage     = 'https://github.com/bankerise/bankerise-sea'
  s.license      = { :type => 'Proprietary' }
  s.author       = 'Bankerise'
  s.platform     = :ios, '15.0'
  s.swift_version = '5.9'
  s.source       = { :path => '.' }

  # Dev-mode consumption only (spec §4.5): the RN podspec/Podfile point at
  # this package by local :path. Release mode will vendor a signed
  # XCFramework instead — out of scope here.
  s.source_files = 'Sources/SEACore/**/*.swift'
  s.resources    = 'Sources/SEACore/Resources/**/*.lproj'
end
