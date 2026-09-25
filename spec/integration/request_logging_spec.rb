# frozen_string_literal: true

require "stringio"

RSpec.describe "Request logging across the stack" do
  it "logs static responses and authentication rejections" do
    output = StringIO.new
    original_stdout = $stdout
    $stdout = output
    get "/AUTHORS"
    get "/products", {}, "HTTP_AUTHORIZATION" => "Bearer sensitive-token"

    events = output.string.lines.map { |line| JSON.parse(line) }
    completed = events.select { |event| event["event"] == "request_completed" }
    expect(events.size).to eq(4)
    expect(completed).to include(include("route" => "/AUTHORS", "status" => 200))
    expect(completed).to include(include("route" => "/products", "status" => 401))
    expect(output.string).not_to include("sensitive-token")
  ensure
    $stdout = original_stdout
  end
end
