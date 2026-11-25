# Adds the BaytnaWidget extension target to the Capacitor iOS project.
# Runs in CI on a fresh checkout (there is no Xcode on the Windows dev machine), so the committed project stays widget-free.
require 'xcodeproj'

project = Xcodeproj::Project.open('ios/App/App.xcodeproj')
app = project.targets.find { |t| t.name == 'App' } or abort('App target not found')
name = 'BaytnaWidget'
exit 0 if project.targets.any? { |t| t.name == name }

widget = project.new_target(:app_extension, name, :ios, '17.0')
group = project.main_group.new_group(name, name)
source = group.new_file('BaytnaWidget.swift')
group.new_file('Info.plist')
widget.add_file_references([source])

widget.build_configurations.each do |config|
  s = config.build_settings
  s['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.baytna.app.widget'
  s['PRODUCT_NAME'] = '$(TARGET_NAME)'
  s['INFOPLIST_FILE'] = 'BaytnaWidget/Info.plist'
  s['GENERATE_INFOPLIST_FILE'] = 'NO'
  s['SWIFT_VERSION'] = '5.0'
  s['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  s['TARGETED_DEVICE_FAMILY'] = '1,2'
  s['MARKETING_VERSION'] = '1.0'
  s['CURRENT_PROJECT_VERSION'] = '1'
  s['SKIP_INSTALL'] = 'YES'
  s['APPLICATION_EXTENSION_API_ONLY'] = 'YES'
  s['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks', '@executable_path/../../Frameworks']
end

app.add_dependency(widget)
embed = app.new_copy_files_build_phase('Embed Foundation Extensions')
embed.dst_subfolder_spec = '13' # PlugIns
embed.add_file_reference(widget.product_reference, true).settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }

project.save
puts "added #{name} target"
