class SidekiqTracker
  def call(worker, msg, _queue)
    start_time = Time.now.utc
    start_rss_size = ProcessSizing.rss_size
    base_hash = base_log_hash(worker, msg)
    track_start(base_hash, start_rss_size)
    yield
  rescue StandardError => e
    base_hash[:action] = "failed"
    raise e
  ensure
    track_finish(base_hash, start_time, start_rss_size)
  end

  def track_start(base_hash, start_rss_size)
    worker_log_hash = base_hash.reverse_merge(
      action: "start", memory_rss: start_rss_size,
    )
    log(worker_log_hash)
    send_to_monitoring(worker_log_hash)
  end

  def track_finish(base_hash, start_time, start_rss_size)
    end_time = Time.now.utc
    duration = end_time - start_time
    current_rss_size =  ProcessSizing.rss_size
    size_change = current_rss_size - start_rss_size
    worker_log_hash = base_hash.reverse_merge(
      action: "finish",
      duration: duration,
      memory_rss_diff: size_change,
      memory_rss: current_rss_size,
    )
    log(worker_log_hash)
    send_to_monitoring(worker_log_hash)
  end

  def base_log_hash(_worker, msg)
    base_hash = {
      tag: msg["class"].to_s,
      args: msg["args"],
      job_uuid: msg["jid"],
      actor: "sidekiq_worker",
      queue: msg["queue"],
      enqueued_at: Time.at(msg["enqueued_at"]).iso8601,
      created_at: Time.at(msg["created_at"]).iso8601,
      sidekiq_retry: msg["retry"], # This will be true or false
      sidekiq_retry_count: msg["retry_count"].is_a?(Integer) ? msg["retry_count"] : 0
    }
    add_error_keys(base_hash, msg)
  end

  def add_error_keys(base_hash, msg)
    return base_hash if msg["error_message"].blank?

    base_hash.merge(
      error_message: msg["error_message"],
      error_class: msg["error_class"].to_s,
      retry_count: msg["retry_count"],
    )
  end

  def log(worker_log_hash)
    Rails.logger.info(worker_log_hash)
  end

  def send_to_monitoring(worker_log_hash)
    SidekiqStats.new.call(worker_log_hash)
  end
end
