# frozen_string_literal: true
require_relative '../test_helper'

SingleCov.covered!

describe DeployGroup do
  let(:stage) { stages(:test_staging) }
  let(:environment) { environments(:production) }
  let(:deploy_group) { deploy_groups(:pod1) }

  def self.it_expires_stage(method)
    it "expires stages when #{method}" do
      stage.deploy_groups << deploy_group
      stage.update_column(:updated_at, 1.minute.ago)
      old = stage.updated_at.to_s(:db)
      deploy_group.send(method)
      stage.reload.updated_at.to_s(:db).wont_equal old
    end
  end

  describe '.enabled?' do
    it 'is enabled when DEPLOY_GROUP_FEATURE is present' do
      with_env DEPLOY_GROUP_FEATURE: "1" do
        DeployGroup.enabled?.must_equal true
      end
    end

    it 'is disabled when DEPLOY_GROUP_FEATURE is blank' do
      DeployGroup.enabled?.must_equal false
    end
  end

  describe '#deploys' do
    it 'finds deploys from all stages that go through this group' do
      deploy_group.deploys.must_equal [deploys(:succeeded_production_test)]
    end
  end

  describe '.new' do
    it 'saves' do
      deploy_group = DeployGroup.new(name: 'test deploy name', environment: environment)
      assert_valid(deploy_group)
    end
  end

  describe 'validations' do
    let(:deploy_group) { DeployGroup.new(name: 'sfsdf', environment: environment) }

    it 'is valid' do
      assert_valid deploy_group
    end

    it 'require a name' do
      deploy_group.name = nil
      refute_valid(deploy_group)
    end

    it 'require an environment' do
      deploy_group.environment = nil
      refute_valid(deploy_group)
    end

    it 'require a unique name' do
      deploy_group.name = deploy_groups(:pod1).name
      refute_valid(deploy_group)
    end

    describe 'env values' do
      it 'fills empty env values' do
        deploy_group.env_value = ''
        assert_valid(deploy_group)
      end

      it 'does not allow invalid env values' do
        deploy_group.env_value = 'no oooo'
        refute_valid(deploy_group)
      end

      it 'does not allow env values that start weird' do
        deploy_group.env_value = '-nooo'
        refute_valid(deploy_group)
      end

      it 'does not allow env values that start weird' do
        deploy_group.env_value = '-nooo'
        refute_valid(deploy_group)
      end

      it 'does not allow env values that end weird' do
        deploy_group.env_value = 'nooo-'
        refute_valid(deploy_group)
      end

      it 'allows :' do
        deploy_group.env_value = 'y:es'
        assert_valid(deploy_group)
      end
    end
  end

  it 'queried by environment' do
    env = Environment.create!(name: 'env666')
    dg1 = DeployGroup.create!(name: 'Pod666', environment: env)
    dg2 = DeployGroup.create!(name: 'Pod667', environment: env)
    DeployGroup.create!(name: 'Pod668', environment: environment)
    env.deploy_groups.sort.must_equal [dg1, dg2].sort
  end

  describe "#initialize_env_value" do
    it 'prefils env_value' do
      DeployGroup.create!(name: 'Pod666 - the best', environment: environment).env_value.must_equal 'pod666-the-best'
    end

    it 'can set env_value' do
      DeployGroup.create!(name: 'Pod666 - the best', env_value: 'pod:666', environment: environment).env_value.
        must_equal 'pod:666'
    end
  end

  describe '#natural_order' do
    it "sorts naturally" do
      list = ['a11', 'a1', 'a22', 'b1', 'a12', 'a9']
      sorted = list.map { |n| DeployGroup.new(name: n) }.sort_by(&:natural_order).map(&:name)
      sorted.must_equal ['a1', 'a9', 'a11', 'a12', 'a22', 'b1']
    end
  end

  it_expires_stage :save
  it_expires_stage :destroy
  it_expires_stage :soft_delete

  describe "#destroy_deploy_groups_stages" do
    let(:deploy_group) { deploy_groups(:pod100) }

    it 'deletes deploy_groups_stages on destroy' do
      assert_difference 'DeployGroupsStage.count', -1 do
        deploy_group.destroy!
      end
    end
  end

  describe "#template_stages" do
    let(:deploy_group) { deploy_groups(:pod100) }

    it "returns all template_stages for the deploy_group" do
      refute deploy_group.template_stages.empty?
    end
  end

  describe "#validate_vault_server_has_same_environment" do
    let(:server) { Samson::Secrets::VaultServer.create!(name: 'a', address: 'http://a.com', token: 't') }

    before do
      Samson::Secrets::VaultServer.any_instance.stubs(:validate_cert)
      Samson::Secrets::VaultServer.any_instance.stubs(:validate_connection)
      deploy_groups(:pod1).update_attributes!(vault_server: server)
      server.reload
    end

    it "is valid when vault servers have exclusive environments" do
      assert deploy_groups(:pod2).update_attributes(vault_server: server)
    end

    it "is valid when not changing invalid vault_server_id so nested saves do not blow up" do
      deploy_groups(:pod100).update_column(:vault_server_id, server.id)
      deploy_groups(:pod100).save!
    end

    it "is invalid when vault servers mix production and non-production deploy groups" do
      refute deploy_groups(:pod100).update_attributes(vault_server: server)
    end

    it "is valid for 2 different environments, as long as they're both production" do
      other_prod_env = Environment.create!(name: 'Other prod', production: true)
      deploy_group = DeployGroup.create(name: 'Another group', environment: other_prod_env, vault_server: server)
      assert deploy_group.valid?
    end
  end
end
