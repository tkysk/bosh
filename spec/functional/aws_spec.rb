require 'spec_helper'

describe Bosh::Cli::Command::AWS do
  let(:aws) { subject }
  let(:default_config_filename) do
    File.expand_path(File.join(
      File.dirname(__FILE__), '..', '..', 'templates', 'aws_configuration_template.yml.erb'
    ))
  end

  before { aws.stub(:sleep) }

  describe 'command line tools' do
    describe 'aws generate micro_bosh' do
      let(:create_vpc_output_yml) { asset 'test-output.yml' }
      let(:route53_receipt_yml) { asset 'test-aws_route53_receipt.yml' }
      let(:micro_bosh_yaml) { Psych.load_file('micro_bosh.yml') }

      around do |test|
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            aws.create_micro_bosh_manifest(create_vpc_output_yml, route53_receipt_yml)
            test.run
          end
        end
      end

      it 'uses some of the normal director keys' do
        micro_bosh_yaml['name'].should == 'micro-dev102'
        micro_bosh_yaml['network']['vip'].should == '50.200.100.1'
        micro_bosh_yaml['network']['cloud_properties']['subnet'].should == 'subnet-4bdf6c26'
        micro_bosh_yaml['resources']['cloud_properties']['availability_zone'].should == 'us-east-1a'

        micro_bosh_yaml['cloud']['properties']['aws']['access_key_id'].should == '...'
        micro_bosh_yaml['cloud']['properties']['aws']['secret_access_key'].should == '...'
        micro_bosh_yaml['cloud']['properties']['aws']['region'].should == 'us-east-1'
      end

      it 'has a health manager username and password populated' do
        micro_bosh_yaml['apply_spec']['properties']['hm']['director_account']['user'].should == 'hm'
        micro_bosh_yaml['apply_spec']['properties']['hm']['director_account']['password'].should_not be_nil
      end
    end

    describe 'aws generate bosh' do
      let(:create_vpc_output_yml) { asset 'test-output.yml' }
      let(:route53_receipt_yml) { asset 'test-aws_route53_receipt.yml' }
      let(:bosh_rds_receipt_yml) { asset 'test-aws_rds_bosh_receipt.yml' }

      it 'generates required bosh deployment keys' do
        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            aws.stub(:target_required)
            aws.stub_chain(:director, :uuid).and_return('deadbeef')
            aws.create_bosh_manifest(create_vpc_output_yml, route53_receipt_yml, bosh_rds_receipt_yml)

            yaml = Psych.load_file('bosh.yml')

            yaml['name'].should == 'vpc-bosh-dev102'
            yaml['properties']['hm']['director_account']['user'].should == 'hm'
            yaml['properties']['hm']['director_account']['password'].should_not be_nil
          end
        end
      end
    end

    describe 'aws generate bat' do
      let(:create_vpc_output_yml) { asset 'test-output.yml' }
      let(:route53_receipt_yml) { asset 'test-aws_route53_receipt.yml' }

      it 'has the correct stemcell name' do
        aws.stub(:target_required)
        aws.stub_chain(:director, :uuid).and_return('deadbeef')

        Dir.mktmpdir do |dir|
          Dir.chdir(dir) do
            aws.create_bat_manifest(create_vpc_output_yml, route53_receipt_yml, 123, 'test-stemcell')
            yaml = Psych.load_file('bat.yml')
            expect(yaml['resource_pools'].first['stemcell']['name']).to eq 'test-stemcell'
            expect(yaml['properties']['stemcell']['name']).to eq 'test-stemcell'
          end
        end
      end
    end

    describe 'aws create' do
      let(:config_file) { asset 'create_all.yml' }
      let(:migrator) { double('Migrator') }

      around do |example|
        previous_env = ENV.to_hash

        ENV['BOSH_AWS_SECRET_ACCESS_KEY'] = 'fake secret access key'
        ENV['BOSH_AWS_ACCESS_KEY_ID'] = 'fake access key id'
        ENV['BOSH_VPC_SUBDOMAIN'] = 'fake vpc subdomain'
        ENV['BOSH_VPC_PRIMARY_AZ'] = 'fake az'
        ENV['BOSH_VPC_SECONDARY_AZ'] = 'fake secondary az'

        example.run

        previous_env.each { |k, v| ENV[k] = v }
      end

      it 'should run the migrations' do
        Bosh::Aws::Migrator.should_receive(:new).with(YAML.load_yaml_file(config_file)).and_return(migrator)
        migrator.should_receive(:migrate)
        aws.create config_file
      end

      it 'should default the configuration file when not passed in' do
        File.exist?(default_config_filename).should == true
        Bosh::Aws::Migrator.should_receive(:new).and_return(migrator)
        migrator.should_receive(:migrate)
        aws.create
      end
    end

    describe 'aws destroy' do
      before { Bosh::Aws::Destroyer.stub(:new).with(aws, config, rds_destroyer, vpc_destroyer).and_return(destroyer) }
      let(:destroyer) { instance_double('Bosh::Aws::Destroyer') }

      before { Bosh::Aws::RdsDestroyer.stub(:new).with(aws, config).and_return(rds_destroyer) }
      let(:rds_destroyer) { instance_double('Bosh::Aws::RdsDestroyer') }

      before { Bosh::Aws::VpcDestroyer.stub(:new).with(aws, config).and_return(vpc_destroyer) }
      let(:vpc_destroyer) { instance_double('Bosh::Aws::VpcDestroyer') }

      before { aws.stub(:load_config).with(config_file).and_return(config) }
      let(:config_file) { double('config_file') }
      let(:config) { { fake: 'config' } }

      it 'destroys the specified VPCs, RDS DBs, and S3 Volumes' do
        destroyer.should_receive(:ensure_not_production!).ordered
        destroyer.should_receive(:delete_all_elbs).ordered
        destroyer.should_receive(:delete_all_ec2).ordered
        destroyer.should_receive(:delete_all_ebs).ordered
        destroyer.should_receive(:delete_all_rds).ordered
        destroyer.should_receive(:delete_all_s3).ordered
        destroyer.should_receive(:delete_all_vpcs).ordered
        destroyer.should_receive(:delete_all_key_pairs).ordered
        destroyer.should_receive(:delete_all_elastic_ips).ordered
        destroyer.should_receive(:delete_all_security_groups).ordered
        destroyer.should_receive(:delete_all_route53_records).ordered
        aws.destroy(config_file)
      end
    end

    describe 'load_config' do
      let(:config_file) { double('config_file') }
      let(:config) { instance_double('Bosh::Aws::AwsConfig', configuration: 'fake_configuration') }

      context 'when a config file is provided' do
        it 'uses the provided file' do
          Bosh::Aws::AwsConfig.should_receive(:new).with(config_file).and_return(config)
          expect(aws.send(:load_config, config_file)).to eq('fake_configuration')
        end
      end

      context 'when a config file is not provided' do
        it 'uses a default config' do
          Bosh::Aws::AwsConfig.should_receive(:new).with(default_config_filename).and_return(config)
          expect(aws.send(:load_config)).to eq('fake_configuration')
        end
      end
    end

    describe 'aws destroy vpc' do
      let(:output_file) { asset 'test-output.yml' }

      it 'should delete the vpc and all its dependencies, and release the elastic ips' do
        fake_ec2 = double('ec2')
        fake_vpc = double('vpc')
        fake_dhcp_options = double('dhcp options')
        fake_route53 = double('route53')

        Bosh::Aws::EC2.stub(:new).and_return(fake_ec2)
        Bosh::Aws::VPC.stub(:find).with(fake_ec2, 'vpc-13724979').and_return(fake_vpc)
        Bosh::Aws::Route53.stub(:new).and_return(fake_route53)

        fake_vpc.stub(:dhcp_options).and_return(fake_dhcp_options)
        fake_vpc.stub(:instances_count).and_return(0)

        fake_vpc.should_receive :delete_security_groups
        fake_vpc.should_receive :delete_subnets
        fake_vpc.should_receive :delete_vpc
        fake_dhcp_options.should_receive :delete
        fake_ec2.should_receive(:internet_gateway_ids).and_return(['gw1id', 'gw2id'])
        fake_ec2.should_receive(:delete_internet_gateways).with(['gw1id', 'gw2id'])
        fake_ec2.should_receive(:remove_key_pair).with 'somenamez'
        fake_ec2.should_receive(:release_elastic_ips).with ['107.23.46.162', '107.23.53.76']
        fake_ec2.should_receive(:release_elastic_ips).with ['123.45.6.7']
        fake_ec2.should_receive(:release_elastic_ips).with ['123.45.6.8']
        fake_ec2.should_receive(:release_elastic_ips).with ['123.4.5.9']
        fake_route53.should_receive(:delete_record).with('*', 'cfdev.com')
        fake_route53.should_receive(:delete_record).with('micro', 'cfdev.com')
        fake_route53.should_receive(:delete_record).with('bosh', 'cfdev.com')
        fake_route53.should_receive(:delete_record).with('bat', 'cfdev.com')

        aws.send(:delete_vpc, output_file)
      end

      it 'should retry on AWS errors' do
        fake_ec2 = double('ec2')
        fake_vpc = double('vpc')
        fake_route_53 = double('route53')
        fake_dhcp_options = double('dhcp_options')

        Bosh::Aws::EC2.stub(:new).and_return(fake_ec2)
        Bosh::Aws::VPC.stub(:find).and_return(fake_vpc)
        Bosh::Aws::Route53.stub(:new).and_return(fake_vpc)

        fake_vpc.stub(:instances_count).and_return(0)
        fake_vpc.stub(:dhcp_options).and_return(fake_dhcp_options)
        fake_vpc.stub(:delete_security_groups)
        fake_vpc.stub(:delete_subnets)
        fake_vpc.stub(:delete_vpc)
        fake_vpc.stub(:remove_key_pair)
        fake_vpc.stub(:delete_record)

        fake_ec2.stub(:internet_gateway_ids)
        fake_ec2.stub(:delete_internet_gateways)
        fake_ec2.stub(:remove_key_pair)
        fake_ec2.stub(:release_elastic_ips)

        fake_dhcp_options.stub(:delete)

        aws.stub(aws_retry_wait_time: 0)

        fake_vpc.should_receive(:delete_security_groups).ordered.exactly(119).times.and_raise(::AWS::EC2::Errors::InvalidGroup::InUse)
        fake_vpc.should_receive(:delete_security_groups).ordered.once.and_return(true)
        aws.send(:delete_vpc, output_file)
      end

      context 'when there are instances running' do
        it "throws a nice error message and doesn't delete any resources" do
          fake_vpc = double('vpc')

          Bosh::Aws::EC2.stub(:new)
          Bosh::Aws::VPC.stub(:find).and_return(fake_vpc)

          fake_vpc.stub(:instances_count).and_return(1)
          fake_vpc.stub(:vpc_id).and_return('vpc-13724979')

          expect {
            fake_vpc.should_not_receive(:delete_security_groups)
            aws.send(:delete_vpc, output_file)
          }.to raise_error(Bosh::Cli::CliError, '1 instance(s) running in vpc-13724979 - delete them first')
        end
      end
    end

    describe 'aws destroy server certificates' do
      let(:config_file) { asset 'config.yml' }
      let(:fake_elb) { double('ELB', server_certificate_names: ['cf_router']) }

      before do
        Bosh::Aws::ELB.stub(:new).and_return(fake_elb)
      end

      context 'when non-interactive' do
        before do
          aws.should_receive(:confirmed?).and_return(true)
        end

        it 'should remove the key pairs' do
          fake_elb.should_receive(:delete_server_certificates).and_return(true)
          aws.send(:delete_server_certificates, config_file)
        end
      end

      context 'when interactive and bailing out' do
        before do
          aws.should_receive(:confirmed?).and_return(false)
        end

        it 'should not delete the key pairs' do
          fake_elb.should_not_receive(:delete_server_certificates)
          aws.send(:delete_server_certificates, config_file)
        end
      end
    end

    describe 'aws bootstrap micro' do
      subject(:aws) { described_class.new }
      let(:fake_bootstrap) { double('micro bosh bootstrap') }
      context 'interative' do
        before(:each) do
          aws.options[:non_interactive] = false
        end

        it 'prompts the user for admin password' do
          fake_bootstrap.should_receive(:start)
          Bosh::Aws::MicroBoshBootstrap.should_receive(:new).with(
            anything,
            kind_of(Hash)
          ).and_return(fake_bootstrap)
          aws.should_receive(:ask).and_return('username')
          aws.should_receive(:ask).and_return('password')

          fake_bootstrap.should_receive(:create_user).with('hm', anything).ordered
          fake_bootstrap.should_receive(:create_user).with('username', 'password').ordered

          aws.bootstrap_micro
        end
      end

      context 'non-interactive' do
        before(:each) do
          aws.options[:non_interactive] = true
        end

        it 'saves the randomly generated password??' do
          fake_bootstrap.should_receive(:start)
          Bosh::Aws::MicroBoshBootstrap.should_receive(:new).with(
            anything,
            kind_of(Hash)
          ).and_return(fake_bootstrap)

          fake_bootstrap.should_receive(:create_user).with('hm', anything).ordered
          fake_bootstrap.should_receive(:create_user).with('admin', anything).ordered

          aws.bootstrap_micro
        end
      end
    end
  end
end
