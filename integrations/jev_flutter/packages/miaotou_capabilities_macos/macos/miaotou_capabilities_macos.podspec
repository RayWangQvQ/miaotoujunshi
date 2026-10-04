#
# The CocoaPods half of this plugin's macOS build. Flutter 3.47 resolves macOS
# plugins through Swift Package Manager and falls back to this; both are declared
# so neither toolchain is a special case.
#
Pod::Spec.new do |s|
  s.name             = 'miaotou_capabilities_macos'
  s.version          = '0.1.0'
  s.summary          = 'The macOS answer to every member of the capability contract.'
  s.description      = <<-DESC
Capture (ScreenCaptureKit), OCR (Vision), draft injection (Accessibility) and the
floating panel (NSPanel) for the 喵头军师 macOS port.
                       DESC
  s.homepage         = 'https://github.com/RayWangQvQ/miaotoujunshi'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'RayWangQvQ' => 'raywangqvq@users.noreply.github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'miaotou_capabilities_macos/Sources/miaotou_capabilities_macos/**/*.swift'
  s.resource_bundles = {
    'miaotou_capabilities_macos_privacy' => [
      'miaotou_capabilities_macos/Sources/miaotou_capabilities_macos/PrivacyInfo.xcprivacy'
    ]
  }

  s.dependency 'FlutterMacOS'

  # 14.0, and the reason is one API: `SCScreenshotManager.captureImage` — taking a
  # still frame of one window — arrived in macOS 14. The window filter is the whole
  # reason this port can photograph a chat that something is standing in front of,
  # so there is no lower floor that would still do the job.
  s.platform = :osx, '14.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
