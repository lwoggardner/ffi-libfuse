# frozen_string_literal: true

# -*- mode: ruby -*-
# vi: set ft=ruby :

# All Vagrant configuration is done below. The "2" in Vagrant.configure
# configures the configuration version (we support older styles for
# backwards compatibility). Please don't change it unless you know what
# you're doing.
Vagrant.configure('2') do |config|
  %w[focal impish].each do |dist|
    %w[fuse fuse3].each do |fuse_ver|
      config.vm.define "#{fuse_ver}-#{dist}", auto_start: false do |dist_config|
        dist_config.vm.box = "ubuntu/#{dist}64"
        dist_config.vm.provision :shell, inline: <<-SHELL
         apt-get update -y
         apt-get install -y gnupg2 gcc make ruby ruby-dev libffi-dev ruby-bundler #{fuse_ver} lib#{fuse_ver}-dev
        SHELL
        dist_config.vm.provision :shell, path: 'vagrant/install-rvm.sh', args: 'stable', privileged: false
        # TODO: extract rubies from github workflow
        %w[2.7].each do |v|
          dist_config.vm.provision :shell, path: 'vagrant/install-ruby.sh', args: [v, 'bundler'], privileged: false
        end
        dist_config.vm.provision :shell, inline: 'cd /vagrant; bundle install', privileged: false
      end
    end
  end
end
