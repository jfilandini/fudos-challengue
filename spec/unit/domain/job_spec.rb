# frozen_string_literal: true

RSpec.describe Challenge::Domain::Job do
  def job_with(status)
    described_class.new(id: "job", product_id: "product", product_name: "Laptop", status: status,
                        run_at: Time.now.utc, created_at: Time.now.utc, updated_at: Time.now.utc)
  end

  it "knows it is still pending" do
    expect(job_with(described_class::PENDING)).to be_pending
  end

  it "knows it is completed" do
    expect(job_with(described_class::COMPLETED)).to be_completed
  end

  it "knows it failed" do
    expect(job_with(described_class::FAILED)).to be_failed
  end
end
