# frozen_string_literal: true

RSpec.describe Challenge::Workers::ProductWorker do
  subject(:worker) { described_class.new(process_due_jobs: process_due_jobs, interval: 0.01) }

  let(:process_due_jobs) { instance_double(Challenge::UseCases::ProcessDueJobs, call: 0) }

  after { worker.stop }

  it "processes due jobs on every tick" do
    worker.tick

    expect(process_due_jobs).to have_received(:call)
  end

  it "survives a tick that fails" do
    allow(process_due_jobs).to receive(:call).and_raise(StandardError, "database is gone")

    expect { worker.tick }.not_to raise_error
  end

  it "keeps processing in the background until it is stopped" do
    ticks = Queue.new
    allow(process_due_jobs).to receive(:call) { ticks << :ticked }

    worker.start

    expect(ticks.pop(timeout: 2)).to eq(:ticked)
    expect(worker).to be_running
  end

  it "is no longer running once stopped" do
    worker.start
    worker.stop

    expect(worker).not_to be_running
  end
end
