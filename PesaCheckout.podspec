Pod::Spec.new do |s|
  s.name             = 'PesaCheckout'
  s.version          = '0.1.0'
  s.summary          = 'Pesa Checkout for iOS: native card fields, 3-D Secure, pinned transport.'
  s.homepage         = 'https://github.com/pesapeer/pesa-ios'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'PesaPeer Ltd' => 'developer@pesapeer.com' }
  s.source           = { :git => 'https://github.com/pesapeer/pesa-ios.git', :tag => "v#{s.version}" }
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/PesaCheckoutCore/**/*.swift'
  end

  s.subspec 'UI' do |ui|
    ui.source_files = 'Sources/PesaCheckout/**/*.swift'
    ui.dependency 'PesaCheckout/Core'
    ui.frameworks = 'UIKit', 'SwiftUI', 'SafariServices'
  end

  s.default_subspecs = 'UI'
end
