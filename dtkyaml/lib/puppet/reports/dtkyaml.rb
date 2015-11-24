require 'puppet'
require 'yaml'
require 'fileutils'

Puppet::Reports.register_report(:dtkyaml) do

  desc "DTK YAML file reporter"

  def process
    #require 'debugger'; debugger
    output_dir = "/host_volume"
    output_file = "#{output_dir}/report.yml"
    FileUtils.mkdir_p output_dir
    File.open(output_file, 'w') {|f| f.write self.to_yaml } 
  end
end
