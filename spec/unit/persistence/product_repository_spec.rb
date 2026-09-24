# frozen_string_literal: true

RSpec.describe Challenge::Persistence::ProductRepository do
  subject(:repository) { described_class.new(build_database) }

  let(:now) { Time.utc(2026, 9, 18, 12, 0, 0) }

  def create(id:, name: "Laptop", created_at: now)
    repository.create(requested_by_user_id: "1", id: id, name: name, created_at: created_at)
  end

  it "round trips a product" do
    create(id: "product-1")

    expect(repository.find("product-1")).to have_attributes(id: "product-1", name: "Laptop", created_at: now)
  end

  it "returns nothing for an unknown product" do
    expect(repository.find("product-1")).to be_nil
  end

  it "lists the most recently created product first" do
    create(id: "older", created_at: now)
    create(id: "newer", created_at: now + 60)

    expect(repository.paginate(requested_by_user_id: "1", limit: 20, offset: 0).fetch(:products).map(&:id)).to eq(["newer", "older"])
  end

  it "applies limit and offset while counting the full collection" do
    4.times { |index| create(id: "product-#{index}") }

    result = repository.paginate(requested_by_user_id: "1", limit: 2, offset: 2)

    expect(result.fetch(:products).map(&:id)).to eq(["product-1", "product-0"])
    expect(result.fetch(:total)).to eq(4)
  end

  it "lists nothing when no product exists" do
    expect(repository.paginate(requested_by_user_id: "1", limit: 20, offset: 0)).to eq(products: [], total: 0)
  end
end
