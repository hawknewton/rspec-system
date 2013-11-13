require 'rspec-system/node_set/base'
require 'fog'

module RSpecSystem
  class NodeSet::Openstack < NodeSet::Base
    PROVIDER_TYPE = 'openstack'
    attr_accessor :vmconf

    STR_CONFIG = [
      :node_timeout,
      :username,
      :flavor,
      :image,
      :endpoint,
      :keypair_name,
      :ssh_username,
      :network_name,
      :private_key,
      :api_key
    ]

    def initialize(name, config, custom_prefabs_path, options)
      super
      @vmconf = read_config
      @now = Time.now.strftime '%Y%m%d-%H:%M:%S.%L'
      RSpec.configuration.rs_storage[:nodes] ||= {}
    end

    def launch
      nodes.each do |k,v|
        storage = RSpec.configuration.rs_storage[:nodes][k] ||= {}
        options = {
          flavor_ref: flavor.id,
          image_ref: image.id,
          name: "#{k}-#{@now}",
          key_name: vmconf[:keypair_name]
        }
        options[:nics] = [{'net_id' => nic.id}] if vmconf[:network_name]
        log.info "Launching openstack instance #{k}"
        log.info "options: #{options.inspect}"
        log.info "----------------------------"
        result = compute.servers.create options
        storage[:server] = result
      end
    end
    def connect; end
    def teardown; end

    def compute
      @compute || @compute = Fog::Compute.new({
        provider: :openstack,
        openstack_username: vmconf[:username],
        openstack_api_key: vmconf[:api_key],
        openstack_auth_url: vmconf[:endpoint],
      })
    end

    def network
      @network || @network = Fog::Network.new({
        provider: :openstack,
        openstack_username: vmconf[:username],
        openstack_api_key: vmconf[:api_key],
        openstack_auth_url: vmconf[:endpoint],
      })
    end
    private

    def flavor
      compute.flavors.find { |x| x.name == vmconf[:flavor] }
    end

    def image
      compute.images.find { |x| x.name == vmconf[:image] }
    end

    def nic
      network.networks.find { |x| x.name == vmconf[:network_name] }
    end

    def nics
    end

    def read_config
      conf = {}
      ENV.keys.keep_if { |k| k =~ /^RS_OPENSTACK_/}.each do |k|
        var = k.sub(/^RS_OPENSTACK_/, '').downcase.to_sym
        conf[var] = ENV[k] if ([var] & STR_CONFIG).any?
      end
      conf[:node_timeout] = conf[:node_timeout].to_i unless conf[:node_timeout].nil?
      conf
    end
  end
end
