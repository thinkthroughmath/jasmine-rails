require 'open3'

namespace :spec do
  def run_cmd(cmd)
    puts "$ #{cmd}"
    stdout = ""
    stderr = ""
    exit_status = Open3.popen3(cmd) {|i, o, e, t|
      stdout = o.gets(nil)
      stderr = e.gets(nil)
      t.value.to_i
    }
    if stderr
      raise "Error executing command: #{cmd}\n#{stderr}"
    end

    console_report, junit_report = stdout.split("ConsoleReporter finished")
    puts console_report

    if ENV["JENKINS"]
      report_dir = File.join(Rails.root, 'test', 'reports', ENV["TEST_TYPE"])
      FileUtils.mkdir_p(report_dir)
      junit_report.strip.split("\n\n").each do |report|
        lines = report.split("\n")
        filename = lines.shift
        File.open(File.join(report_dir, filename), 'w') do |f|
          f.puts lines.join("\n")
        end
      end
    end
  end

  desc "run test with phantomjs"
  task :javascript => :environment do
    original_debug_setting = Rails.application.config.assets.debug
    Rails.application.config.assets.debug = false
    require 'jasmine_rails/offline_asset_paths'
    if Rails::VERSION::MAJOR >= 4
      Sprockets::Rails::Helper.send :include, JasmineRails::OfflineAssetPaths
    else
      ActionView::AssetPaths.send :include, JasmineRails::OfflineAssetPaths
    end
    spec_filter = ENV['SPEC']
    app = ActionController::Integration::Session.new(Rails.application)
    path = JasmineRails.route_path
    app.get path, :console => 'true', :spec => spec_filter
    JasmineRails::OfflineAssetPaths.disabled = true
    raise "Jasmine runner at '#{path}' returned a #{app.response.status} error: #{app.response.message}" unless app.response.success?
    html = app.response.body
    runner_path = Rails.root.join('spec/tmp/runner.html')
    File.open(runner_path, 'w') {|f| f << html.gsub('/assets', './assets')}

    exit_status = run_cmd %{phantomjs "#{File.join(File.dirname(__FILE__), 'runner.js')}" "file://#{runner_path.to_s}?spec=#{spec_filter}"}
    Rails.application.config.assets.debug = original_debug_setting
    unless exit_status == 0
      raise "Non-zero exit status from running tests"
    end
  end

  # alias
  task :javascripts => :javascript
end
