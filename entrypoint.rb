#!/usr/bin/env ruby
require 'active_support'
require 'active_support/core_ext'
require 'awesome_print'

# Load ruby libraries
require File.join(ENV['RUBYLIB'], 'logging_helper.rb')
Dir[File.join(ENV['RUBYLIB'], '**/*.rb')].each { |f| require f }

Thread.abort_on_exception = true
$stdout.sync = true

if ARGV.size.positive?
  exec(*ARGV)
else
  ParetoEventRouter.instance.start!
end
