# frozen_string_literal: true

RSpec.describe Challenge::UseCases::EnqueueProductCreation do
  subject(:enqueue) { described_class.new(job_repository: jobs, clock: clock, delay_seconds: 5) }

  let(:jobs) { Challenge::Persistence::JobRepository.new(build_database) }
  let(:clock) { FrozenClock.new }

  it "records the request as a pending job" do
    job = enqueue.call(name: "Laptop")

    expect(job).to be_pending
    expect(job.product_name).to eq("Laptop")
    expect(jobs.find(job.id)).to eq(job)
  end

  it "schedules the job for the configured delay" do
    expect(enqueue.call(name: "Laptop").run_at).to eq(clock.now + 5)
  end

  it "gives every request its own job and product identifiers" do
    first = enqueue.call(name: "Laptop")
    second = enqueue.call(name: "Laptop")

    expect([first.id, first.product_id]).not_to include(second.id, second.product_id)
  end

  it "withholds the job from the worker until the delay has elapsed" do
    job = enqueue.call(name: "Laptop")

    expect(jobs.due(clock.now)).to be_empty
    expect(jobs.due(clock.now + 5).map(&:id)).to eq([job.id])
  end
end
