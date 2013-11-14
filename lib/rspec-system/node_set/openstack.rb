require 'net/ssh'
require 'net/scp'
require 'fog'
require 'rspec-system/node_set/base'

module RSpecSystem
  class NodeSet::Openstack < NodeSet::Base
    PROVIDER_TYPE = 'openstack'
    attr_accessor :env_conf

    CONFIG_KEYS = [
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

    ALLOWED_OPTIONS = [
      :node_timeout,
      :flavor_name,
      :image_name,
      :keypair_name,
      :network_name
    ]

    def initialize(name, config, custom_prefabs_path, options)
      super
      @env_conf = read_env
      @now = Time.now.strftime '%Y%m%d-%H:%M:%S.%L'
      RSpec.configuration.rs_storage[:nodes] ||= {}
    end

    def launch
      each_node do |name, node, storage, conf|
        options = {
          flavor_ref: conf.flavor.id,
          image_ref: conf.image.id,
          name: "#{name}-#{@now}",
          key_name: conf[:keypair_name]
        }
        options[:nics] = [{'net_id' => conf.network.id}] if conf[:network_name]
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
            raise if Time.new.to_i - before > conf[:node_timeout].to_i
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
        openstack_username: env_conf[:username],
        openstack_api_key: env_conf[:api_key],
        openstack_auth_url: env_conf[:endpoint],
      })
    end

    def network
      @network || @network = Fog::Network.new({
        provider: :openstack,
        openstack_username: env_conf[:username],
        openstack_api_key: env_conf[:api_key],
        openstack_auth_url: env_conf[:endpoint],
      })
    end

    def node_conf(name)
      o = (nodes[name].options || {}).inject({}) { |memo,(k,v)| memo[k.to_sym] = v; memo }
      conf = env_conf.merge o.reject { |k,v| !(ALLOWED_OPTIONS & [k]).any? }

      me = self
      [:flavor, :image, :network].each do |m|
        conf.define_singleton_method(m) do
          name = conf["#{m}_name".to_sym]
          me.log.info "Looking up #{m} #{name}"
          (me.send m == :network ? m : :compute).send("#{m}s").find { |x| x.name == name }
        end
      end

      conf
    end
    private
    def read_env
      ENV.inject({}) do |memo, (k, v)|
        if k =~ /^RS_OPENSTACK_(.+)/
          key = $1.downcase.to_sym
          memo[key] = v if ([key] & CONFIG_KEYS).any?
        end
        memo
      end
    end

    def each_node(&blk)
      nodes.each do |name, node|
        storage = RSpec.configuration.rs_storage[:nodes][name] ||= {}
        yield name, node, storage, node_conf(name)
      end
    end
  end
end
