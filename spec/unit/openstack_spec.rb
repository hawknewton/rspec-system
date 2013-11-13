require 'spec_helper'
require 'rspec-system/node_set/openstack'

describe RSpecSystem::NodeSet::Openstack do
  subject { described_class.new(setname, config, custom_prefabs_path, options) }

  let(:setname) { 'set name' }
  let(:config) do
    {
      'nodes' => {
        'main-test1' => { 'prefab' => 'centos-64-x64' },
        'main-test2' => { 'prefab' => 'centos-59-x64' }
      }
    }
  end

  let(:custom_prefabs_path) { '' }
  let(:options) { { } }
  let(:api_key) { 'test-api_key' }
  let(:node_timeout) { 120 }
  let(:username) { 'test-username' }
  let(:image_name) { 'test-image_name' }
  let(:flavor_name) { 'test-flavor_name' }
  let(:endpoint) { 'http://token.url/tokens' }
  let(:keypair_name) { 'test-keypair_name' }
  let(:ssh_username) { 'test-ssh_username' }
  let(:network_name) { 'test-network_name' }
  let(:private_key) { 'test-private_key' }

  let(:env_vars) do
    {
      'RS_OPENSTACK_NODE_TIMEOUT' => node_timeout,
      'RS_OPENSTACK_USERNAME'     => username,
      'RS_OPENSTACK_API_KEY'      => api_key,
      'RS_OPENSTACK_IMAGE'        => image_name,
      'RS_OPENSTACK_FLAVOR'       => flavor_name,
      'RS_OPENSTACK_ENDPOINT'     => endpoint,
      'RS_OPENSTACK_KEYPAIR_NAME' => keypair_name,
      'RS_OPENSTACK_SSH_USERNAME' => ssh_username,
      'RS_OPENSTACK_NETWORK_NAME' => network_name,
      'RS_OPENSTACK_PRIVATE_KEY'  => private_key
    }
  end

  let(:rs_storage) do
    { }
  end

  let(:log) do
    log = stub :log
    log.stubs :info
    log
  end

  before do
    env_vars.each { |k,v| ENV[k] = v.to_s }
    RSpec.configuration.stubs(:rs_storage).returns rs_storage
    described_class.any_instance.stubs(:log).returns log
  end

  it 'should have the PROVIDER_TYPE openstack' do
    expect(described_class::PROVIDER_TYPE).to eq 'openstack'
  end

  it 'should initialize rs_storage' do
    subject
    expect(RSpec.configuration.rs_storage).to eq rs_storage
  end

  describe '#vmconf' do
    subject { described_class.new(setname, config, custom_prefabs_path, options).vmconf }
    context 'given env config variables' do

      it 'should read node_timeout from the environment' do
        expect(subject[:node_timeout]).to eq node_timeout
      end

      it 'should read username from the environment' do
        expect(subject[:username]).to eq username
      end

      it 'should read flavor from the environment' do
        expect(subject[:flavor]).to eq flavor_name
      end

      it 'should read image from the environment' do
        expect(subject[:image]).to eq image_name
      end

      it 'should read endpoint url from the environment' do
        expect(subject[:endpoint]).to eq endpoint
      end

      it 'should read keypair name from the environment' do
        expect(subject[:keypair_name]).to eq keypair_name
      end

      it 'should read ssh username from the environment' do
        expect(subject[:ssh_username]).to eq ssh_username
      end

      it 'should read network name from the environment' do
        expect(subject[:network_name]).to eq network_name
      end

      it 'should read private key from the environment' do
        expect(subject[:private_key]).to eq private_key
      end

      it 'should read api key from the environment' do
        expect(subject[:api_key]).to eq api_key
      end
    end
  end

  describe '#compute' do
    subject { described_class.new(setname, config, custom_prefabs_path, options).compute }
    let(:connection) { Object.new }

    it 'should retrieve connection to openstack compute' do
      Fog::Compute.expects(:new).with({
        provider: :openstack,
        openstack_username: username,
        openstack_api_key: api_key,
        openstack_auth_url: endpoint,
      }).returns connection
      expect(subject).to equal connection
    end

    it 'should cache openstack connections' do
      Fog::Compute.expects(:new).with({
        provider: :openstack,
        openstack_username: username,
        openstack_api_key: api_key,
        openstack_auth_url: endpoint,
      }).once.returns connection
      c = described_class.new(setname, config, custom_prefabs_path, options)
      c.compute
      c.compute
    end
  end

  describe '#network' do
    subject { described_class.new(setname, config, custom_prefabs_path, options).network }
    let(:connection) { Object.new }

    it 'should retrieve connection to openstack network' do
      Fog::Network.expects(:new).with({
        provider: :openstack,
        openstack_username: username,
        openstack_api_key: api_key,
        openstack_auth_url: endpoint,
      }).returns connection
      expect(subject).to equal connection
    end

    it 'should cache connections' do
      Fog::Network.expects(:new).with({
        provider: :openstack,
        openstack_username: username,
        openstack_api_key: api_key,
        openstack_auth_url: endpoint,
      }).once.returns connection
      c = described_class.new(setname, config, custom_prefabs_path, options)
      c.network
      c.network
    end
  end

  describe '#launch' do
    subject { described_class.new(setname, config, custom_prefabs_path, options) }

    let(:compute) do
      stub({
        flavors: [ stub(id: flavor_id, name: flavor_name) ],
        images: [ stub(id: image_id, name: image_name) ],
        servers: mock('servers')
      })
    end

    let(:create_returns) do
      { 'id' => machine_id }
    end

    let(:network) do
      stub(networks: [ stub(id: network_id, name: network_name) ])
    end

    let(:flavor_id) { 'flavor_123' }
    let(:image_id) { 'image_123' }
    let(:network_id) { 'network_123' }
    let(:machine_id) { 'machine_123' }

    before do
      compute.servers.stubs(:create).returns create_returns
      subject.stubs(:compute).returns compute
      subject.stubs(:network).returns network
    end

    it 'should use the node\'s name' do
      num = 1
      compute.servers.expects(:create).with do |options|
        expect(options[:name]).to match /^main-test#{num}-.+/
        num += 1
      end.twice.returns create_returns
      subject.launch
    end

    it 'should lookup the flavor' do
      compute.servers.expects(:create).twice.with do |options|
        expect(options[:flavor_ref]).to eq flavor_id
      end.returns create_returns
      subject.launch
    end

    it 'should lookup the image' do
      compute.servers.expects(:create).twice.with do |options|
        expect(options[:image_ref]).to eq image_id
      end.returns create_returns
      subject.launch
    end

    it 'should use the correct ssh keypair name' do
      compute.servers.expects(:create).twice.with do |options|
        expect(options[:key_name]).to eq keypair_name
      end.returns create_returns
      subject.launch
    end

    it 'should use the correct network id' do
      compute.servers.expects(:create).twice.with do |options|
        nics = options[:nics]
        expect(nics[0]['net_id']).to eq network_id
      end.returns create_returns
      subject.launch
    end

    it 'should assign server to rs_storage' do
      subject.launch
      expect(rs_storage[:nodes]['main-test1'][:server]).to equal create_returns
    end
  end
end
