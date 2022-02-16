#!/bin/sh

set -e

gem install activesupport -v 4.2

gem install rubocop -v 1.25.0
gem install rubocop-rspec -v 2.8.0
gem install rubocop-performance -v 1.13.2
gem install rubocop-rails -v 2.13.2
gem install rubocop-rake -v 0.6.0

ruby /action/lib/index.rb
