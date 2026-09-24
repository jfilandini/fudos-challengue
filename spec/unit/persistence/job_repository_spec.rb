# frozen_string_literal: true

RSpec.describe Challenge::Persistence::JobRepository do
  subject(:repository) { described_class.new(build_database) }

  let(:now) { Time.utc(2026, 9, 18, 12, 0, 0) }

  def create(id: "job-1", run_at: now)
    repository.create(id: id, product_id: "product-1", product_name: "Laptop", run_at: run_at, now: now)
  end

  it "creates a job that is pending and scheduled" do
    job = create(run_at: now + 5)

    expect(job).to be_pending
    expect(job).to have_attributes(product_id: "product-1", product_name: "Laptop", run_at: now + 5)
  end

  it "round trips a job" do
    create

    expect(repository.find("job-1")).to have_attributes(id: "job-1", product_name: "Laptop")
  end

  it "returns nothing for an unknown job" do
    expect(repository.find("job-1")).to be_nil
  end

  it "considers a job due once its scheduled time has arrived" do
    create(run_at: now)

    expect(repository.due(now).map(&:id)).to eq(["job-1"])
  end

  it "holds back a job whose scheduled time is still in the future" do
    create(run_at: now + 5)

    expect(repository.due(now)).to be_empty
    expect(repository.due(now + 5).map(&:id)).to eq(["job-1"])
  end

  it "stops returning a job once it has been completed" do
    create(run_at: now)
    repository.claim_next(now)
    repository.mark_completed("job-1", now + 1)

    expect(repository.due(now + 1)).to be_empty
    expect(repository.find("job-1")).to be_completed
  end

  it "stops returning a job once it has failed" do
    create(run_at: now)
    repository.claim_next(now)
    repository.mark_failed("job-1", now + 1)

    expect(repository.due(now + 1)).to be_empty
    expect(repository.find("job-1")).to be_failed
  end

  it "records when a job last changed" do
    create(run_at: now)
    repository.claim_next(now)
    repository.mark_completed("job-1", now + 1)

    expect(repository.find("job-1").updated_at).to eq(now + 1)
  end
end
