require 'json'

Pod::Spec.new do |s|
  s.name         = 'SEACore'
  s.version      = '0.0.4'
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

  # Consumed two ways (AGENTS.md): the git/tag source above, which checks
  # out the whole monorepo (pod root == repo root, so paths need to be
  # repo-root-relative), or a local `:path => 'packages/sea-core-ios'` for
  # dev (pod root == this directory, so paths are package-relative).
  # Detect which one we're in by checking whether `Sources/` sits next to
  # this podspec.
  prefix = File.directory?(File.join(__dir__, 'Sources')) ? '' : 'packages/sea-core-ios/'
  s.source_files = "#{prefix}Sources/SEACore/**/*.swift"
  s.resources    = "#{prefix}Sources/SEACore/Resources/**/*.lproj"
end
