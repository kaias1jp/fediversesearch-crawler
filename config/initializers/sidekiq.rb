Sidekiq.configure_server do |config|
    config.redis = { url: 'redis://localhost:6379', namespace: 'fediversesearch_production' }
end

Sidekiq.configure_client do |config|
    config.redis = { url: 'redis://localhost:6379', namespace: 'fediversesearch_production' }
end
