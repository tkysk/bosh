require 'spec_helper'
require 'bosh/stemcell/archive'
require 'bosh/stemcell/aws/ami_collection'

module Bosh::Stemcell::Aws
  describe AmiCollection  do
    subject do
      AmiCollection.new(
        stemcell,
        regions,
        virtualization_type,
        'fake-access-key',
        'fake-secret-access-key',
        'fake-bucket-name',
        nil
      )
    end

    let(:stemcell) do
      instance_double('Bosh::Stemcell::Archive').tap do |s|
        allow(s).to receive(:extract).and_yield('/foo/bar', {
          'cloud_properties' => { 'ami' => '' }
        })
      end
    end

    let(:regions) { ['foo', 'bar', 'baz'] }

    let(:virtualization_type) { "hvm" }

    let(:image) { instance_double('AWS::EC2::Image', :"public=" => nil, :name => 'fake-ami-id', :tags => nil) }
    let(:ec2) { instance_double('AWS::EC2', images: { 'fake-ami-id' => image }) }
    let(:region_ami_mapping) { regions.inject({}) { |acc, region| acc[region] = "fake-ami-id-#{region}"; acc } }
    # let(:cpi) { instance_double('Bosh::AwsCloud::Cloud', ec2: ec2, publish_stemcell: region_ami_mapping) }

    describe '#produce_amis' do
      # before { allow(Bosh::Clouds::Provider).to receive(:create).and_return(cpi) }

      # it 'creates a new cpi with the appropriate properties' do
      #   expect(Bosh::Clouds::Provider).to receive(:create).with({
      #     'plugin' => 'aws',
      #     'properties' => {
      #       'aws' =>       {
      #         'default_key_name' => 'fake',
      #         'region' => regions.first,
      #         'access_key_id' => 'fake-access-key',
      #         'secret_access_key' => 'fake-secret-access-key'
      #       },
      #       'registry' => {
      #         'endpoint' => 'http://fake.registry',
      #         'user' => 'fake',
      #         'password' => 'fake'
      #       }
      #     }
      #   }, 'fake-director-uuid').and_return(cpi)
      #
      #   subject.produce_amis
      # end
      #
      it 'creates a new ami and makes it public' do
        expect(image).to receive(:public=).with(true)
        subject.produce_amis
      end

      it 'returns the ami id' do
        expect(subject.produce_amis).to eq({regions.first => "fake-ami-id"})
      end

      context 'when virtualization type is passed' do
        let(:virtualization_type) { "hvm" }

        it 'creates the stemcell with the appropriate arguments' do
          expect(cpi).to receive(:create_stemcell) do |image_path, cloud_properties|
            expect(image_path).to eq('/foo/bar/image')
            expect(cloud_properties['virtualization_type']).to eq(virtualization_type)
            'fake-ami-id'
          end

          subject.produce_amis
        end
      end

      context 'when publishing to the China region' do
        let(:regions) { ['cn-north-1'] }
        let(:env) do
          {
            'BOSH_AWS_CHINA_ACCESS_KEY_ID' => 'fake-access-key',
            'BOSH_AWS_CHINA_SECRET_ACCESS_KEY' => 'fake-secret-access-key',
          }
        end

        before { stub_const('ENV', env) }

        before { allow(Logger).to receive(:new) }

        it 'creates a new cpi with the appropriate properties' do
          expect(Bosh::Clouds::Provider).to receive(:create).with({
                'plugin' => 'aws',
                'properties' => {
                  'aws' =>       {
                    'default_key_name' => 'fake',
                    'region' => 'cn-north-1',
                    'access_key_id' => 'fake-access-key',
                    'secret_access_key' => 'fake-secret-access-key'
                  },
                  'registry' => {
                    'endpoint' => 'http://fake.registry',
                    'user' => 'fake',
                    'password' => 'fake'
                  }
                }
              }, 'fake-director-uuid').and_return(cpi)

          subject.produce_amis
        end

        it 'creates a new ami and makes it public' do
          expect(image).to receive(:public=).with(true)
          subject.produce_amis
        end

        it 'returns the ami id' do
          expect(subject.produce_amis).to eq({"cn-north-1" => "fake-ami-id"})
        end

      end

      context 'when no virtualization type is passed' do
        let(:virtualization_type) { nil }

        it 'creates the stemcell with the appropriate arguments' do
          expect(cpi).to receive(:create_stemcell) do |image_path, cloud_properties|
            expect(image_path).to eq('/foo/bar/image')
            expect(cloud_properties['virtualization_type']).to eq('paravirtual')
            'fake-ami-id'
          end

          subject.produce_amis
        end
      end
    end
  end
end
