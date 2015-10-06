require 'exception_notification/sidekiq'

if !Rails.env.test?
  Sidekiq.configure_server do |config|
    config.redis = { url: 'redis://localhost:6379/0', namespace: "sidekiq_podfilter_#{Rails.env}" }
  end

  Sidekiq.configure_client do |config|
    config.redis = { url: 'redis://localhost:6379/0', namespace: "sidekiq_podfilter_#{Rails.env}" }
  end
end
