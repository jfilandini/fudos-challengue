# frozen_string_literal: true

module Challenge
  class Container
    attr_reader :config

    def initialize(config = Config.from_env)
      @config = config
    end

    def clock
      @clock ||= Support::Clock.new
    end

    def database
      @database ||= Persistence::Database.new(config.database_path).setup!
    end

    def user_repository
      @user_repository ||= Persistence::UserRepository.new(database)
    end

    def product_repository
      @product_repository ||= Persistence::ProductRepository.new(database)
    end

    def job_repository
      @job_repository ||= Persistence::JobRepository.new(database)
    end

    def jwt_encoder
      @jwt_encoder ||= Support::JwtEncoder.new(
        secret: config.jwt_secret,
        ttl_seconds: config.jwt_ttl_seconds,
        clock: clock
      )
    end

    def authenticate_user
      @authenticate_user ||= UseCases::AuthenticateUser.new(
        user_repository: user_repository,
        jwt_encoder: jwt_encoder
      )
    end

    def enqueue_product_creation
      @enqueue_product_creation ||= UseCases::EnqueueProductCreation.new(
        job_repository: job_repository,
        clock: clock,
        delay_seconds: config.product_creation_delay_seconds
      )
    end

    def process_due_jobs
      @process_due_jobs ||= UseCases::ProcessDueJobs.new(
        job_repository: job_repository,
        product_repository: product_repository,
        unit_of_work: database,
        clock: clock
      )
    end

    def find_product
      @find_product ||= UseCases::FindProduct.new(product_repository: product_repository)
    end

    def list_products
      @list_products ||= UseCases::ListProducts.new(product_repository: product_repository)
    end

    def find_job
      @find_job ||= UseCases::FindJob.new(job_repository: job_repository)
    end

    def product_worker
      @product_worker ||= Workers::ProductWorker.new(
        process_due_jobs: process_due_jobs,
        interval: config.worker_poll_interval_seconds
      )
    end
  end
end
