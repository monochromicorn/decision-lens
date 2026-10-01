# Parses the APP_HOSTS environment variable into Rails' host-authorization list.
#
# Format: comma-separated exact hostnames, e.g. "lens.example.com,www.example.com".
# Case is ignored and whitespace around entries is trimmed. Anything that is not a
# plain hostname (wildcards, leading dots, schemes, ports, paths, IP addresses,
# underscores, empty entries) is rejected rather than interpreted.
#
# Fail-closed: if nothing valid is configured, DENY_ALL becomes the only allowed
# host, so every request except the health check is refused. This never opens access.
module AllowedHosts
  HEALTH_CHECK_PATH = "/up".freeze
  DENY_ALL = "no-allowed-hosts-configured.invalid".freeze

  LABEL = /[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?/
  HOSTNAME = /\A(?=.{1,253}\z)#{LABEL}(?:\.#{LABEL})*\z/
  IPV4 = /\A\d+(?:\.\d+){3}\z/

  Result = Data.define(:hosts, :rejected_count) do
    def configured? = hosts.any?
  end

  module_function

  def parse(raw)
    entries = raw.to_s.split(",").map { |entry| entry.strip.downcase }
    valid, invalid = entries.partition { |entry| valid_hostname?(entry) }
    Result.new(hosts: valid.uniq.freeze, rejected_count: invalid.length)
  end

  def valid_hostname?(entry)
    HOSTNAME.match?(entry) && !IPV4.match?(entry)
  end

  # The list handed to config.hosts: the parsed hosts, or a deny-all placeholder.
  def for_rails(raw)
    result = parse(raw)
    result.configured? ? result.hosts : [ DENY_ALL ]
  end

  # Platform health probes may use any Host header, so /up skips host authorization.
  def health_check_exclusion
    ->(request) { request.path == HEALTH_CHECK_PATH }
  end
end
