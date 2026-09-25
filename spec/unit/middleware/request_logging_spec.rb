# frozen_string_literal: true

require "stringio"

RSpec.describe Challenge::Middleware::RequestLogging do
  let(:output) { StringIO.new }
  let(:logger) { Logger.new(output, formatter: ->(_severity, _time, _name, message) { "#{message}\n" }) }
  let(:response) { [202, { "secret-header" => "sensitive-response" }, ["sensitive-body"]] }
  let(:downstream) { ->(_env) { response } }
  let(:middleware) { described_class.new(downstream, logger: logger) }

  def events
    output.string.lines.map { |line| JSON.parse(line) }
  end

  it "logs entry before dispatch and completion with a shared generated ID without changing the response" do
    app = lambda do |_env|
      expect(events.map { |event| event["event"] }).to eq(["request_started"])
      response
    end
    result = described_class.new(app, logger: logger).call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/products")

    expect(result).to equal(response)
    started, completed = events
    expect(started).to include("method" => "POST", "route" => "/products")
    expect(completed).to include("event" => "request_completed", "status" => 202, "request_id" => started["request_id"])
    expect(started["request_id"]).to match(/\A[0-9a-f-]{36}\z/)
    expect(completed["duration_ms"]).to be >= 0
    expect(Time.iso8601(completed["timestamp"]).utc?).to be(true)
  end

  it "omits credentials, query strings, client IDs, resource IDs and response data" do
    %w[/auth/login /products/sensitive-id /jobs/sensitive-id /sensitive-path].each do |path|
      middleware.call(
        "REQUEST_METHOD" => "POST", "PATH_INFO" => path,
        "QUERY_STRING" => "password=sensitive-query", "HTTP_AUTHORIZATION" => "Bearer sensitive-token",
        "HTTP_COOKIE" => "sensitive-cookie", "HTTP_X_REQUEST_ID" => "sensitive-client-id",
        "HTTP_IDEMPOTENCY_KEY" => "sensitive-key", "REMOTE_ADDR" => "sensitive-ip",
        "challenge.user_id" => "sensitive-user", "rack.input" => StringIO.new(' {"password":"sensitive-password"}')
      )
    end

    expect(output.string).not_to include("sensitive")
    expect(events.map { |event| event["route"] }.uniq).to eq(["/auth/login", "/products/:id", "/jobs/:id", "unmatched"])
    expect(events.first.keys).to match_array(%w[event timestamp request_id method route])
    expect(events.last.keys).to match_array(%w[event timestamp request_id method route status duration_ms])
  end

  it "does not log arbitrary method text and generates a different ID for each request" do
    2.times { middleware.call("REQUEST_METHOD" => "secret\nforged", "PATH_INFO" => "/health") }

    expect(events.map { |event| event["method"] }.uniq).to eq(["OTHER"])
    expect(events.select { |event| event["event"] == "request_started" }.map { |event| event["request_id"] }.uniq.size).to eq(2)
  end

  it "records unhandled failure without logging exception details or swallowing it" do
    error = StandardError.new("sensitive-exception")
    app = ->(_env) { raise error }

    expect { described_class.new(app, logger: logger).call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/products") }
      .to raise_error { |raised| expect(raised).to equal(error) }
    expect(events.last).to include("status" => 500, "event" => "request_completed")
    expect(output.string).not_to include("sensitive-exception")
  end

  it "continues serving requests if the log output fails" do
    allow(logger).to receive(:info).and_raise(IOError)

    expect(middleware.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/health")).to equal(response)
  end
end
