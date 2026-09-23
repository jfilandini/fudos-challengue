# frozen_string_literal: true

require_relative "app/boot"

container = Challenge::Container.new
container.product_worker.start

run Challenge::Application.build(container)
