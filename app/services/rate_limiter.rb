# Tiny fixed-window counter kept in process memory. The app runs as exactly one
# Puma worker, so a shared in-process store is sufficient and needs no database.
class RateLimiter
  STORE = ActiveSupport::Cache::MemoryStore.new(size: 2.megabytes)

  def initialize(name:, limit:, period:, store: STORE)
    @name = name
    @limit = limit
    @period = period
    @store = store
  end

  def throttled?(key)
    @store.read(cache_key(key)).to_i >= @limit
  end

  # Records one event. The window starts at the first event for the key.
  def hit(key)
    @store.increment(cache_key(key), 1, expires_in: @period) ||
      @store.write(cache_key(key), 1, expires_in: @period)
  end

  def self.reset!
    STORE.clear
  end

  private

  def cache_key(key) = "rl:#{@name}:#{key}"
end
