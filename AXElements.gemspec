require './lib/accessibility/version'

Gem::Specification.new do |s|
  s.name     = 'AXElements'
  s.version  = Accessibility::VERSION

  s.summary     = 'UI Automation for OS X'
  s.description = <<-EOS
AXElements is a UI automation library built on top of various OS X
frameworks. You can use AXElements to write functional tests for
Cocoa apps, script UI interactions, or even to build higher level
tools such as screen readers.
  EOS
  s.authors     = ['Mark Rada']
  s.email       = 'mrada@marketcircle.com'
  s.homepage    = 'http://axelements.com'
  s.licenses    = ['BSD 3-clause']
  s.has_rdoc    = 'yard'

  s.files            =
    Dir.glob('lib/**/*.rb') +
    Dir.glob('rakelib/*.rake') +
    [
      'Rakefile',
      'README.markdown',
      'History.markdown',
      '.yardopts',
      'CONTRIBUTING.markdown'
    ]
  s.test_files       =
    Dir.glob('test/**/test_*.rb') +
    ['test/helper.rb']

  s.add_runtime_dependency 'mouse',                  '~> 4.0'
  s.add_runtime_dependency 'screen_recorder',        '~> 0.1.5'
  s.add_runtime_dependency 'accessibility_core',     '~> 0.7.1'
  s.add_runtime_dependency 'accessibility_keyboard', '~> 1.0'
  s.add_runtime_dependency 'activesupport',          '~> 4.2'
end
