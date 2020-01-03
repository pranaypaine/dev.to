require "rails_helper"

RSpec.describe SidekiqStats do
  let(:stats_class) { subject }

  let(:client) do
    double("statsd",
           increment: 1,
           gauge: 2,
           timing: 3)
  end

  let(:start_hash) do
    {
      action: "start",
      actor: "sidekiq_worker",
      created_at: "1970-01-01T00:02:03+00:00",
      enqueued_at: "1970-01-01T00:07:36+00:00",
      job_uuid: "abc123cdef",
      memory_rss: 211_951_616,
      queue: "low_priority",
      sidekiq_retry: true,
      sidekiq_retry_count: 0,
      tag: "Articles::UpdateAnalyticsWorker"
    }
  end

  let(:finish_hash) { start_hash.merge(action: "finish", duration: 2.0) }
  let(:start_tags) { ["action:start", "queue:low_priority", "worker_name:Articles::UpdateAnalyticsWorker"] }
  let(:finish_tags) { ["action:finish", "queue:low_priority", "worker_name:Articles::UpdateAnalyticsWorker"] }
  let(:start_time) { Time.new(1970, 1, 1, 0, 8, 0, 0) } #  "1970-01-01T00:08:00.000+00:00"

  before do
    stub_const("SidekiqStats::STATSD_CLIENT", client)
  end

  around do |example|
    Timecop.freeze(start_time) do
      example.run
    end
  end

  describe "call" do
    it "increments hits" do
      expect(client).to receive(:increment).with("sidekiq.worker.hits", tags: start_tags)

      stats_class.call(start_hash)
    end

    it "logs latency for start actions" do
      # 08:00 - 07:36 = 24.0s
      expect(client).to receive(:gauge).with("sidekiq.worker.latency", 24.0, tags: start_tags)

      stats_class.call(start_hash)
    end

    it "logs duration for finish actions" do
      expect(client).to receive(:timing).with("sidekiq.worker.duration", 2000.0, tags: finish_tags)

      stats_class.call(finish_hash)
    end

    it "logs memory use" do
      expect(client).to receive(:gauge).with("sidekiq.worker.memory", 211_951_616, tags: start_tags)

      stats_class.call(start_hash)
    end
  end
end
