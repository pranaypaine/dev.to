require "rails_helper"

RSpec.describe SidekiqTracker, sidekiq_inline: true do
  let(:worker) { Articles::UpdateAnalyticsWorker.new }
  let(:user_id) { 1 }
  let(:job_id) { "abc123cdef" }
  let(:message) do
    {
      "class" => "Articles::UpdateAnalyticsWorker",
      "queue" => "low_priority",
      "args" => [[[[asset_hash]]]],
      "retry" => true,
      "jid" => job_id,
      "created_at" => 123,
      "enqueued_at" => 456
    }
  end
  let(:queue) { "indexing" }

  it "logs start and end data for a job" do
    expect(Rails.logger).to receive(:info).with(
      hash_including(
        asset_id: [14_250_980],
        client_id: [1_000_002],
        tag: "Articles::UpdateAnalyticsWorker",
        job_uuid: "abc123cdef",
        actor: "sidekiq_worker",
        queue: "low_priority",
        enqueued_at: "1970-01-01T00:07:36+00:00",
        created_at: "1970-01-01T00:02:03+00:00",
        sidekiq_retry: true,
        sidekiq_retry_count: 0,
        action: "start",
      ),
    ).once

    expect(Rails.logger).to receive(:info).with(
      hash_including(
        asset_id: [14_250_980],
        client_id: [1_000_002],
        tag: "Articles::UpdateAnalyticsWorker",
        job_uuid: "abc123cdef",
        actor: "sidekiq_worker",
        queue: "low_priority",
        enqueued_at: "1970-01-01T00:07:36+00:00",
        created_at: "1970-01-01T00:02:03+00:00",
        sidekiq_retry: true,
        sidekiq_retry_count: 0,
        action: "finish",
        duration: anything,
        memory_rss_diff: anything,
      ),
    ).once

    subject.call(worker, message, queue) {}
  end

  it "logs if an error occurs" do
    expect(Rails.logger).to receive(:info).with(
      hash_including(
        asset_id: [14_250_980],
        client_id: [1_000_002],
        tag: "Articles::UpdateAnalyticsWorker",
        job_uuid: "abc123cdef",
        actor: "sidekiq_worker",
        queue: "low_priority",
        enqueued_at: "1970-01-01T00:07:36+00:00",
        created_at: "1970-01-01T00:02:03+00:00",
        sidekiq_retry: true,
        sidekiq_retry_count: 0,
        action: "start",
      ),
    ).once

    expect(Rails.logger).to receive(:info).with(
      hash_including(
        asset_id: [14_250_980],
        client_id: [1_000_002],
        tag: "Articles::UpdateAnalyticsWorker",
        job_uuid: "abc123cdef",
        actor: "sidekiq_worker",
        queue: "low_priority",
        enqueued_at: "1970-01-01T00:07:36+00:00",
        created_at: "1970-01-01T00:02:03+00:00",
        sidekiq_retry: true,
        sidekiq_retry_count: 0,
        action: "failed",
        duration: anything,
        memory_rss_diff: anything,
      ),
    ).once

    expect do
      subject.call(worker, message, queue) { raise StandardError }
    end.to raise_error(StandardError)
  end

  it "logs error params if they are present" do
    message["error_message"] = "undefined method"
    message["error_class"] = "NoMethodError"
    message["retry_count"] = 5
    expect(Rails.logger).to receive(:info).with(
      hash_including(
        actor: "sidekiq_worker",
        sidekiq_retry: true,
        sidekiq_retry_count: 5,
        action: "start",
        error_message: message["error_message"],
        error_class: message["error_class"].to_s,
        retry_count: message["retry_count"],
      ),
    ).once

    expect(Rails.logger).to receive(:info).with(
      hash_including(
        actor: "sidekiq_worker",
        sidekiq_retry: true,
        sidekiq_retry_count: 5,
        action: "finish",
        error_message: message["error_message"],
        error_class: message["error_class"].to_s,
        retry_count: message["retry_count"],
      ),
    ).once

    subject.call(worker, message, queue) {}
  end

  it "logs argument even if worker does not have an argument hash method" do
    class MockJob
      TEAM_TAG = "".freeze
      include Sidekiq::Worker

      def perform(args); end
    end

    message["class"] = "MockJob"
    message["args"] = [{ "foo" => "bar" }]
    expect(Rails.logger).to receive(:info).with(
      hash_including(
        tag: "MockJob",
        job_uuid: "abc123cdef",
        actor: "sidekiq_worker",
        queue: "low_priority",
        enqueued_at: "1970-01-01T00:07:36+00:00",
        created_at: "1970-01-01T00:02:03+00:00",
        sidekiq_retry: true,
        sidekiq_retry_count: 0,
        action: "start",
        job_args: message["args"].to_s,
      ),
    ).once

    expect(Rails.logger).to receive(:info).with(
      hash_including(
        tag: "MockJob",
        job_uuid: "abc123cdef",
        actor: "sidekiq_worker",
        queue: "low_priority",
        enqueued_at: "1970-01-01T00:07:36+00:00",
        created_at: "1970-01-01T00:02:03+00:00",
        sidekiq_retry: true,
        sidekiq_retry_count: 0,
        action: "finish",
        duration: anything,
        memory_rss_diff: anything,
        job_args: message["args"].to_s,
      ),
    ).once

    subject.call(MockJob.new, message, "low_priority") {}
  end

  it "assigns team ownership" do
    expect(TeamOwner).to receive(:assign).with(worker.class::TEAM_TAG)
    subject.call(worker, message, queue) {}
  end

  it "sends TEAM_TAG to monitoring service" do
    expect(SidekiqStats::STATSD_CLIENT).to receive(:increment).with(
      "sidekiq.worker.hits", tags: [
        "action:start",
        "queue:low_priority",
        "worker_name:Articles::UpdateAnalyticsWorker",
      ]
    )
    expect(SidekiqStats::STATSD_CLIENT).to receive(:increment).with(
      "sidekiq.worker.hits", tags: [
        "action:finish",
        "queue:low_priority",
        "worker_name:Articles::UpdateAnalyticsWorker",
      ]
    )
    subject.call(worker, message, queue) {}
  end

  context "when the job has retried" do
    before do
      allow(Rails.logger).to receive(:info)
    end

    let(:retried_message) do
      message.merge("retry_count" => 2)
    end

    it "logs that there was a retry" do
      expect(Rails.logger).to receive(:info).with(
        hash_including(
          sidekiq_retry_count: 2,
        ),
      )
      subject.call(worker, retried_message, queue) {}
    end
  end
end
