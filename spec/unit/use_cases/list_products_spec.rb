# frozen_string_literal: true

RSpec.describe Challenge::UseCases::ListProducts do
  subject(:list_products) { described_class.new(product_repository: products) }

  let(:products) { Challenge::Persistence::ProductRepository.new(build_database) }
  let(:now) { Time.utc(2026, 9, 18, 12, 0, 0) }

  it "lists nothing while no product exists" do
    expect(list_products.call(requested_by_user_id: "1")).to have_attributes(products: [], page: 1, per_page: 20, total: 0, total_pages: 0)
  end

  it "lists the most recently created product first" do
    products.create(requested_by_user_id: "1", id: "older", name: "Mouse", created_at: now)
    products.create(requested_by_user_id: "1", id: "newer", name: "Laptop", created_at: now + 60)

    expect(list_products.call(requested_by_user_id: "1").products.map(&:id)).to eq(["newer", "older"])
  end
  it "calculates metadata for a partially filled last page" do
    3.times { |index| products.create(requested_by_user_id: "1", id: index.to_s, name: "Product", created_at: now + index) }

    result = list_products.call(requested_by_user_id: "1", page: 2, per_page: 2)

    expect(result.products.map(&:id)).to eq(["0"])
    expect(result).to have_attributes(page: 2, per_page: 2, total: 3, total_pages: 2)
  end

  it "rejects invalid pagination for non-HTTP callers" do
    expect { list_products.call(requested_by_user_id: "1", page: 0) }.to raise_error(ArgumentError)
    expect { list_products.call(requested_by_user_id: "1", per_page: 101) }.to raise_error(ArgumentError)
  end

end
