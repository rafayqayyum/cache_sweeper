# frozen_string_literal: true

class RenameArticlesJob < ActiveJob::Base
  def perform(title)
    Article.find_each { |article| article.update!(title:) }
  end
end
