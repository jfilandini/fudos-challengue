# frozen_string_literal: true

RSpec.describe "Job claiming" do
  let(:database) { build_database }
  let(:jobs) { Challenge::Persistence::JobRepository.new(database) }
  let(:now) { Time.utc(2026, 9, 18, 12) }

  def create(id, run_at: now, created_at: now)
    jobs.create(id: id, product_id: "product-#{id}", product_name: "Coffee", run_at: run_at, now: created_at)
  end

  it "claims eligible jobs by due time, creation time and ID" do
    create("future", run_at: now + 1)
    create("later")
    create("b", created_at: now - 1)
    create("a", created_at: now - 1)
    create("oldest-due", run_at: now - 1)
    expect(4.times.map { jobs.claim_next(now).id }).to eq(%w[oldest-due a b later])
    expect(jobs.claim_next(now)).to be_nil
    expect(jobs.find("future")).to be_pending
  end

  it "commits in_progress and does not claim the same job twice" do
    create("one")
    claimed = jobs.claim_next(now)
    expect(claimed).to be_in_progress
    expect(jobs.find("one")).to eq(claimed)
    expect(jobs.claim_next(now)).to be_nil
  end

  it "only completes or fails in_progress jobs and preserves terminal states" do
    create("one")
    expect { jobs.mark_completed("one", now) }
      .to raise_error(Challenge::Persistence::JobRepository::InvalidTransition)
    expect(jobs.mark_failed("one", now)).to be(false)
    expect(jobs.find("one")).to be_pending
    jobs.claim_next(now)
    jobs.mark_completed("one", now)
    expect(jobs.mark_failed("one", now)).to be(false)
    expect { jobs.mark_completed("one", now) }
      .to raise_error(Challenge::Persistence::JobRepository::InvalidTransition)
    expect(jobs.find("one")).to be_completed

    create("two")
    jobs.claim_next(now)
    expect(jobs.mark_failed("two", now)).to be(true)
    expect { jobs.mark_completed("two", now) }
      .to raise_error(Challenge::Persistence::JobRepository::InvalidTransition)
    expect(jobs.find("two")).to be_failed
  end
end
