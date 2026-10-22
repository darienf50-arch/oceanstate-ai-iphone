platform :ios, '17.0'
use_frameworks! :linkage => :static
target 'OceanStateAI' do
  pod 'Tor/CTor', '409.14.1'
end
post_install do |installer|
  installer.pods_project.targets.each do |target|
    if target.name == 'Tor'
      # This app uses the embedded thread/configuration API only. The upstream
      # unused X25519 wrapper references base32 symbols absent from its binary.
      # Keep the minimal public API we actually use, without modifying C-Tor.
      keep = ['TORConfiguration.m', 'TORThread.m', 'TORLogging.m', 'Tor-dummy.m']
      target.source_build_phase.files.to_a.each do |entry|
        name = File.basename(entry.file_ref.path.to_s)
        entry.remove_from_project if name.end_with?('.m') && !keep.include?(name)
      end
    end
    target.build_configurations.each do |config|
      config.build_settings['CODE_SIGNING_ALLOWED'] = 'NO'
    end
  end
end
