require "rails_helper"
require "yaml"
require "open3"
require "ipaddr"

# Guards the invariants of the Kamal 2 / Docker deployment without snapshotting whole files.
RSpec.describe "Deployment configuration" do
  let(:root) { Rails.root }
  let(:deploy) { YAML.safe_load_file(root.join("config/deploy.yml")) }
  let(:dockerfile) { root.join("Dockerfile").read }
  let(:dockerignore) { root.join(".dockerignore").read.lines.map(&:strip).reject { |l| l.empty? || l.start_with?("#") } }
  let(:secret_name) { /KEY|PASSWORD|SECRET|TOKEN/ }

  def git_ignored?(path)
    _out, status = Open3.capture2e("git", "check-ignore", "-q", path, chdir: root.to_s)
    status.success?
  end

  describe "config/deploy.yml" do
    it "describes one web server and nothing else" do
      expect(deploy["service"]).to eq("decision-lens")
      expect(deploy["servers"].keys).to eq([ "web" ])
      expect(deploy["servers"]["web"].length).to eq(1)
      expect(deploy.keys & %w[accessories volumes asset_path boot hooks_path aliases]).to be_empty
      expect(deploy["servers"].values.flatten.join).not_to match(/worker|job/i)
    end

    it "uses a private-capable image on ghcr.io built for amd64" do
      expect(deploy["registry"]["server"]).to eq("ghcr.io")
      expect(deploy["image"]).to match(%r{\A[a-z0-9-]+/decision-lens\z})
      expect(deploy["builder"]["arch"]).to eq("amd64")
    end

    it "serves HTTPS through kamal-proxy with the /up health check on the app port" do
      proxy = deploy["proxy"]

      expect(proxy["ssl"]).to be true
      expect(proxy["app_port"]).to eq(3000)
      expect(proxy["healthcheck"]["path"]).to eq(AllowedHosts::HEALTH_CHECK_PATH)
      expect(proxy["forward_headers"]).to be true
      expect(proxy["host"]).to be_present
    end

    it "targets one valid public IPv4 server address" do
      address = deploy["servers"]["web"].first
      ip = IPAddr.new(address)

      expect(address).to match(/\A\d{1,3}(\.\d{1,3}){3}\z/)
      expect(ip).to be_ipv4
      expect([ ip.private?, ip.loopback?, ip.link_local? ]).to all(be false)
      expect(IPAddr.new("0.0.0.0/8").include?(ip)).to be false
      expect(IPAddr.new("100.64.0.0/10").include?(ip)).to be false
      expect(IPAddr.new("192.0.2.0/24").include?(ip)).to be false
      expect(IPAddr.new("224.0.0.0/3").include?(ip)).to be false
    end

    it "serves the production hostname, and APP_HOSTS matches proxy.host exactly" do
      expect(deploy["proxy"]["host"]).to eq("lens.juanmoredemo.com")
      expect(deploy["env"]["clear"]["APP_HOSTS"]).to eq(deploy["proxy"]["host"])
      expect(AllowedHosts.parse(deploy["env"]["clear"]["APP_HOSTS"]).hosts).to eq([ "lens.juanmoredemo.com" ])
    end

    it "contains no REPLACE_ME placeholder" do
      expect(root.join("config/deploy.yml").read).not_to include("REPLACE_ME")
    end

    it "sets the documented non-secret production values" do
      clear = deploy["env"]["clear"]

      expect(clear).to include(
        "AI_PROVIDER" => "typesafe",
        "TYPESAFE_MODEL" => "jev-latest",
        "TYPESAFE_BASE_URL" => "https://api.typesafe.ai",
        "AI_TIMEOUT_SECONDS" => 10,
        "ANALYSES_PER_HOUR" => 100,
        "FAILED_LOGINS_PER_15_MINUTES" => 10,
        "RAILS_MAX_THREADS" => 2,
        "PORT" => 3000,
        "RAILS_LOG_LEVEL" => "info"
      )
    end

    it "passes exactly the five secrets by name and never as values" do
      expect(deploy["env"]["secret"]).to match_array(%w[SECRET_KEY_BASE DEMO_USERNAME DEMO_PASSWORD TYPESAFE_API_KEY])
      expect(deploy["registry"]["password"]).to eq([ "KAMAL_REGISTRY_PASSWORD" ])
    end

    it "keeps every secret-looking name out of the clear environment" do
      expect(deploy["env"]["clear"].keys.grep(secret_name)).to be_empty
    end

    it "keeps clear environment values free of credential-looking strings" do
      deploy["env"]["clear"].each_value do |value|
        expect(value.to_s).not_to match(/\A[A-Za-z0-9+\/=_-]{32,}\z/)
        expect(value.to_s).not_to match(/Bearer |sk-|ghp_/)
      end
    end

    it "retains few old containers on the small disk" do
      expect(deploy["retain_containers"]).to be_between(1, 5)
    end
  end

  describe ".kamal/secrets.example" do
    let(:lines) { root.join(".kamal/secrets.example").read.lines.map(&:strip).reject { |l| l.empty? || l.start_with?("#") } }

    it "lists the five secrets as shell-variable references with no values" do
      expect(lines.map { |l| l.split("=", 2).first }).to match_array(%w[KAMAL_REGISTRY_PASSWORD SECRET_KEY_BASE DEMO_USERNAME DEMO_PASSWORD TYPESAFE_API_KEY])
      lines.each do |line|
        name, value = line.split("=", 2)
        expect(value).to eq("$#{name}")
      end
    end

    it "is trackable, while real secret files are ignored by Git" do
      expect(git_ignored?(".kamal/secrets.example")).to be false
      expect(git_ignored?(".kamal/secrets")).to be true
      expect(git_ignored?(".kamal/secrets.production")).to be true
      expect(git_ignored?(".env")).to be true
    end
  end

  describe "Dockerfile" do
    let(:stages) { dockerfile.scan(/^FROM .+ AS (\w+)/i).flatten }

    it "is multi-stage and uses the Ruby version in .ruby-version" do
      expect(dockerfile.scan(/^FROM /i).length).to be >= 3
      expect(stages).to include("base", "build")
      expect(dockerfile[/^ARG RUBY_VERSION=(\S+)/, 1]).to eq(root.join(".ruby-version").read.strip.delete_prefix("ruby-"))
    end

    it "installs production gems only" do
      expect(dockerfile).to match(/BUNDLE_WITHOUT="development:test"/)
      expect(dockerfile).to match(/BUNDLE_DEPLOYMENT="1"/)
    end

    it "precompiles bootsnap and assets, using the dummy secret only for the asset step" do
      expect(dockerfile).to include("bootsnap precompile --gemfile")
      expect(dockerfile).to include("bootsnap precompile app/ lib/")
      dummy_lines = dockerfile.lines.grep(/SECRET_KEY_BASE_DUMMY/)
      expect(dummy_lines.length).to eq(1)
      expect(dummy_lines.first).to include("assets:precompile")
      expect(dockerfile).not_to match(/^ENV[^\n]*SECRET_KEY_BASE/)
    end

    it "runs as a non-root user and starts Puma on port 3000" do
      user = dockerfile.lines.grep(/^USER /).last
      expect(user).to match(/USER 1000:1000/)
      expect(dockerfile).to match(/^EXPOSE 3000$/)
      expect(dockerfile).to match(/^CMD \[.*"server".*\]/)
      expect(dockerfile.index("USER 1000:1000")).to be < dockerfile.index("CMD [")
    end

    describe "runtime file permissions" do
      # Final-stage instructions only: comments removed, backslash-continued lines joined.
      let(:final_stage) do
        dockerfile.split(/^FROM /i).last.lines.reject { |line| line.strip.start_with?("#") }.join.gsub(/\\\n/, " ")
      end

      it "makes /rails readable and searchable for everyone before switching to the unprivileged user" do
        chmod_at = final_stage.index("chmod -R a+rX /rails")

        expect(chmod_at).not_to be_nil
        expect(chmod_at).to be > final_stage.index("COPY --from=build /rails /rails")
        expect(chmod_at).to be < final_stage.index("USER 1000:1000")
      end

      it "only adds read/search permission, never write or broader modes" do
        chmods = final_stage.scan(/chmod\s+[^&|;\n]+/).map(&:strip)

        expect(chmods).to eq([ "chmod -R a+rX /rails" ])
      end

      it "does not recursively chown the application source to the runtime user" do
        expect(final_stage).not_to match(%r{chown\s+-R[^&|;\n]*(/rails|\s\.(\s|$)|\s\*)})
      end

      it "keeps log/ and tmp/ as the only runtime-owned (writable) directories" do
        chowns = final_stage.scan(/chown\s+[^&|;\n]+/).map(&:strip)

        expect(chowns).to eq([ "chown -R rails:rails log tmp" ])
      end
    end

    it "has no database, cache, queue, or release-step commands" do
      expect(dockerfile).not_to match(/db:|sqlite|postgres|libpq|mysql|redis|sidekiq|memcached|solid_queue|thrust|entrypoint/i)
    end

    it "keeps compilers out of the final stage" do
      final_stage = dockerfile.split(/^FROM /i).last

      expect(final_stage).not_to match(/build-essential|pkg-config|libyaml-dev/)
    end

    it "never copies environment files or keys into the image" do
      expect(dockerfile).not_to match(/\.env|master\.key|\.kamal|credentials/)
    end
  end

  describe ".dockerignore" do
    it "keeps secrets, history, logs, and local artifacts out of the build context" do
      expect(dockerignore).to include(".git", ".env", ".env.*", ".kamal", "config/*.key", "log/*", "tmp/*")
    end

    it "keeps log and tmp directories that the image needs to chown" do
      expect(dockerignore).to include("!log/.keep", "!tmp/.keep")
      expect(root.join("log/.keep")).to exist
      expect(root.join("tmp/.keep")).to exist
    end
  end

  describe "bin/kamal" do
    it "exists and Kamal stays out of the production bundle" do
      expect(root.join("bin/kamal")).to exist
      gemfile = root.join("Gemfile").read
      non_production_group = gemfile[/group :development, :test do.*?^end/m].to_s

      expect(non_production_group).to include('gem "kamal"')
    end
  end

  describe "no leftover Koyeb instructions" do
    it "mentions Koyeb nowhere in code, specs, or deployment documentation" do
      files = %w[README.md Dockerfile config/deploy.yml config/puma.rb .env.example lib/allowed_hosts.rb] +
              Dir.glob("docs/**/*.md", base: root.to_s)
      offenders = files.select { |file| root.join(file).read.match?(/koyeb/i) }

      expect(offenders).to be_empty
    end
  end
end
