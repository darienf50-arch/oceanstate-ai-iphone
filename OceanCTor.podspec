Pod::Spec.new do |s|
  s.name = 'OceanCTor'
  s.version = '409.14.1'
  s.summary = 'Official iCepa prebuilt C-Tor, without a conflicting wrapper framework.'
  s.homepage = 'https://github.com/iCepa/Tor.framework'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'iCepa Tor.framework contributors'
  s.source = { :git => 'https://github.com/iCepa/Tor.framework.git', :tag => 'v409.14.1' }
  s.ios.deployment_target = '15.0'
  s.prepare_command = 'Tor/download.sh v409.14.1 "tor" 823d98fcafd8eba089f31b32989ad70e15a0e8a1b5709bc0d5941fb09ef1b625'
  s.vendored_frameworks = 'tor.xcframework'
  s.libraries = 'z'
end
