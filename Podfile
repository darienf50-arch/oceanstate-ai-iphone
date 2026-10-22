platform :ios, '17.0'
use_frameworks! :linkage => :static
target 'OceanStateAI' do
  pod 'OceanCTor', :podspec => 'OceanCTor.podspec'
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
