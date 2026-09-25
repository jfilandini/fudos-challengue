# frozen_string_literal: true

RSpec.describe Challenge::UseCases::ProcessDueJobs do
  subject(:process_due_jobs) do
    described_class.new(job_repository: jobs, product_repository: products, unit_of_work: database, clock: clock)
  end

  let(:database) { build_database }
  let(:jobs) { Challenge::Persistence::JobRepository.new(database) }
  let(:products) { Challenge::Persistence::ProductRepository.new(database) }
  let(:clock) { FrozenClock.new }

  def enqueue(run_at: clock.now)
    jobs.create(id: "job-1", product_id: "product-1", product_name: "Laptop", run_at: run_at, now: clock.now)
  end

  it "creates the product, completes the due job and counts it as processed" do
    enqueue

    expect(process_due_jobs.call).to eq(1)
    expect(products.find("product-1")).to have_attributes(name: "Laptop")
    expect(jobs.find("job-1")).to be_completed
  end

  it "leaves a job untouched until its delay has elapsed" do
    enqueue(run_at: clock.now + 5)

    expect(process_due_jobs.call).to eq(0)
    expect(products.find("product-1")).to be_nil
  end

  it "creates the product once the delay has elapsed" do
    enqueue(run_at: clock.now + 5)
    process_due_jobs.call

    clock.advance(5)
    process_due_jobs.call

    expect(products.find("product-1")).not_to be_nil
  end

  it "has nothing left to do on a second pass" do
    enqueue
    process_due_jobs.call

    expect(process_due_jobs.call).to eq(0)
  end

  it "marks a job as failed instead of raising when the product cannot be created" do
    enqueue
    allow(products).to receive(:create).and_raise(StandardError, "database is gone")

    expect { process_due_jobs.call }.not_to raise_error
    expect(jobs.find("job-1")).to be_failed
  end

  it "leaves no product behind when the job cannot be completed" do
    enqueue
    allow(jobs).to receive(:mark_completed).and_raise(StandardError, "database is gone")

    process_due_jobs.call

    expect(products.find("product-1")).to be_nil
    expect(jobs.find("job-1")).to be_failed
  end
end
