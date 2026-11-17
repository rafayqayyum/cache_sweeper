# frozen_string_literal: true

Rails.application.routes.draw do
  patch "/articles/:id", to: lambda { |env|
    request = ActionDispatch::Request.new(env)
    Article.find(request.path_parameters[:id]).update!(title: request.params[:title])
    [200, {}, [Rails.cache.exist?("articles/index").to_s]]
  }
end
