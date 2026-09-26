# frozen_string_literal: true

RSpec.describe Challenge::UseCases::EnqueueProductCreation do
  subject(:enqueue) { described_class.new(job_repository: jobs, clock: clock, delay_seconds: 5) }

  let(:jobs) { Challenge::Persistence::JobRepository.new(build_database) }
  let(:clock) { FrozenClock.new }

  it "records the request as a pending job" do
    job = enqueue.call(name: "Laptop", requested_by_user_id: "1", idempotency_key: SecureRandom.uuid)

    expect(job).to be_pending
    expect(job.product_name).to eq("Laptop")
    expect(job.requested_by_user_id).to eq("1")
    expect(jobs.find_for_user(job.id, requested_by_user_id: "1")).to eq(job)
  end

  it "schedules the job for the configured delay" do
    expect(enqueue.call(name: "Laptop", requested_by_user_id: "1", idempotency_key: SecureRandom.uuid).run_at).to eq(clock.now + 5)
  end

  it "gives every request its own job and product identifiers" do
    first = enqueue.call(name: "Laptop", requested_by_user_id: "1", idempotency_key: SecureRandom.uuid)
    second = enqueue.call(name: "Laptop", requested_by_user_id: "1", idempotency_key: SecureRandom.uuid)

    expect([first.id, first.product_id]).not_to include(second.id, second.product_id)
  end

  it "withholds the job from the worker until the delay has elapsed" do
    job = enqueue.call(name: "Laptop", requested_by_user_id: "1", idempotency_key: SecureRandom.uuid)

    expect(jobs.claim_next(clock.now)).to be_nil
    expect(jobs.find_for_user(job.id, requested_by_user_id: "1")).to be_pending
    expect(jobs.claim_next(clock.now + 5)).to have_attributes(id: job.id, status: "in_progress")
  end
end
