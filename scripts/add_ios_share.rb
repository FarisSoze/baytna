# Adds the BaytnaShare extension target (the «بيتنا» entry in the share sheet, for Google Maps links) to the Capacitor iOS project.
# Runs in CI after add_ios_widget.rb, on a fresh checkout, so the committed project stays extension-free.
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
app = project.targets.find { |t| t.name == 'App' } or abort('App target not found')
name = 'BaytnaShare'
exit 0 if project.targets.any? { |t| t.name == name }

share = project.new_target(:app_extension, name, :ios, '17.0')
group = project.main_group.new_group(name, name)
source = group.new_file('ShareViewController.swift')
group.new_file('Info.plist')
share.add_file_references([source])

share.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.baytna.app.share'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'BaytnaShare/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['MARKETING_VERSION'] = '1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'NO' # it walks up to UIApplication to open the app on its Places tab
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

app.add_dependency(share)
embed = app.copy_files_build_phases.find { |p| p.dst_subfolder_spec == '13' } || app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.dst_subfolder_spec = '13' # PlugIns
embed.add_file_reference(share.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "added #{name} target"
