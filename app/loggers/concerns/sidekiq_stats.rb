class SidekiqStats
  # report timing and other sidekiq job data to statsd
  STATSD_CLIENT = DataDogStatsClient
  START_ACTIONS = %w[start].freeze
  FINISH_ACTIONS = %w[finish failed].freeze

  attr_reader :tags

  def call(worker_log_hash)
    build_tags(worker_log_hash)

    report_hit
    report_memory_use(worker_log_hash)

    report_latency(worker_log_hash) if start_action?(worker_log_hash)
    report_duration(worker_log_hash) if finish_action?(worker_log_hash)
  end

  def client
    STATSD_CLIENT
  end

  private

  def report_hit
    client.increment("sidekiq.worker.hits", tags: tags)
  end

  def report_latency(worker_log_hash)
    return unless worker_log_hash[:enqueued_at]

    latency = Time.now.to_f - Time.parse(worker_log_hash[:enqueued_at]).to_f
    client.gauge("sidekiq.worker.latency", latency, tags: tags)
  end

  def report_duration(worker_log_hash)
    return unless worker_log_hash[:duration]

    duration = worker_log_hash[:duration]
    client.timing("sidekiq.worker.duration", duration * 1000, tags: tags)
  end

  def report_memory_use(worker_log_hash)
    return unless worker_log_hash[:memory_rss]

    rss = worker_log_hash[:memory_rss]
    client.gauge("sidekiq.worker.memory", rss, tags: tags)
  end

  def start_action?(worker_log_hash)
    worker_log_hash[:action].in? START_ACTIONS
  end

  def finish_action?(worker_log_hash)
    worker_log_hash[:action].in? FINISH_ACTIONS
  end

  def build_tags(worker_log_hash)
    @tags =
      [
        "action:#{worker_log_hash[:action]}",
        "queue:#{worker_log_hash[:queue]}",
        "worker_name:#{worker_log_hash[:tag]}",
      ]
  end
end
