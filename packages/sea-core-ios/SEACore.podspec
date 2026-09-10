require 'json'

Pod::Spec.new do |s|
  s.name         = 'SEACore'
  s.version      = '0.0.8'
  s.summary      = 'Bankerise SEA — hardened embedded WebView auth core (iOS).'
  s.homepage     = 'https://github.com/bankerise/secure-embedded-authentication'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
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
  #
  # A `File.directory?(__dir__ + 'Sources')` runtime check can't tell these
  # apart reliably: `__dir__` reflects wherever the podspec *file* physically
  # sits when Ruby evaluates it, which — for `pod spec lint <local path>` —
  # is this package directory (Sources/ sits right next to it) even though
  # the linter then validates source_files against the git+tag source, which
  # checks out the whole monorepo (repo-root-relative). That mismatch made
  # `pod spec lint` fail with "pattern did not match any file" despite both
  # real consumption paths working. Listing both candidate patterns sidesteps
  # detection entirely — whichever one doesn't match the actual pod root
  # simply contributes no files.
  s.source_files = ['Sources/SEACore/**/*.swift', 'packages/sea-core-ios/Sources/SEACore/**/*.swift']
  s.resources    = ['Sources/SEACore/Resources/**/*.lproj', 'packages/sea-core-ios/Sources/SEACore/Resources/**/*.lproj']
end
