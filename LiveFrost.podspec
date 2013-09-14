Pod::Spec.new do |s|
  s.name         = "LiveFrost"
  s.version      = "0.0.1"
  s.summary      = "Real time blurring."
  s.homepage     = "http://github.com/radi/LiveFrost"
  s.license      = 'MIT'
  s.author       = { "Evadne Wu" => "ev@radi.ws" }
  s.source       = { :git => "http://github.com/radi/LiveFrost.git", :tag => "0.0.1" }
  s.platform     = :ios, '6.0'
  s.source_files = 'LiveFrost', 'LiveFrost/**/*.{h,m}'
  s.exclude_files = 'LiveFrost/Exclude'
  s.frameworks = 'Accelerate', 'QuartzCore', 'UIKit'
  s.requires_arc = true
end
