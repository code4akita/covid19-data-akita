$:.unshift File.expand_path(File.join(File.dirname(__FILE__), 'lib'))

require 'rubygems'
require "bundler/setup"
Bundler.require

Dir.glob('lib/tasks/*.rake').each { |r| load r}
