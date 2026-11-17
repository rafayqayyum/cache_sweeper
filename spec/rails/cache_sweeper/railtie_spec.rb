# frozen_string_literal: true

require "rails_helper"

RSpec.describe CacheSweeper::Railtie do
  let(:article) { Article.create!(title: "First", body: "Body") }

  describe "boot" do
    it "raises sweep errors in local environments" do
      expect(CacheSweeper.config.raise_errors).to be(true)
    end

    it "loads the sweepers in the configured paths, skipping missing ones" do
      expect(CacheSweeper.registry.rules.map(&:sweeper)).to eq([ArticleSweeper, ArticleSweeper])
    end

    it "attaches the log subscriber" do
      expect(ActiveSupport::LogSubscriber.log_subscribers).to include(an_instance_of(CacheSweeper::LogSubscriber))
    end
  end

  describe "reloading" do
    it "rebuilds the registry with the reloaded classes" do
      previous = Article

      Rails.application.reloader.reload!

      expect(Article).not_to be(previous)
      expect(CacheSweeper.registry.rules.map(&:model)).to eq([Article, Article])
    end

    it "keeps sweeping exactly once per change after a reload" do
      Rails.application.reloader.reload!
      record = Article.create!(title: "First")

      events = instrumented("sweep.cache_sweeper") { record.update!(title: "Second") }

      expect(events.size).to eq(1)
    end
  end

  describe "executor batching" do
    let(:executor) { Rails.application.executor }

    before do
      article
      enqueued_jobs.clear
      seed_cache("articles/index", "articles/#{article.id}")
    end

    it "defers deletions until the unit of work completes" do
      executor.wrap do
        article.update!(title: "Second")
        expect(cached?("articles/index")).to be(true)
      end

      expect(cached?("articles/index")).to be(false)
    end

    it "deletes the keys of the whole unit of work at once" do
      events = instrumented("delete.cache_sweeper") do
        executor.wrap do
          article.update!(title: "Second")
          Article.find(article.id).update!(title: "Third")
        end
      end

      expect(events.map { |event| event.payload[:keys] }).to eq([["articles/#{article.id}", "articles/index"]])
    end

    it "flushes when the unit of work raises" do
      expect do
        executor.wrap do
          article.update!(title: "Second")
          raise "request failed"
        end
      end.to raise_error("request failed")

      expect(cached?("articles/index")).to be(false)
    end

    it "enqueues one async job per unit of work" do
      executor.wrap do
        article.update!(body: "Second")
        article.update!(body: "Third")
      end

      expect(enqueued_jobs).to contain_exactly(delete_job(["articles/#{article.id}/body"], queue: :low))
    end

    it "sweeps after a web request, once the response is done" do
      response = Rack::MockRequest.new(Rails.application).patch("/articles/#{article.id}", params: { title: "Second" })

      expect(response.body).to eq("true")
      expect(article.reload.title).to eq("Second")
      expect(cached?("articles/index")).to be(false)
    end

    it "sweeps after a job, in one deduplicated delete" do
      other = Article.create!(title: "Other")

      events = instrumented("delete.cache_sweeper") { ActiveJob::Base.execute(RenameArticlesJob.new("Renamed").serialize) }

      expect(events.map { |event| event.payload[:keys] })
        .to eq([["articles/#{article.id}", "articles/index", "articles/#{other.id}"]])
    end

    context "with a pending key limit" do
      around do |example|
        CacheSweeper.config.max_pending_keys = 2
        example.run
      ensure
        CacheSweeper.config.max_pending_keys = 1_000
      end

      it "flushes progressively during a long job instead of holding every key until it ends" do
        other = Article.create!(title: "Other")

        events = instrumented("delete.cache_sweeper") { ActiveJob::Base.execute(RenameArticlesJob.new("Renamed").serialize) }

        expect(events.map { |event| event.payload[:keys] })
          .to eq([["articles/#{article.id}", "articles/index"], ["articles/#{other.id}", "articles/index"]])
      end
    end
  end

  describe "logging" do
    let(:output) { StringIO.new }
    let(:logger) { ActiveSupport::Logger.new(output) }

    before do
      article
      allow(ActiveSupport::LogSubscriber).to receive(:logger).and_return(logger)
    end

    it "logs sweeps and deletions at debug level" do
      article.update!(title: "Second")

      expect(output.string).to include("CacheSweeper ArticleSweeper swept", "CacheSweeper deleted")
    end

    it "stays quiet above debug level" do
      logger.level = :info

      article.update!(title: "Second")

      expect(output.string).to be_empty
    end

    context "when a sweep fails" do
      around do |example|
        CacheSweeper.config.raise_errors = false
        example.run
      ensure
        CacheSweeper.config.raise_errors = true
      end

      it "logs the failure at error level" do
        logger.level = :error
        allow(Rails.cache).to receive(:delete_multi).and_raise("cache down")

        article.update!(title: "Second")

        expect(output.string).to include("CacheSweeper failed: RuntimeError: cache down")
      end
    end
  end
end
