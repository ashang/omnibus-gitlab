#
# Copyright:: Copyright (c) 2012 Opscode, Inc.
# Copyright:: Copyright (c) 2014 GitLab.com
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'openssl'

# Default location of install-dir is /opt/gitlab/. This path is set during build time.
# DO NOT change this value unless you are building your own GitLab packages
install_dir = node['package']['install-dir']
ENV['PATH'] = "#{install_dir}/bin:#{install_dir}/embedded/bin:#{ENV['PATH']}"

directory "/etc/gitlab" do
  owner "root"
  group "root"
  mode "0775"
  action :nothing
end.run_action(:create)

Gitlab[:node] = node
if File.exists?("/etc/gitlab/gitlab.rb")
  Gitlab.from_file("/etc/gitlab/gitlab.rb")
end
node.consume_attributes(Gitlab.generate_config(node['fqdn']))

if File.exists?("/var/opt/gitlab/bootstrapped")
	node.set['gitlab']['bootstrap']['enable'] = false
end

directory "/var/opt/gitlab" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

directory "#{install_dir}/embedded/etc" do
  owner "root"
  group "root"
  mode "0755"
  recursive true
  action :create
end

template "#{install_dir}/embedded/etc/gitconfig" do
  source "gitconfig-system.erb"
  mode 0755
  variables gitconfig: node['gitlab']['omnibus-gitconfig']['system']
end

# This recipe needs to run before gitlab-rails
# because we add `gitlab-www` user to some groups created by that recipe
include_recipe "gitlab::web-server"

if node['gitlab']['gitlab-rails']['enable']
  include_recipe "gitlab::users"
  include_recipe "gitlab::gitlab-shell"
  include_recipe "gitlab::gitlab-rails"
end

include_recipe "gitlab::gitlab-ci-proxying"

include_recipe "gitlab::selinux"

# add trusted certs recipe
include_recipe "gitlab::add_trusted_certs"

# Create dummy unicorn and sidekiq services to receive notifications, in case
# the corresponding service recipe is not loaded below.
[
  "unicorn",
  "ci-unicorn",
  "sidekiq",
  "ci-sidekiq",
  "mailroom"
].each do |dummy|
  service dummy do
    supports []
  end
end

# Install our runit instance
include_recipe "runit"

# Configure DB Services
[
  "redis",
  "postgresql" # Postgresql depends on Redis because of `rake db:seed_fu`
].each do |service|
  if node["gitlab"][service]["enable"]
    include_recipe "gitlab::#{service}"
  else
    include_recipe "gitlab::#{service}_disable"
  end
end
include_recipe "gitlab::database_migrations" if node['gitlab']['gitlab-rails']['enable']

# Always create logrotate folders and configs, even if the service is not enabled.
# https://gitlab.com/gitlab-org/omnibus-gitlab/issues/508
include_recipe "gitlab::logrotate_folders_and_configs"

# Configure Services
[
  "unicorn",
  "sidekiq",
  "gitlab-workhorse",
  "mailroom",
  "nginx",
  "remote-syslog",
  "logrotate",
  "bootstrap",
  "mattermost",
  "gitlab-pages",
  "registry"
].each do |service|
  if node["gitlab"][service]["enable"]
    include_recipe "gitlab::#{service}"
  else
    include_recipe "gitlab::#{service}_disable"
  end
end

# Deprecated in favor of gitlab-workhorse since 8.2
runit_service "gitlab-git-http-server" do
  action :disable
end
