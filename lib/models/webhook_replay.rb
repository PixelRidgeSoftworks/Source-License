# frozen_string_literal: true

# WebhookReplay model - records processed webhooks to prevent replays
class WebhookReplay < Sequel::Model(:webhook_replays)
  plugin :timestamps, update_on_create: true

  def before_create
    self.processed_at ||= Time.now
    super
  end
end
