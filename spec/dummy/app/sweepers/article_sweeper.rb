# frozen_string_literal: true

class ArticleSweeper < CacheSweeper::Base
  delivery :batched

  watch Article, only: :title do |article|
    ["articles/#{article.id}", "articles/index"]
  end

  watch Article, only: :body, delivery: :async, queue: :low do |article|
    "articles/#{article.id}/body"
  end
end
