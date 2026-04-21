#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint flutter_cache_video_player.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'flutter_cache_video_player'
  s.version          = '1.6.0'
  s.summary          = 'flutter_cache_video_player'
  s.description      = <<-DESC
A six-terminal universal audio and video player that caches while watching, supports multi-threaded download, breakpoint resumption, and LRU cache elimination.
                       DESC
  s.homepage         = 'https://jsontodart.cn'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Matkurban' => '3496354336@qq.com' }

  s.source           = { :path => '.' }
  s.source_files = 'flutter_cache_video_player/Sources/flutter_cache_video_player/**/*'

  # If your plugin requires a privacy manifest, for example if it collects user
  # data, update the PrivacyInfo.xcprivacy file to describe your plugin's
  # privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'flutter_cache_video_player_privacy' => ['flutter_cache_video_player/Sources/flutter_cache_video_player/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
