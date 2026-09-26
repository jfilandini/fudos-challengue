# frozen_string_literal: true

require "tmpdir"
require "timeout"
require "rbconfig"

RSpec.describe "Independent job processors" do
  def connect(path)
    Challenge::Persistence::Database.new(path).setup!
  end

  def seed(database, count)
    jobs = Challenge::Persistence::JobRepository.new(database)
    count.times do |index|
      jobs.create(id: "job-#{index}", product_id: "product-#{index}", product_name: "Coffee",
                  requested_by_user_id: "1", idempotency_key: "request-#{index}", run_at: FrozenClock.new.now, now: FrozenClock.new.now)
    end
  end

  def processor(database)
    Challenge::UseCases::ProcessDueJobs.new(
      job_repository: Challenge::Persistence::JobRepository.new(database),
      product_repository: Challenge::Persistence::ProductRepository.new(database),
      unit_of_work: database, clock: FrozenClock.new
    )
  end

  it "processes shared jobs exactly once across competing processes" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "shared.sqlite3")
      database = connect(path)
      seed(database, 20)
      database.close
      children = 3.times.map do
        ready_r, ready_w = IO.pipe
        go_r, go_w = IO.pipe
        pid = Process.spawn(
          RbConfig.ruby, "-rbundler/setup", File.expand_path("../../fixtures/job_processor.rb", __dir__),
          path, "process", 3 => ready_w, 4 => go_r
        )
        ready_w.close
        go_r.close
        [pid, ready_r, go_w]
      end
      Timeout.timeout(15) do
        children.each { |_, ready, _| expect(ready.read).to eq("ready") }
        children.each { |_, _, go| go.write("!"); go.close }
        children.each { |pid, _, _| expect(Process.wait2(pid).last.success?).to be(true) }
      end
      database = connect(path)
      expect(database.execute("SELECT COUNT(*) AS n FROM products").first["n"]).to eq(20)
      expect(database.execute("SELECT status, COUNT(*) AS n FROM jobs GROUP BY status"))
        .to eq([{ "status" => "completed", "n" => 20 }])
      database.close
    ensure
      children&.each do |pid, ready, go|
        ready.close rescue nil
        go.close rescue nil
        Process.kill('KILL', pid) rescue nil
        Process.wait(pid) rescue nil
      end
    end
  end

  it "retains the committed claim and rolls back product creation if a worker dies" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "crash.sqlite3")
      database = connect(path)
      seed(database, 1)
      database.close
      ready_r, ready_w = IO.pipe
      pid = Process.spawn(
        RbConfig.ruby, "-rbundler/setup", File.expand_path("../../fixtures/job_processor.rb", __dir__),
        path, "crash", 3 => ready_w
      )
      ready_w.close
      Timeout.timeout(10) { expect(ready_r.read(1)).to eq("!") }
      Process.kill('KILL', pid)
      Process.wait(pid)
      database = connect(path)
      jobs = Challenge::Persistence::JobRepository.new(database)
      expect(jobs.find_for_user("job-0", requested_by_user_id: "1")).to be_in_progress
      expect(processor(database).call).to eq(0)
      expect(database.execute("SELECT * FROM products")).to be_empty
      database.close
    ensure
      ready_r&.close rescue nil
      Process.kill('KILL', pid) rescue nil
      Process.wait(pid) rescue nil
    end
  end
end
