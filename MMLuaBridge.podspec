Pod::Spec.new do |spec|
  spec.name                     = "MMLuaBridge"
  spec.version                  = "1.0.0"
  spec.summary                  = "MMLuaBridge"
  spec.platform                 = :ios
  spec.license                  = { :type => 'Apache', :file => 'LICENSE' }
  spec.ios.deployment_target 	  = "7.0"
  spec.authors                  = { "Yang Zexin" => "yangzexin27@gmail.com" }
  spec.homepage                 = "https://github.com/yangzexin/MMLuaBridge"
  spec.source                   = { :git => "#{spec.homepage}.git", :branch => "master" }
  spec.requires_arc             = true
  spec.source_files = "MMLuaBridge/*.{h,m}", "MMLuaBridge/lua-5.1.5/src/*.{h,c}"
  spec.exclude_files = "MMLuaBridge/lua-5.1.5/src/lua.c", "MMLuaBridge/lua-5.1.5/src/luac.c"
end
