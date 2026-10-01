require "rails_helper"

# Guards the "no database" architecture so a default-Rails convention cannot creep back in.
RSpec.describe "Database-free application" do
  let(:root) { Rails.root }

  it "does not load Active Record" do
    expect(defined?(ActiveRecord::Base)).to be_nil
    expect(Rails.application.config).not_to respond_to(:active_record)
  end

  it "loads only the Rails frameworks it needs" do
    expect(defined?(ActiveJob::Base)).to be_nil
    expect(defined?(ActionMailer::Base)).to be_nil
    expect(defined?(ActiveStorage::Blob)).to be_nil
    expect(defined?(ActionCable::Server::Base)).to be_nil
  end

  it "has no database configuration, schema, migrations, or Active Record tasks" do
    %w[config/database.yml db lib/tasks/db.rake].each do |path|
      expect(root.join(path)).not_to exist, path
    end
  end

  it "bundles no database adapter, cache/queue backend, or worker gem" do
    locked = root.join("Gemfile.lock").read
    %w[pg mysql2 sqlite3 trilogy redis redis-client sidekiq resque delayed_job good_job solid_queue solid_cache solid_cable
       dalli memcached].each do |gem_name|
      expect(locked).not_to match(/^    #{Regexp.escape(gem_name)} \(/), gem_name
    end
  end

  it "ships no release-phase, worker, or database deployment command" do
    %w[Procfile Procfile.dev bin/jobs Dockerfile].each do |path|
      file = root.join(path)
      next unless file.exist?

      expect(file.read).not_to match(/db:|release:|worker:|sidekiq|solid_queue/i), path
    end
  end

  it "builds assets without Node" do
    expect(root.join("package.json")).not_to exist
    expect(root.join("node_modules")).not_to exist
    expect(Rails.application.config.assets).to respond_to(:paths) # Propshaft, no JS bundler
  end
end
