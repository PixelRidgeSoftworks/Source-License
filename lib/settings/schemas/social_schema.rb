# frozen_string_literal: true

# Source-License: Social Media Settings Schema
# Defines social media integration settings with their metadata

class Settings::Schemas::SocialSchema
  SOCIAL_SETTINGS = {
    'social.enable_social_links' => {
      type: 'boolean',
      default: false,
      category: 'social',
      description: 'Enable social media links in footer',
      web_editable: true,
    },
    'social.enable_github' => {
      type: 'boolean',
      default: false,
      category: 'social',
      description: 'Show GitHub link in footer',
      web_editable: true,
    },
    'social.github_url' => {
      type: 'url',
      default: '',
      category: 'social',
      description: 'GitHub profile or organization URL',
      web_editable: true,
    },
    'social.enable_twitter' => {
      type: 'boolean',
      default: false,
      category: 'social',
      description: 'Show Twitter/X link in footer',
      web_editable: true,
    },
    'social.twitter_url' => {
      type: 'url',
      default: '',
      category: 'social',
      description: 'Twitter/X profile URL',
      web_editable: true,
    },
    'social.enable_linkedin' => {
      type: 'boolean',
      default: false,
      category: 'social',
      description: 'Show LinkedIn link in footer',
      web_editable: true,
    },
    'social.linkedin_url' => {
      type: 'url',
      default: '',
      category: 'social',
      description: 'LinkedIn profile or company page URL',
      web_editable: true,
    },
    'social.enable_facebook' => {
      type: 'boolean',
      default: false,
      category: 'social',
      description: 'Show Facebook link in footer',
      web_editable: true,
    },
    'social.facebook_url' => {
      type: 'url',
      default: '',
      category: 'social',
      description: 'Facebook page URL',
      web_editable: true,
    },
    'social.enable_youtube' => {
      type: 'boolean',
      default: false,
      category: 'social',
      description: 'Show YouTube link in footer',
      web_editable: true,
    },
    'social.youtube_url' => {
      type: 'url',
      default: '',
      category: 'social',
      description: 'YouTube channel URL',
      web_editable: true,
    },
    'social.enable_discord' => {
      type: 'boolean',
      default: false,
      category: 'social',
      description: 'Show Discord link in footer',
      web_editable: true,
    },
    'social.discord_url' => {
      type: 'url',
      default: '',
      category: 'social',
      description: 'Discord server invite URL',
      web_editable: true,
    },
  }.freeze

  class << self
    def settings
      SOCIAL_SETTINGS
    end
  end
end
