require 'rake/file_utils'
require 'yaml'
require 'common/deep_copy'
require 'bosh/stemcell/aws/ami_collection'
require 'bosh/stemcell/aws/region'

module Bosh::Stemcell::Aws
  HVM_VIRTUALIZATION = 'hvm'

  class LightStemcell
    def initialize(stemcell, virtualization_type, regions, access_key_id, secret_access_key_id, bucket_name)
      @stemcell = stemcell
      @virtualization_type = virtualization_type
      @regions = regions
      @access_key_id = ENV['BOSH_AWS_ACCESS_KEY_ID']
      @secret_access_key = ENV['BOSH_AWS_SECRET_ACCESS_KEY']
      @bucket_name = ENV['BOSH_AWS_IMPORT_INSTANCE_BUCKET_NAME']
    end

    def write_archive
      @stemcell.extract(exclude: 'image') do |extracted_stemcell_dir|
        Dir.chdir(extracted_stemcell_dir) do
          FileUtils.touch('image', verbose: true)
          light_maifest = Bosh::Common::DeepCopy.copy(@stemcell.manifest)
          light_maifest['name'] = adjust_hvm_name(manifest['name'])
          light_maifest['cloud_properties']['name'] = adjust_hvm_name(manifest['cloud_properties']['name'])

          ami_collection = AmiCollection.new(@stemcell, @regions, @virtualization_type, @access_key_id, @secret_access_key, @bucket_name)

          # Light stemcell contains AMIs for all regions
          # so that CPI can pick one based on its configuration
          light_maifest['cloud_properties']['ami'] = ami_collection.produce_amis
          File.write('stemcell.MF', Psych.dump(light_maifest))
          Rake::FileUtilsExt.sh("sudo tar cvzf #{path} *")
        end
      end
    end

    def path
      stemcell_name = adjust_hvm_name(File.basename(@stemcell.path))
      File.join(File.dirname(@stemcell.path), "light-#{stemcell_name}")
    end

    private

    def adjust_hvm_name(name)
      @virtualization_type == HVM_VIRTUALIZATION ? name.gsub("xen", "xen-hvm") : name
    end
  end
end
