require 'bosh/dev/build'
require 'bosh/stemcell/archive'
require 'bosh/stemcell/aws/light_stemcell'

module Bosh::Dev
  class StemcellPublisher
    def self.for_candidate_build(bucket_name, primary_instance_bucket, primary_access_key, primary_secret_key, china_instance_bucket, china_access_id, china_instnace_secret)
      new(Build.candidate(bucket_name), primary_instance_bucket, primary_access_key, primary_secret_key, china_instance_bucket, china_access_id, china_instnace_secret)
    end

    def initialize(build,, primary_instance_bucket, primary_access_key, primary_secret_key, china_instance_bucket, china_access_id, china_instnace_secret)
      @build = build
      @primary_instance_bucket = primary_instance_bucket
      @primary_access_key = primary_access_key
      @primary_secret_key = primary_secret_key
      @china_instance_bucket = china_instance_bucket
      @china_access_id = china_access_id
      @china_instnace_secret = china_instnace_secret
    end

    def publish(stemcell_filename)
      stemcell = Bosh::Stemcell::Archive.new(stemcell_filename)
      publish_light_stemcell(stemcell) if stemcell.infrastructure == 'aws'
      @build.upload_stemcell(stemcell)
    end

    private

    def publish_light_stemcell(stemcell)
      primary_creds = {
        access_key_id: @primary_access_key,
        secret_access_key: @primary_secret_key,
        bucket_name: @primary_instance_bucket,
      }
      china_creds = {
        access_key_id: @primary_access_key,
        secret_access_key: @primary_secret_key,
        bucket_name: @primary_instance_bucket,
      }
      aws_light_stemcell_creator_config = {
        regions: {
          primary_creds => %w(us-east-1, us-west-1, uk-north-1),
          china_creds => ['cn-north-1']
        }
      }
      config_file = Tempfile.new(%w(aws_light_stemcell_creator_config .json'))
      config_file.write(aws_light_stemcell_creator_config.to_json)
      config_file.close



      do_stuff(stemcell, config_file.path)
      other_stemcell = make_hvm_stemcell(stemcell)
      do_stuff(stemcell, config_file.path)
    end

  end

  def make_hvm_stemcell(stemcell)

  end

  def do_stuff(stemcell, config_file)
    stemcell_name = File.basename(stemcell.path)
    Dir.tmpdir do |dir|
      light_stemcell_path = "#{dir}/light-#{stemcell_name}"
      `create-aws-light-stemcell -c #{config_file.path} #{stemcell.path} -o #{light_stemcell_path}`
      raise('failed') unless $?.exitstatus.zero?
      light_stemcell_stemcell = Bosh::Stemcell::Archive.new(light_stemcell_path)
      @build.upload_stemcell(light_stemcell_stemcell)
    end
  end
end
