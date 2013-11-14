require 'net/ssh'
require 'net/scp'
require 'fog'
require 'rspec-system/node_set/base'

module RSpecSystem
  class NodeSet::Openstack < NodeSet::Base
    PROVIDER_TYPE = 'openstack'
    attr_accessor :vmconf

    STR_CONFIG = [
      :node_timeout,
      :username,
      :flavor_name,
      :image_name,
      :endpoint,
      :keypair_name,
      :network_name,
      :ssh_keys,
      :api_key
    ]

    def initialize(name, config, custom_prefabs_path, options)
      super
      @vmconf = read_config
      @now = Time.now.strftime '%Y%m%d-%H:%M:%S.%L'
      RSpec.configuration.rs_storage[:nodes] ||= {}
    end

    def launch
      each_node do |name, node, storage, conf|
        options = {
          flavor_ref: flavor.id,
          image_ref: image.id,
          name: "#{name}-#{@now}",
          key_name: conf[:keypair_name]
        }
        options[:nics] = [{'net_id' => nic.id}] if vmconf[:network_name]
        log.info "Launching openstack instance #{name}"
        result = compute.servers.create options
        storage[:server] = result
      end
    end

    def connect
      each_node do |name, node, storage, conf|
        server = storage[:server]
        before = Time.new.to_i
        while true
          begin
            server.wait_for(5) { ready? }
            break
          rescue ::Fog::Errors::TimeoutError
            raise if Time.new.to_i - before > vmconf[:node_timeout]
            log.info "Timeout connecting to instance, trying again..."
          end
        end

        chan = ssh_connect(:host => name, :user => 'root', :net_ssh_options => {
          keys: conf[:ssh_keys].split(':'),
          host_name: server.addresses[conf[:network_name]].first['addr'],
          paranoid: false
        })
        storage[:ssh] = chan
      end
    end

    def teardown
      each_node do |name, node, storage, conf|
        server = storage[:server]
        log.info "Destroying server #{server.name}"
        server.destroy
      end
    end

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
      compute.flavors.find { |x| x.name == vmconf[:flavor_name] }
    end

    def image
      compute.images.find { |x| x.name == vmconf[:image_name] }
    end

    def nic
      network.networks.find { |x| x.name == vmconf[:network_name] }
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

    def each_node(&blk)
      nodes.each do |name, node|
        storage = RSpec.configuration.rs_storage[:nodes][name] ||= {}
        yield name, node, storage, vmconf
      end
    end
  end
end
