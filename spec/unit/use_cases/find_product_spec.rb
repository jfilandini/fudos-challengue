# frozen_string_literal: true

RSpec.describe Challenge::UseCases::FindProduct do
  subject(:find_product) { described_class.new(product_repository: products) }

  let(:products) { Challenge::Persistence::ProductRepository.new(build_database) }

  it "returns the product it was asked for" do
    products.create(requested_by_user_id: "1", id: "product-1", name: "Laptop", created_at: Time.utc(2026, 9, 18, 12, 0, 0))

    expect(find_product.call("product-1", requested_by_user_id: "1")).to have_attributes(name: "Laptop")
  end

  it "returns nothing when the product does not exist" do
    expect(find_product.call("product-1", requested_by_user_id: "1")).to be_nil
  end
end
